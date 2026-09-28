terraform {
  required_version = ">= 1.11.5"

  backend "s3" {
    key          = "state/eks-cluster.tfstate"
    use_lockfile = true # Enables native S3 locking (OpenTofu 1.8+ / Terraform 1.9+)
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.66.0"
    }
  }
}
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "production"
      Project     = "cloud-native-architecture"
      ManagedBy   = "OpenTofu"
    }
  }
}