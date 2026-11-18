data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Latest Canonical Ubuntu LTS AMI (x86_64, gp3 EBS), resolved from Canonical's public SSM parameter.
data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/${var.ubuntu_version}/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

locals {
  subnet_id = coalesce(var.subnet_id, sort(data.aws_subnets.default.ids)[0])

  # Runs once, on first boot (cloud-init). Installs what the Hermes installer needs:
  # git, curl, tar and CA certificates for the POSIX install script, and libatomic1, which the
  # managed Node.js links against and minimal Ubuntu images do not ship.
  # Output ends up in /var/log/cloud-init-output.log.
  bootstrap = <<-EOT
    #!/bin/bash
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y --no-install-recommends ca-certificates curl git libatomic1 tar
  EOT

  # Optional var.user_data is a shell snippet appended after the bootstrap.
  user_data = var.user_data == null ? local.bootstrap : "${local.bootstrap}\n${var.user_data}"

  ssh_enabled = length(var.ssh_allowed_cidrs) > 0
  key_name    = var.ssh_public_key != null ? aws_key_pair.this[0].key_name : var.ssh_key_name
}

# --- SSH key (optional): created from a public key you supply ---

resource "aws_key_pair" "this" {
  count = var.ssh_public_key != null ? 1 : 0

  key_name   = var.name
  public_key = var.ssh_public_key
}

# --- Access: SSM Session Manager (no inbound ports required) ---

data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name}-ec2"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.name}-ec2"
  role = aws_iam_role.this.name
}

# --- Network ---

resource "aws_security_group" "this" {
  name        = "${var.name}-ec2"
  description = "${var.name} instance: no inbound by default, all outbound"
  vpc_id      = data.aws_vpc.default.id
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = toset(var.ssh_allowed_cidrs)

  security_group_id = aws_security_group.this.id
  description       = "SSH"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = each.value
}

# --- Instance ---

resource "aws_instance" "this" {
  ami                    = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type          = var.instance_type
  subnet_id              = local.subnet_id
  vpc_security_group_ids = [aws_security_group.this.id]
  iam_instance_profile   = aws_iam_instance_profile.this.name
  key_name               = local.key_name
  user_data              = local.user_data

  # Default VPC subnets auto-assign a public IP, which the instance needs for outbound internet.
  associate_public_ip_address = true

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
      error_message = "ssh_allowed_cidrs is set but there is no key to log in with. Set ssh_public_key (creates a key pair) or ssh_key_name (existing key pair)."
    }
  }
}
