##############################################################################
# security.tf — NexCloud TCC
# Security Groups, WAF, ACM, IAM Role EC2
# Requisitos: R03 (Segurança), R04 (HTTPS), R12 (Isolamento de rede)
##############################################################################

##############################################################################
# Secret header CloudFront → ALB
#
# Um valor aleatório é gerado pelo Terraform e configurado como custom header
# no CloudFront origin. O ALB listener valida esse header, garantindo que
# apenas requisições originadas do CloudFront sejam aceitas.
#
# O valor NÃO é exposto em documentação pública — ele fica no state Terraform.
##############################################################################

resource "random_password" "cf_origin_secret" {
  length  = 32
  special = false
}

##############################################################################
# Security Group — ALB
#
# O ALB aceita HTTPS na porta 443 da internet (necessário pois o CloudFront
# pode vir de qualquer IP do AWS CloudFront prefix list).
# O header secreto no listener HTTPS garante que apenas o CloudFront passe.
##############################################################################

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-sg-alb"
  description = "ALB - aceita 80 (redirect) e 443 da internet via CloudFront"
  vpc_id      = aws_vpc.main.id

  # HTTP para redirecionar para HTTPS
  ingress {
    description      = "HTTP redirect"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  # HTTPS — aceito de qualquer IP pois CloudFront usa IPs distribuídos globalmente.
  # A proteção real é o custom header validado pelo listener rule abaixo.
  ingress {
    description      = "HTTPS via CloudFront"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    description = "Saida irrestrita para health checks nas EC2"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-sg-alb"
  }

  lifecycle {
    create_before_destroy = true
  }
}

##############################################################################
# Security Group — EC2
# EC2 aceita somente HTTP porta 80 vindo do SG do ALB.
# Sem SSH aberto — acesso administrativo via AWS SSM Session Manager.
##############################################################################

resource "aws_security_group" "ec2" {
  name        = "${local.name_prefix}-sg-ec2"
  description = "EC2 - aceita HTTP:80 apenas do ALB. Sem SSH."
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP do ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Saida irrestrita - updates via NAT Gateway, APIs AWS via VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-sg-ec2"
  }

  lifecycle {
    create_before_destroy = true
  }
}

##############################################################################
# ACM — Certificado para CloudFront (us-east-1 obrigatório)
##############################################################################

