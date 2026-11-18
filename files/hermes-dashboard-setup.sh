#!/bin/bash
# hermes-dashboard-setup: put the Hermes web dashboard on your tailnet.
#
# Three ways it runs (all safe to repeat):
#
#   * First boot with tailscale_auth_key set in OpenTofu: the node has already joined, so the
#     first-boot script calls it with no arguments and it reads the real tailnet name.
#
#   * First boot with only tailnet_domain set: the first-boot script calls it with
#     HERMES_DASHBOARD_FQDN=<name>.<tailnet>.ts.net, so everything is wired before you join.
#     Then you only join:   sudo tailscale up --ssh --hostname=<name>
#
#   * By hand, as root, AFTER the node has joined Tailscale. It reads the node's real tailnet
#     name from Tailscale, so use this when neither variable was set, or when Tailscale gave
#     the node a different name than expected (for example "hermes-1" after a name clash):
#         sudo hermes-dashboard-setup
#
# What it does:
#   1. lets Caddy fetch the TLS certificate for the tailnet name from the local tailscaled
#   2. creates the dashboard login (user "admin", random password) the first time
#   3. points Hermes at its public URL, writes the Caddyfile, starts the dashboard and Caddy
#
# The tailnet name matters because Hermes validates the Host header of every request against the
# public URL declared here.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this as root: sudo hermes-dashboard-setup" >&2
  exit 1
fi

die() { echo "ERROR: $*" >&2; exit 1; }

backend_state() { tailscale status --json 2>/dev/null | jq -r '.BackendState // empty' 2>/dev/null || true; }

fqdn="${HERMES_DASHBOARD_FQDN:-}"
unattended=0
if [ -n "$fqdn" ]; then
  # First-boot call: the name is given, and the node has not joined the tailnet yet.
  unattended=1
else
  # Right after a join (including the auth-key join at first boot) the name can take a moment to appear.
  for _ in $(seq 1 60); do
    [ "$(backend_state)" = "Running" ] && break
    sleep 1
  done
  [ "$(backend_state)" = "Running" ] || die "Tailscale is not up (state: '$(backend_state)').
Run 'sudo tailscale up --ssh', approve the node, then run this script again."
  for _ in $(seq 1 30); do
    fqdn="$(tailscale status --json 2>/dev/null | jq -r '.Self.DNSName // empty' | sed 's/\.$//')" || fqdn=""
    [ -n "$fqdn" ] && break
    sleep 1
  done
fi

case "$fqdn" in
  *.ts.net) ;;
  *) die "no MagicDNS name ending in .ts.net (got: '${fqdn:-none}').
Enable MagicDNS and HTTPS certificates on the DNS page of the Tailscale admin console, then run this script again." ;;
esac

command -v caddy >/dev/null || die "caddy is not installed (the first-boot script did not finish?). See /var/log/cloud-init-output.log"
sudo -u ubuntu -H bash -lc 'command -v hermes' >/dev/null || die "hermes is not installed for the ubuntu user. See /var/log/cloud-init-output.log"

# --- 1. let Caddy (user "caddy") get the certificate from tailscaled ---------------------------
if ! grep -qs '^TS_PERMIT_CERT_UID=caddy$' /etc/default/tailscaled; then
  sed -i '/^TS_PERMIT_CERT_UID=/d' /etc/default/tailscaled
  echo 'TS_PERMIT_CERT_UID=caddy' >> /etc/default/tailscaled
  systemctl restart tailscaled
  if [ "$unattended" -eq 0 ]; then
    for _ in $(seq 1 30); do
      [ "$(backend_state)" = "Running" ] && break
      sleep 1
    done
    [ "$(backend_state)" = "Running" ] || die "tailscaled did not come back up after the restart"
  fi
fi

# --- 2. dashboard login + public URL -------------------------------------------------------------
env_dir=/etc/hermes-dashboard
env_file="$env_dir/dashboard.env"
install -d -m 0755 "$env_dir"

new_password=""
if [ ! -f "$env_file" ]; then
  new_password="$(openssl rand -hex 16)"
  (
    umask 077
    {
      echo "HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin"
      echo "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=$new_password"
      echo "HERMES_DASHBOARD_BASIC_AUTH_SECRET=$(openssl rand -hex 32)"
    } > "$env_file"
  )
fi
# The public URL follows the tailnet name, so refresh it on every run.
sed -i '/^HERMES_DASHBOARD_PUBLIC_URL=/d' "$env_file"
echo "HERMES_DASHBOARD_PUBLIC_URL=https://$fqdn" >> "$env_file"
chown root:root "$env_file"
chmod 600 "$env_file"

# --- 3. Caddy: HTTPS on the tailnet name, forwarding to the loopback-only dashboard --------------
cat > /etc/caddy/Caddyfile <<EOF
$fqdn {
	reverse_proxy 127.0.0.1:9119
}
EOF
caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1 \
  || die "the generated Caddyfile is invalid; run: caddy validate --config /etc/caddy/Caddyfile"

# --- 4. start everything -------------------------------------------------------------------------
systemctl daemon-reload
systemctl enable hermes-dashboard.service >/dev/null 2>&1
systemctl restart hermes-dashboard.service
systemctl enable caddy >/dev/null 2>&1
systemctl restart caddy
sleep 3

echo
if systemctl is-active --quiet hermes-dashboard.service; then
  echo "hermes-dashboard.service: running"
else
  echo "hermes-dashboard.service: NOT running. Check: journalctl -u hermes-dashboard -n 50" >&2
fi
if systemctl is-active --quiet caddy; then
  echo "caddy.service:            running"
else
  echo "caddy.service:            NOT running. Check: journalctl -u caddy -n 50" >&2
fi

echo
echo "Dashboard:  https://$fqdn   (only reachable from devices on your tailnet)"
if [ "$unattended" -eq 1 ]; then
  echo "            It answers once this node joins the tailnet as that name:"
  echo "            sudo tailscale up --ssh --hostname=${fqdn%%.*}"
fi
echo "Login:      admin"
# Never print the password into a log file: cloud-init-output.log is readable by every local user.
if [ -n "$new_password" ] && [ -t 1 ]; then
  echo "Password:   $new_password   (generated now; also stored root-only in $env_file)"
else
  echo "Password:   see $env_file (readable by root only):  sudo cat $env_file"
fi
