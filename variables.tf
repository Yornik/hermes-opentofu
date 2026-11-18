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
  description = "Name prefix for all resources."
  type        = string
  default     = "hermes"
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
