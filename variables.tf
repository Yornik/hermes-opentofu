variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-central-1"
}

variable "aws_profile" {
  description = "AWS CLI/SSO profile for the sandbox account. Null uses the default credential chain."
  type        = string
  default     = null
}

variable "name" {
  description = "Name prefix for all resources. Also the node's hostname in your tailnet, so it must be a valid DNS label (lowercase letters, digits, hyphens)."
  type        = string
  default     = "hermes"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.name))
    error_message = "name must be a lowercase DNS label: letters, digits and hyphens, not starting or ending with a hyphen."
  }
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "m7i-flex.large"
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 75
}

variable "ubuntu_version" {
  description = "Ubuntu LTS release to launch (Canonical SSM parameter path segment)."
  type        = string
  default     = "26.04"
}

variable "vpc_cidr" {
  description = "CIDR block of the dedicated VPC created for the instance. The public subnet is the first /24 inside it, so the prefix must be /24 or shorter."
  type        = string
  default     = "10.200.0.0/16"

  validation {
    condition     = can(cidrsubnet(var.vpc_cidr, 8, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block with a prefix length of /24 or shorter, e.g. 10.200.0.0/16."
  }
}

variable "ssh_allow_current_ip" {
  description = "Open SSH (TCP 22) to the public IP of the machine running tofu, and to nothing else. The IP is looked up via checkip.amazonaws.com at plan time and added as a /32; it is re-evaluated on every plan, so the rule follows your IP. Behind a VPN or shared NAT this is the VPN/NAT egress address. Set false to have no inbound rules at all, which leaves Tailscale as the only way in; only do that after Tailscale is joined and tested (SSM Session Manager is not enabled)."
  type        = bool
  default     = true
}

variable "ssh_public_key" {
  description = "Public key (e.g. contents of ~/.ssh/id_ed25519.pub) to register as an EC2 key pair. Needed to SSH in as the 'ubuntu' user. Takes precedence over ssh_key_name."
  type        = string
  default     = null
}

variable "ssh_key_name" {
  description = "Name of an existing EC2 key pair, as an alternative to ssh_public_key. Null means no key pair."
  type        = string
  default     = null
}

variable "enable_tailnet_dashboard" {
  description = "Install Caddy, a hermes-dashboard systemd unit and the hermes-dashboard-setup helper, so the Hermes web dashboard can be published on your tailnet (HTTPS, Hermes login) after you join Tailscale. Installs only: nothing is started or exposed until you run `sudo hermes-dashboard-setup`. No inbound security group rule is ever added."
  type        = bool
  default     = true
}

variable "tailscale_auth_key" {
  description = "Tailscale auth key. When set, the instance joins your tailnet at first boot (with Tailscale SSH on and the node named <name>), so you can set ssh_allow_current_ip = false and never open port 22. SECRET: pass it as TF_VAR_tailscale_auth_key, never in a committed file. Use a one-off (single-use) key with a short expiry: it ends up in the OpenTofu state, the saved plan and the instance's user-data. Generate it at https://login.tailscale.com/admin/settings/keys."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = var.tailscale_auth_key == null || can(regex("^tskey-[A-Za-z0-9_-]+$", var.tailscale_auth_key))
    error_message = "tailscale_auth_key does not look like a Tailscale auth key (expected tskey-auth-...). The value is not shown here because it is a secret."
  }
}

variable "dashboard_username" {
  description = "Username for the Hermes dashboard login. When null (default), OpenTofu generates two random words (for example \"happy-otter\"). Read it with `tofu output dashboard_username`."
  type        = string
  default     = null

  validation {
    condition     = var.dashboard_username == null || can(regex("^[a-z][a-z0-9_-]{2,31}$", var.dashboard_username))
    error_message = "dashboard_username must be 3-32 characters: lowercase letters, digits, underscore or hyphen, starting with a letter."
  }
}

variable "dashboard_password" {
  description = "Password for the Hermes dashboard login. When null (default), OpenTofu generates a passphrase like \"14-quietly-happy-otter!\" (a number, dictionary words and a symbol); read it with `tofu output -raw dashboard_password`. Set your own instead if you prefer: any passphrase generator works (for example Crypt::HSXKPasswd, or `openssl rand -hex 16`). SECRET: pass it as TF_VAR_dashboard_password. 16-128 printable ASCII characters (symbols and spaces are fine; it is carried base64-encoded and quoted). Either way it ends up in the OpenTofu state, saved plan and user-data like the other secrets here."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = var.dashboard_password == null || can(regex("^[ -~]{16,128}$", var.dashboard_password))
    error_message = "dashboard_password must be 16-128 printable ASCII characters (the value is not shown because it is a secret)."
  }
}

