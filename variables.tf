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
  description = "CIDRs allowed to SSH (port 22). Empty (default) opens no inbound ports; use SSM Session Manager instead."
  type        = list(string)
  default     = []
}

variable "ssh_key_name" {
  description = "Existing EC2 key pair name, only needed if ssh_allowed_cidrs is set. Null means no key pair."
  type        = string
  default     = null
}

variable "user_data" {
  description = "Optional cloud-init / shell script run on first boot."
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
