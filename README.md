# hermes-opentofu

OpenTofu config for deploying [Hermes Agent](https://github.com/NousResearch/hermes-agent) on a single EC2 instance.

## What it creates

- 1 EC2 instance: Ubuntu 26.04 LTS (latest Canonical AMI), `m7i-flex.large`, 75 GiB encrypted gp3 root volume, IMDSv2 only
- Security group whose **only inbound rule is SSH (TCP 22) from the public IP of the machine running `tofu`**, as a single `/32`. All outbound is allowed. There is no way to add other inbound sources through variables.
- No IAM role or instance profile: **SSM Session Manager is not enabled** and the instance has no AWS API permissions. Access is SSH, then Tailscale.
- First-boot bootstrap (`user_data`) that installs:
  - `git`, `curl`, `tar`, `ca-certificates` and `libatomic1` (the Hermes installer needs them; minimal Ubuntu images lack `libatomic1`)
  - [Tailscale](https://tailscale.com) from its official apt repo (installed, **not joined**)
  - Hermes Agent for the `ubuntu` user, via the official installer with `--non-interactive` (installed, **not configured**)
- A dedicated VPC (`10.200.0.0/16` by default) with one public subnet, an internet gateway and a route table, in an availability zone that offers the instance type. The instance has a public IP and reaches the internet through the internet gateway, so **no NAT gateway** is needed (or created). Region: `eu-central-1` by default.

State is local (`terraform.tfstate`, git-ignored). Add a remote backend before using this beyond a sandbox.

## Usage

```sh
cp terraform.tfvars.example terraform.tfvars   # then edit: set ssh_public_key
tofu init
tofu plan -out=tfplan
tofu apply tfplan
```

Log in with the sandbox account's credentials first (or set `aws_profile`). Common variables are in `variables.tf`:

| Variable | Default | Notes |
|---|---|---|
| `region` | `eu-central-1` | |
| `instance_type` | `m7i-flex.large` | 2 vCPU / 8 GiB |
| `vpc_cidr` | `10.200.0.0/16` | CIDR of the VPC this creates; the subnet is its first `/24` |
| `root_volume_size_gb` | `75` | can be grown later without replacing the instance |
| `ubuntu_version` | `26.04` | set `24.04` if a dependency does not support 26.04 yet |
| `ssh_allow_current_ip` | `true` | opens SSH to the IP `tofu` runs from (looked up via `checkip.amazonaws.com` at plan time); `false` = no inbound rules at all |
| `ssh_public_key` | `null` | public key to register as an EC2 key pair (login user: `ubuntu`) |
| `ssh_key_name` | `null` | alternative: name of an existing key pair |
| `user_data` | `null` | extra shell snippet appended after the built-in bootstrap |

Put your values in `terraform.tfvars` (git-ignored). With SSH enabled and no key, the plan fails with a message saying so.

The IP is looked up on **every plan**. If your IP changes (new network, VPN on/off), the next `tofu apply` updates the rule in place; until then SSH from the new IP is blocked. Behind a VPN or shared NAT the rule covers that egress address.

## Connect

```sh
ssh ubuntu@<public_ip>        # `tofu output ssh_command`
```

The first boot installs packages for a few minutes after the instance is up. To follow it:

```sh
cloud-init status --wait
tail -f /var/log/cloud-init-output.log
```

The public IP changes when the instance is stopped and started; attach an Elastic IP if you need it stable.

## Set up Hermes

Hermes is installed for the `ubuntu` user but not configured. After the first-boot script has finished, log in as `ubuntu` and run:

```sh
hermes setup             # provider, model, messaging platforms
hermes gateway install   # runs the gateway as a systemd service so it survives logout
```

If `hermes` is not found in your current shell, start a new login shell (the installer adds `~/.local/bin` to your shell rc files). Do not run Hermes in the foreground of an SSH session; it stops when the session ends.

## Set up Tailscale

Tailscale is installed and its daemon runs, but the node is **not joined** to a tailnet: joining needs an auth key, and secrets should not go in `user_data` (they end up in state and instance metadata). Join once, interactively:

```sh
sudo tailscale up --ssh
```

Open the printed URL to approve the node.

## Lock SSH down to Tailscale only

Once Tailscale works, remove the public SSH rule so the security group has **no inbound rules at all**. Tailscale only makes outbound connections, so it needs no open port.

SSM Session Manager is not enabled, so do this in order and do not skip the test:

1. **Join the tailnet** on the instance: `sudo tailscale up --ssh` (see above).
2. **Test from another device on your tailnet**, with the instance's tailnet name (`tailscale status`) or its `100.x` address (`tailscale ip -4` on the instance):

   ```sh
   ssh ubuntu@<tailnet-name-or-100.x-address>
   ```

   With `--ssh`, Tailscale authenticates you through the tailnet and your tailnet policy must allow it (the default policy lets you SSH to your own devices). Plain `sshd` over the tailnet address also works with your key.
3. **Only when step 2 works**, set this in `terraform.tfvars`:

   ```hcl
   ssh_allow_current_ip = false
   ```

4. Review and apply. The plan should show exactly one change: the SSH ingress rule being destroyed.

   ```sh
   tofu plan -out=tfplan
   tofu apply tfplan
   ```

5. **Check**: from a machine that is not on your tailnet, `ssh ubuntu@<public_ip>` should now time out, while the tailnet address still works.

**If you get locked out** (Tailscale stopped, node expired, tailnet policy changed): set `ssh_allow_current_ip = true` again and run `tofu apply` from the machine you want to SSH from. That is an AWS API change and needs no access to the instance.