variable "dashboard_password_words" {
  description = "Number of random words in the generated dashboard password (ignored when dashboard_password is set). Each word adds roughly 9-10 bits on top of the ~6.5 bits of the two-digit number, so the default 3 is only about 30-35 bits: fine against casual guessing on a tailnet-only login, thin for something that opens a terminal. Use 6 or more for a stronger one, or set dashboard_password yourself."
  type        = number
  default     = 3

  validation {
    condition     = var.dashboard_password_words >= 3 && var.dashboard_password_words <= 10 && floor(var.dashboard_password_words) == var.dashboard_password_words
    error_message = "dashboard_password_words must be a whole number between 3 and 10."
  }
}

variable "tailnet_domain" {
  description = "Your tailnet's MagicDNS domain, e.g. \"your-tailnet.ts.net\" (Tailscale admin console, DNS page). When set (and no tailscale_auth_key), the dashboard is fully wired at first boot for the node name \"<name>.<tailnet_domain>\"; join with `sudo tailscale up --ssh --hostname=<name>`. With a tailscale_auth_key the real name is read after the join, so this is only used for the dashboard_url output. When both are null, run `sudo hermes-dashboard-setup` after joining. Not a secret, but identifying: put it in your git-ignored terraform.tfvars or TF_VAR_tailnet_domain, not in the repo."
  type        = string
  default     = null

  validation {
    condition     = var.tailnet_domain == null || can(regex("^[a-z0-9][a-z0-9-]*\\.ts\\.net$", var.tailnet_domain))
    error_message = "tailnet_domain must look like \"your-tailnet.ts.net\" (lowercase, ending in .ts.net)."
  }
}

variable "auto_reboot" {
  description = "Reboot automatically when unattended-upgrades installs a kernel or other update that requires it (for example a new kernel). Writes Unattended-Upgrade::Automatic-Reboot into /etc/apt/apt.conf.d on first boot; unattended-upgrades itself ships enabled with Ubuntu and installs security updates daily. Reboots only happen when nobody is logged in (Automatic-Reboot-WithUsers stays off) and at auto_reboot_time. Safe because the gateway is installed as a systemd service at first boot (install_gateway_service), so it comes back on its own."
  type        = bool
  default     = true
}

variable "auto_reboot_time" {
  description = "Time (24h clock) for automatic reboots caused by unattended-upgrades, when auto_reboot is true. The instance clock is UTC."
  type        = string
  default     = "02:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.auto_reboot_time))
    error_message = "auto_reboot_time must be a 24-hour clock time like \"02:00\"."
  }
}

variable "install_gateway_service" {
  description = "Install the Hermes gateway as ubuntu's systemd user service at first boot (hermes gateway install) and enable linger, so the gateway survives SSH logouts and server reboots. Needed for auto_reboot: without it, a reboot takes the bot down until someone logs in. The gateway starts with no chat platform configured and is harmless until you connect one."
  type        = bool
  default     = true
}

variable "user_data" {
  description = "Optional shell snippet appended to the built-in first-boot bootstrap (which installs git, curl, tar, ca-certificates, libatomic1, Tailscale and Hermes Agent, unconfigured)."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    Project     = "hermes"
    Environment = "sandbox"
    ManagedBy   = "opentofu"
  }
}
