terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "EscolaTech"
      Environment = var.environment
      Team        = "NexCloud"
      ManagedBy   = "Terraform"
      Owner       = "NexCloud"
    }
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags {
    tags = {
      Project     = "EscolaTech"
      Environment = var.environment
      Team        = "NexCloud"
      ManagedBy   = "Terraform"
      Owner       = "NexCloud"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_canonical_user_id" "current" {}
data "aws_cloudfront_log_delivery_canonical_user_id" "main" {}

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  name_prefix = "${var.project_name}-${var.environment}"
  ami_id      = data.aws_ssm_parameter.al2023_ami.value
}
