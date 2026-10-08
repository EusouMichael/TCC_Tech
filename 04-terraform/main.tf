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

# A conta usada no TCC está sujeita a um SCP que bloqueia s3:ListAllMyBuckets.
# Por isso não usamos data.aws_canonical_user_id, que faz uma chamada ao S3.
# O bucket de logs usa Object Ownership BucketOwnerEnforced e não depende de ACL.

# AMI Amazon Linux 2023 via DescribeImages.
# Evita dependência do Parameter Store/SSM, que também está bloqueado pelo SCP
# da conta. O filtro é restrito ao proprietário oficial Amazon e x86_64.
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

##############################################################################
# Locals
##############################################################################

locals {
  account_id  = data.aws_caller_identity.current.account_id
  name_prefix = "${var.project_name}-${var.environment}"
  ami_id      = data.aws_ami.al2023.id
}