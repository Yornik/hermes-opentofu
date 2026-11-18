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
  default     = 30
}

variable "ubuntu_version" {
  description = "Ubuntu LTS release to launch (Canonical SSM parameter path segment)."
  type        = string
  default     = "26.04"
}

variable "subnet_id" {
  description = "Subnet to launch into. Null picks the first subnet of the default VPC."
  type        = string
  default     = null
}

variable "ssh_allowed_cidrs" {
  description = "CIDRs allowed to SSH (port 22), e.g. [\"203.0.113.10/32\"]. Empty (default) opens no inbound ports; use SSM Session Manager instead. Avoid 0.0.0.0/0."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.ssh_allowed_cidrs : can(cidrhost(c, 0))])
    error_message = "Every entry in ssh_allowed_cidrs must be a valid IPv4 CIDR block, e.g. 203.0.113.10/32."
  }
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
  description = "Optional shell snippet appended to the built-in first-boot bootstrap (which installs git, curl, tar, ca-certificates and libatomic1)."
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