resource "aws_acm_certificate" "cloudfront" {
  count = var.use_custom_domain ? 1 : 0
  provider = aws.us_east_1

  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  tags = {
    Name = "${local.name_prefix}-cert-cloudfront"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "acm_cloudfront_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cloudfront[0].domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "cloudfront" {
  count = var.use_custom_domain ? 1 : 0
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.cloudfront[0].arn
  validation_record_fqdns = [for r in aws_route53_record.acm_cloudfront_validation : r.fqdn]
}

##############################################################################
# ACM — Certificado para o ALB (sa-east-1)
#
# O CloudFront utiliza origin.<dominio> como origem HTTPS.
# Esse hostname aponta por Alias para o ALB e o certificado abaixo cobre
# o dominio, permitindo validacao TLS correta entre CloudFront e ALB.
# O trafego ALB -> EC2 permanece HTTP dentro da VPC privada.
##############################################################################

# Certificado ALB mantido para uso futuro com origin HTTPS, se necessário.
resource "aws_acm_certificate" "alb" {
  count = var.use_custom_domain ? 1 : 0
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  tags = {
    Name = "${local.name_prefix}-cert-alb"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "acm_alb_validation" {
  for_each = {
    for dvo in aws_acm_certificate.alb[0].domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "alb" {
  count = var.use_custom_domain ? 1 : 0
  certificate_arn         = aws_acm_certificate.alb[0].arn
  validation_record_fqdns = [for r in aws_route53_record.acm_alb_validation : r.fqdn]
}

##############################################################################
# WAF Web ACL — escopo CLOUDFRONT (us-east-1)
# Associado à distribuição CloudFront.
# Protege contra OWASP Top 10, SQLi, inputs maliciosos, IPs com má reputação
# e rate limiting. Não substitui Shield Standard para DDoS L3/L4.
##############################################################################

resource "aws_wafv2_web_acl" "main" {
  provider    = aws.us_east_1
  name        = "${local.name_prefix}-waf"
  description = "WAF Escola Tech - OWASP, SQLi, rate limiting"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "CommonRuleSet"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "SQLiRuleSet"
    priority = 2
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "SQLiRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "KnownBadInputs"
    priority = 3
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "KnownBadInputsMetric"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "IPReputationList"
    priority = 4
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "IPReputationListMetric"
      sampled_requests_enabled   = true
    }
  }

  # Rate limiting: bloqueia IPs que excedam 2000 req/5min
  rule {
    name     = "RateLimit"
    priority = 5
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitMetric"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "${local.name_prefix}-waf"
  }
}

##############################################################################
# IAM Role para EC2
##############################################################################

resource "aws_iam_role" "ec2_instance_role" {
  name = "${local.name_prefix}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = {
    Name = "${local.name_prefix}-ec2-role"
  }
}

# SSM Session Manager — acesso administrativo sem SSH
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch Agent — envio de logs e métricas
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Permissões S3 restritas ao bucket de assets (leitura) e backups (escrita)
resource "aws_iam_role_policy" "ec2_s3" {
  name = "${local.name_prefix}-ec2-s3"
  role = aws_iam_role.ec2_instance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadAssets"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::${local.name_prefix}-assets-${local.account_id}",
          "arn:aws:s3:::${local.name_prefix}-assets-${local.account_id}/*"
        ]
      },
      {
        Sid    = "WriteBackups"
        Effect = "Allow"
        Action = ["s3:PutObject"]
        Resource = [
          "arn:aws:s3:::${local.name_prefix}-backups-${local.account_id}/*"
        ]
      }
    ]
  })
}

# Permissão para o bootstrap taggear a própria instância
resource "aws_iam_role_policy" "ec2_tag_self" {
  name = "${local.name_prefix}-ec2-tag-self"
  role = aws_iam_role.ec2_instance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "TagSelf"
      Effect   = "Allow"
      Action   = ["ec2:CreateTags"]
      Resource = "arn:aws:ec2:${var.aws_region}:${local.account_id}:instance/*"
      Condition = {
        StringEquals = {
          "ec2:ResourceTag/ManagedBy" = "Terraform"
        }
      }
    }]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${local.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2_instance_role.name

  tags = {
    Name = "${local.name_prefix}-ec2-profile"
  }
}

##############################################################################
# Security Group — RDS PostgreSQL
#
# Banco privado: somente as EC2 da aplicação podem acessar TCP/5432.
# Não existe acesso público ao RDS.
##############################################################################

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-sg-rds"
  description = "RDS PostgreSQL - acesso somente das EC2 da aplicacao"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL somente das EC2"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  egress {
    description = "Saida para servicos AWS necessarios"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-sg-rds"
  }
}

##############################################################################
# IAM — EC2 pode ler somente o segredo gerenciado pelo RDS.
##############################################################################

resource "aws_iam_role_policy" "ec2_rds_secret" {
  name = "${local.name_prefix}-ec2-rds-secret"
  role = aws_iam_role.ec2_instance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "ReadRDSMasterSecret"
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = aws_db_instance.postgres.master_user_secret[0].secret_arn
    }]
  })
}


resource "aws_iam_role_policy" "ec2_rds_iam_auth" {
  name = "${local.name_prefix}-ec2-rds-iam-auth"
  role = aws_iam_role.ec2_instance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "ConnectAsApplicationUser"
      Effect   = "Allow"
      Action   = ["rds-db:connect"]
      Resource = "arn:aws:rds-db:${var.aws_region}:${local.account_id}:dbuser:${aws_db_instance.postgres.resource_id}/${var.db_app_username}"
    }]
  })
}
