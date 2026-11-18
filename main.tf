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

  # Dashboard login: yours if you set it, otherwise generated below. Both are stored in the state, so
  # `tofu output` shows them; they are seeded onto the instance at first boot only.
  dashboard_username = var.dashboard_username != null ? var.dashboard_username : random_pet.dashboard_username[0].id
  dashboard_password = sensitive(var.dashboard_password != null ? var.dashboard_password : "${random_integer.dashboard_password_number[0].result}-${random_pet.dashboard_password_words[0].id}!")

  # The node's tailnet name once it joins with `--hostname=<name>`; empty when tailnet_domain is unset,
  # in which case hermes-dashboard-setup detects the real name after you join.
  tailnet_fqdn = var.tailnet_domain == null ? "" : "${var.name}.${var.tailnet_domain}"

  # First-boot script (cloud-init, runs once as root): base packages, Tailscale (joined if
  # tailscale_auth_key is set, otherwise just installed), Hermes Agent (not configured) and, if
  # enable_tailnet_dashboard is set, Caddy plus the hermes-dashboard unit and setup helper.
  # See files/bootstrap.sh.tftpl for the details.
  # Add `--skip-browser` to its Hermes installer call to leave out the browser tools if disk or
  # memory gets tight.
  bootstrap = templatefile("${path.module}/files/bootstrap.sh.tftpl", {
    enable_dashboard       = var.enable_tailnet_dashboard
    dashboard_fqdn         = local.tailnet_fqdn
    node_name              = var.name
    tailscale_auth_key     = var.tailscale_auth_key == null ? "" : var.tailscale_auth_key
    dashboard_username     = local.dashboard_username
    dashboard_password_b64 = base64encode(local.dashboard_password)
    dashboard_unit         = chomp(file("${path.module}/files/hermes-dashboard.service"))
    dashboard_setup_script = chomp(file("${path.module}/files/hermes-dashboard-setup.sh"))
  })

  # Optional var.user_data is a shell snippet appended after the bootstrap. Always marked
  # sensitive: it can carry the Tailscale auth key, and this keeps it out of plan output.
  user_data       = sensitive(var.user_data == null ? local.bootstrap : "${local.bootstrap}\n${var.user_data}")
  user_data_bytes = length(nonsensitive(local.user_data))

  # Whether a Tailscale auth key was given (the key itself is sensitive; this boolean is not).
  has_auth_key = nonsensitive(var.tailscale_auth_key != null)

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
    # ami: the "latest" AMI parameter moves over time; don't replace the instance when it does.
    # user_data: cloud-init runs it once, on first boot, so a later edit (for example removing the
    # one-off Tailscale auth key from your environment) would only stop and restart the instance for
    # nothing. To re-run it on a fresh instance: tofu apply -replace=aws_instance.this
    ignore_changes = [ami, user_data]

    precondition {
      condition     = local.user_data_bytes <= 16000
      error_message = "user_data is ${local.user_data_bytes} bytes; EC2 allows at most 16384. Shorten var.user_data or the bootstrap files."
    }

    precondition {
      condition     = !local.ssh_enabled || local.key_name != null
      error_message = "SSH is enabled (ssh_allow_current_ip) but there is no key to log in with. Set ssh_public_key (creates a key pair) or ssh_key_name (existing key pair)."
    }
  }
}

# Warnings, not errors: both are fine in the right situation, so they must not block a plan.
check "break_glass_access" {
  assert {
    condition     = local.ssh_enabled || local.key_name != null
    error_message = "SSH is closed and no key pair is attached. If Tailscale does not come up you cannot get in, and adding a key pair later means replacing the instance. Keep ssh_public_key set as break-glass access: the security group stays closed until you set ssh_allow_current_ip = true."
  }
}

check "a_way_in_exists" {
  assert {
    condition     = local.ssh_enabled || local.has_auth_key
    error_message = "SSH is closed and no tailscale_auth_key is set. That is fine if this instance has already joined your tailnet; on a new instance nothing could reach it (there is no SSM)."
  }
}

# --- Dashboard login, generated unless you set dashboard_username / dashboard_password ---
# Example result: user "happy-otter", password "14-quietly-happy-otter!". Random values live in the
# state, so they stay the same across applies. They are only used at first boot (see user_data).

resource "random_pet" "dashboard_username" {
  count = var.dashboard_username == null ? 1 : 0

  length    = 2
  separator = "-"
}

resource "random_pet" "dashboard_password_words" {
  count = var.dashboard_password == null ? 1 : 0

  length    = var.dashboard_password_words
  separator = "-"
}

resource "random_integer" "dashboard_password_number" {
  count = var.dashboard_password == null ? 1 : 0

  min = 10
  max = 99
}
