##############################################################################
# s3.tf — NexCloud TCC
# S3 Buckets: assets (site + estáticos), logs, backups
# Requisitos: R07 (Armazenamento), R08 (Backup de assets)
##############################################################################

locals {
  bucket_assets  = "${local.name_prefix}-assets-${local.account_id}"
  bucket_logs    = "${local.name_prefix}-logs-${local.account_id}"
  bucket_backups = "${local.name_prefix}-backups-${local.account_id}"
}

##############################################################################
# BUCKET 1 — Assets (site HTML + estáticos)
#
# Armazena o index.html e demais assets do site institucional.
# Privado — acesso via OAC pelo CloudFront.
# A EC2 também lê deste bucket no bootstrap para obter o index.html.
##############################################################################

resource "aws_s3_bucket" "assets" {
  bucket        = local.bucket_assets
  force_destroy = false

  tags = {
    Name    = local.bucket_assets
    Purpose = "Site assets — HTML, CSS, JS, images"
  }
}

resource "aws_s3_bucket_ownership_controls" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Permite apenas CloudFront (via OAC) e a EC2 (via IAM Role) acessarem
resource "aws_s3_bucket_policy" "assets" {
  bucket = aws_s3_bucket.assets.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOAC"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.assets.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
          }
        }
      },
      {
        Sid    = "AllowEC2Read"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.ec2_instance_role.arn
        }
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.assets.arn,
          "${aws_s3_bucket.assets.arn}/*"
        ]
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.assets]
}

resource "aws_s3_bucket_lifecycle_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = var.use_custom_domain ? ["https://${var.domain_name}", "https://www.${var.domain_name}"] : ["*"]
    max_age_seconds = 3600
  }
}

##############################################################################
# Upload do index.html para o S3
#
# O Terraform faz o upload do site para o bucket no apply.
# A EC2 obtém este arquivo no bootstrap, garantindo que o ASG crie novas
# instâncias com o site correto automaticamente.
##############################################################################

##############################################################################
# API — arquivos da aplicação Node.js
##############################################################################

resource "aws_s3_object" "api_package" {
  bucket       = aws_s3_bucket.assets.id
  key          = "api/package.json"
  source       = "${path.module}/../07-api/package.json"
  content_type = "application/json"
  etag         = filemd5("${path.module}/../07-api/package.json")
}

resource "aws_s3_object" "api_server" {
  bucket       = aws_s3_bucket.assets.id
  key          = "api/server.js"
  source       = "${path.module}/../07-api/server.js"
  content_type = "application/javascript"
  etag         = filemd5("${path.module}/../07-api/server.js")
}

resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.assets.id
  key          = "site/index.html"
  source       = "${path.module}/../05-website/index.html"
  content_type = "text/html; charset=utf-8"
  etag         = filemd5("${path.module}/../05-website/index.html")

  tags = {
    Name = "index.html"
  }

  depends_on = [aws_s3_bucket_public_access_block.assets]
}

##############################################################################
# BUCKET 2 — Logs (ALB + CloudFront)
##############################################################################

resource "aws_s3_bucket" "logs" {
  bucket        = local.bucket_logs
  force_destroy = true

  tags = {
    Name    = local.bucket_logs
    Purpose = "Access logs — ALB and CloudFront"
  }
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# CloudFront legacy logging via S3 ACL foi removido porque a conta do TCC possui
# um SCP que bloqueia s3:ListAllMyBuckets. O bucket permanece seguro com
# BucketOwnerEnforced; os logs do ALB continuam sendo entregues via bucket policy.

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "logs-lifecycle"
    status = "Enabled"

    filter {}

    transition {
      days          = var.s3_logs_transition_days # 30d → S3-IA
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.s3_logs_glacier_days # 90d → Glacier
      storage_class = "GLACIER"
    }

    expiration {
      days = var.s3_logs_expiration_days # 365d → delete
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Política de logs do ALB
# Usa logdelivery.elasticloadbalancing.amazonaws.com conforme documentação
# atual da AWS (a conta de serviço hardcoded está sendo descontinuada).
resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowALBLogs"
        Effect = "Allow"
        Principal = {
          Service = "logdelivery.elasticloadbalancing.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.logs.arn}/alb/AWSLogs/${local.account_id}/*"
      },
      {
        Sid    = "AllowALBGetBucketAcl"
        Effect = "Allow"
        Principal = {
          Service = "logdelivery.elasticloadbalancing.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.logs.arn
      },

    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.logs]
}

##############################################################################
# BUCKET 3 — Backups de assets e configurações
#
# NOTA: Este bucket armazena backups de assets estáticos e arquivos de
# configuração da aplicação. Não há banco de dados neste projeto.
# Backups de EBS são gerenciados pelo AWS Backup (ver backup.tf).
##############################################################################

resource "aws_s3_bucket" "backups" {
  bucket        = local.bucket_backups
  force_destroy = false

  tags = {
    Name    = local.bucket_backups
    Purpose = "Backups de assets e configuracoes da aplicacao"
  }
}

resource "aws_s3_bucket_ownership_controls" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "backup-lifecycle"
    status = "Enabled"

    filter {}

    transition {
      days          = 7
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "backups" {
  bucket = aws_s3_bucket.backups.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowEC2WriteBackups"
      Effect = "Allow"
      Principal = {
        AWS = aws_iam_role.ec2_instance_role.arn
      }
      Action   = ["s3:PutObject"]
      Resource = "${aws_s3_bucket.backups.arn}/*"
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.backups]
}