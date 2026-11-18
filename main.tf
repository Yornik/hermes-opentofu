# Availability zones in the region that offer the instance type (m7i-flex is not in every AZ).
data "aws_ec2_instance_type_offerings" "this" {
  location_type = "availability-zone"

  filter {
    name   = "instance-type"
    values = [var.instance_type]
  }
}

# Latest Canonical Ubuntu LTS AMI (x86_64, gp3 EBS), resolved from Canonical's public SSM parameter.
data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/${var.ubuntu_version}/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

locals {
  # First AZ (alphabetically) that offers the instance type; null if none does (checked on the subnet).
  az = try(sort(data.aws_ec2_instance_type_offerings.this.locations)[0], null)

  # Runs once, on first boot (cloud-init). Installs what the Hermes installer needs:
  # git, curl, tar and CA certificates for the POSIX install script, and libatomic1, which the
  # managed Node.js links against and minimal Ubuntu images do not ship.
  # Also installs Tailscale from its official apt repo (codename taken from /etc/os-release).
  # Tailscale is NOT joined to a tailnet here, because that needs an auth key and secrets do not
  # belong in user_data. Join once by hand: `sudo tailscale up --ssh`.
  # Finally installs Hermes Agent for the `ubuntu` user (the installer puts everything under $HOME
  # and edits shell rc files, so it must not run as root). `--non-interactive` skips the setup
  # wizard and the gateway service install, so Hermes is installed but NOT configured: run
  # `hermes setup` and `hermes gateway install` yourself. Add `--skip-browser` to the installer
  # call to leave out the browser tools if disk or memory gets tight.
  # Tailscale goes before Hermes so a failed Hermes install cannot block the Tailscale install.
  # Output ends up in /var/log/cloud-init-output.log.
  bootstrap = <<-EOT
    #!/bin/bash
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y --no-install-recommends ca-certificates curl git libatomic1 tar

    . /etc/os-release
    mkdir -p --mode=0755 /usr/share/keyrings
    curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/$VERSION_CODENAME.noarmor.gpg" -o /usr/share/keyrings/tailscale-archive-keyring.gpg
    curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/$VERSION_CODENAME.tailscale-keyring.list" -o /etc/apt/sources.list.d/tailscale.list
    apt-get update -y
    apt-get install -y tailscale

    curl -fsSL https://hermes-agent.nousresearch.com/install.sh -o /tmp/hermes-install.sh
    chmod 755 /tmp/hermes-install.sh
    sudo -u ubuntu -H bash /tmp/hermes-install.sh --non-interactive
    rm -f /tmp/hermes-install.sh
  EOT

  # Optional var.user_data is a shell snippet appended after the bootstrap.
  user_data = var.user_data == null ? local.bootstrap : "${local.bootstrap}\n${var.user_data}"

  # The only inbound rule: SSH from the public IP of the machine running tofu, as a single /32.
  ssh_enabled     = var.ssh_allow_current_ip
  current_ip_cidr = local.ssh_enabled ? "${chomp(data.http.current_ip[0].response_body)}/32" : null
  key_name        = var.ssh_public_key != null ? aws_key_pair.this[0].key_name : var.ssh_key_name
}

# Public IP of the machine running tofu, only looked up when ssh_allow_current_ip is true.
data "http" "current_ip" {
  count = var.ssh_allow_current_ip ? 1 : 0

  url = "https://checkip.amazonaws.com"

  lifecycle {
    # checkip.amazonaws.com returns the address AWS sees the request coming from (your router's or
    # VPN's public egress IP), never a LAN address. Still refuse anything that is not a public IPv4
    # (garbage, IPv6, or a private/loopback/link-local range) rather than build an SG rule from it.
    postcondition {
      condition = (
        can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", chomp(self.response_body))) &&
        !can(regex("^(10\\.|127\\.|169\\.254\\.|192\\.168\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.)", chomp(self.response_body)))
      )
      error_message = "checkip.amazonaws.com did not return a public IPv4 address, so no SSH rule will be created from it."
    }
  }
}

# --- SSH key (optional): created from a public key you supply ---

resource "aws_key_pair" "this" {
  count = var.ssh_public_key != null ? 1 : 0

  key_name   = var.name
  public_key = var.ssh_public_key
}

# Access is SSH from the current IP and Tailscale. There is deliberately no IAM instance profile,
# so SSM Session Manager is not available and the instance has no AWS API permissions.

# --- Network: a dedicated VPC with one public subnet (this account has no default VPC) ---

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = var.name
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = var.name
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 0)
  availability_zone       = local.az
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name}-public"
  }

  lifecycle {
    precondition {
      condition     = local.az != null
      error_message = "No availability zone in ${var.region} offers ${var.instance_type}. Choose another instance_type or region."
    }
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.name}-public"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "this" {
  name        = "${var.name}-ec2"
  description = "${var.name} instance: SSH from one IP only, all outbound"
  vpc_id      = aws_vpc.this.id
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# The only inbound rule on this security group: TCP 22 from the current public IP (/32).
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  count = local.ssh_enabled ? 1 : 0

  security_group_id = aws_security_group.this.id
  description       = "SSH from the IP tofu ran on"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = local.current_ip_cidr
}

# --- Instance ---

resource "aws_instance" "this" {
  ami                    = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.this.id]
  key_name               = local.key_name
  user_data              = local.user_data

  # The instance needs a public IP for outbound internet (and for SSH from your IP).
  associate_public_ip_address = true

  # The first-boot script downloads packages, so the default route must exist before the instance boots.
  depends_on = [aws_route_table_association.public]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 only
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = var.name
  }

  lifecycle {
    # "latest" AMI parameter moves over time; don't replace the instance when it does.
    ignore_changes = [ami]

    precondition {
      condition     = !local.ssh_enabled || local.key_name != null
      error_message = "SSH is enabled (ssh_allow_current_ip) but there is no key to log in with. Set ssh_public_key (creates a key pair) or ssh_key_name (existing key pair)."
    }
  }
}
