// Provider and environment configuration for application infrastructure.
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.100"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "realworld-devops"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

variable "aws_region" {
  description = "AWS region for this environment."
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Environment name used in resource names and tags."
  type        = string
  default     = "dev"
}

variable "db_instance_class" {
  description = "RDS instance class. The selected class must be available in the configured region."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_storage_gib" {
  description = "Initial encrypted RDS storage size in GiB."
  type        = number
  default     = 20

  validation {
    condition     = var.db_storage_gib >= 20
    error_message = "RDS PostgreSQL requires at least 20 GiB of allocated storage."
  }
}

locals {
  name = "realworld-${var.environment}"
}
