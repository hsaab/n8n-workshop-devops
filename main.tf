# -----------------------------------------------------------------------------
# n8n DevOps Workshop Infrastructure
# -----------------------------------------------------------------------------
# This Terraform project provisions AWS infrastructure for a DevOps workshop
# where participants can provision EC2 instances and trigger disk space alerts.
#
# Resources created:
# - IAM roles for Lambda and EC2
# - Security group for EC2 instances (outbound only)
# - SNS topic for CloudWatch alerts
# - Four Lambda functions: provision, teardown, fill_disk, reset_disk
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# Data source to get current region
data "aws_region" "current" {}
