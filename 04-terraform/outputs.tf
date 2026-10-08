##############################################################################
# outputs.tf — NexCloud TCC
# Outputs exibidos após terraform apply
##############################################################################

# ── Rede ─────────────────────────────────────────────────────────────────────

output "vpc_id" {
  description = "ID da VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs das subnets públicas"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas"
  value       = aws_subnet.private[*].id
}

# ── ALB ──────────────────────────────────────────────────────────────────────

output "alb_dns_name" {
  description = "DNS name do ALB (use para testes diretos sem domínio customizado)"
  value       = aws_lb.main.dns_name
}

output "alb_arn" {
  description = "ARN do ALB"
  value       = aws_lb.main.arn
}

output "target_group_arn" {
  description = "ARN do Target Group"
  value       = aws_lb_target_group.main.arn
}

# ── CloudFront ───────────────────────────────────────────────────────────────

output "cloudfront_distribution_id" {
  description = "ID da distribuição CloudFront"
  value       = aws_cloudfront_distribution.main.id
}

output "cloudfront_domain_name" {
  description = "Domain name CloudFront — use este para acessar o site sem domínio registrado"
  value       = aws_cloudfront_distribution.main.domain_name
}

# ── ASG ──────────────────────────────────────────────────────────────────────

output "asg_name" {
  description = "Nome do Auto Scaling Group"
  value       = aws_autoscaling_group.main.name
}

# ── Route 53 ─────────────────────────────────────────────────────────────────

output "route53_zone_id" {
  description = "ID da Hosted Zone Route 53"
  value       = one(aws_route53_zone.main[*].zone_id)
}

output "route53_name_servers" {
  description = "Name servers — configure estes no registrador do domínio"
  value       = one(aws_route53_zone.main[*].name_servers)
}

# ── S3 ───────────────────────────────────────────────────────────────────────

output "s3_assets_bucket" {
  description = "Nome do bucket S3 de assets"
  value       = aws_s3_bucket.assets.bucket
}

output "s3_logs_bucket" {
  description = "Nome do bucket S3 de logs"
  value       = aws_s3_bucket.logs.bucket
}

output "s3_backups_bucket" {
  description = "Nome do bucket S3 de backups"
  value       = aws_s3_bucket.backups.bucket
}

# ── Monitoramento ────────────────────────────────────────────────────────────

output "sns_topic_arn" {
  description = "ARN do tópico SNS de alertas (confirme a assinatura no e-mail)"
  value       = aws_sns_topic.alerts.arn
}

output "cloudwatch_dashboard_name" {
  description = "Nome do dashboard CloudWatch"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}

# ── Website ───────────────────────────────────────────────────────────────────

output "website_url" {
  description = "URL do site (requer domínio registrado e DNS delegado)"
  value       = var.use_custom_domain ? "https://${var.domain_name}" : "N/A — use website_url_cloudfront"
}

output "website_url_cloudfront" {
  description = "URL do site via CloudFront diretamente (funciona sem domínio registrado)"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

# ── Segurança ─────────────────────────────────────────────────────────────────

# O valor do header secreto não deve ser exibido em logs de CI/CD.
output "cf_origin_secret_hint" {
  description = "Indicador — o header X-CF-Origin-Secret está configurado. Valor no state Terraform."
  value       = "configured — see terraform state"
  sensitive   = false
}

# ── Resumo ────────────────────────────────────────────────────────────────────

output "deployment_summary" {
  description = "Resumo do deployment"
  value = {
    project     = var.project_name
    environment = var.environment
    region      = var.aws_region
    domain      = var.use_custom_domain ? var.domain_name : "CloudFront default domain"
    asg         = "min=${var.asg_min_size} desired=${var.asg_desired_capacity} max=${var.asg_max_size}"
    instance    = var.instance_type
    backend     = "local (ver comentário em main.tf para backend S3)"
  }
}