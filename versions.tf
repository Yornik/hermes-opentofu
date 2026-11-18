terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  # Leave null to use the default credential chain (e.g. AWS_PROFILE from your SSO login).
  profile = var.aws_profile

  default_tags {
    tags = var.tags
  }
}
