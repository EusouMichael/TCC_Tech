##############################################################################
# main.tf — NexCloud TCC
# Provider AWS + data sources globais
# Projeto: Escola Tech — Case 3
# Equipe: NexCloud | Região: sa-east-1 (São Paulo)
##############################################################################

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

  # Backend local — state armazenado em terraform.tfstate neste diretório.
  # Para uso em equipe, crie o bucket S3 manualmente e descomente o bloco
  # abaixo, removendo o bloco vazio acima.
  #
  # backend "s3" {
  #   bucket  = "nexcloud-terraform-state-<account-id>"
  #   key     = "escolatech/terraform.tfstate"
  #   region  = "sa-east-1"
  #   encrypt = true
  # }
  #
  # Nota: DynamoDB locking é opcional a partir do Terraform 1.7+.
  # Consulte a documentação da versão em uso antes de adicionar dynamodb_table.
}

##############################################################################
# Provider principal — sa-east-1 (São Paulo)
##############################################################################

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

# Provider us-east-1 — obrigatório para ACM (CloudFront) e WAF (CLOUDFRONT scope)
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

##############################################################################
# Data sources
##############################################################################

data "aws_caller_identity" "current" {}

data "aws_canonical_user_id" "current" {}

data "aws_cloudfront_log_delivery_canonical_user_id" "main" {}

# AMI Amazon Linux 2023 via parâmetro SSM oficial da AWS.
# Isso garante sempre a AMI mais recente e compatível, sem depender de filtros
# frágeis por nome. Compatível com x86_64 / HVM / EBS / t3.small.
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

##############################################################################
# Locals
##############################################################################

locals {
  account_id  = data.aws_caller_identity.current.account_id
  name_prefix = "${var.project_name}-${var.environment}"
  ami_id      = data.aws_ssm_parameter.al2023_ami.value
}