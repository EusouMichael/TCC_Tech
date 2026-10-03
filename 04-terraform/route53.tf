##############################################################################
# route53.tf — NexCloud TCC
# Hosted Zone + DNS Records + Health Check
# Requisito: R05 (DNS)
#
# NOTA: Esta configuração implementa DNS simples com alias para CloudFront
# e um health check de monitoramento. NÃO há failover ativo/passivo
# configurado — não existem registros PRIMARY/SECONDARY neste projeto.
# Se o endpoint principal falhar, o CloudFront e o ASG são responsáveis
# pela resiliência, não o Route 53 failover.
#
# Pré-requisito: o domínio (var.domain_name) deve estar registrado e seus
# name servers delegados para esta Hosted Zone. Sem isso, os registros DNS
# não terão efeito. Para testes sem domínio, use o domínio do CloudFront
# diretamente (output: cloudfront_domain_name).
##############################################################################

##############################################################################
# Hosted Zone
##############################################################################

resource "aws_route53_zone" "main" {
  name    = var.domain_name
  comment = "Hosted Zone Escola Tech — NexCloud TCC"

  tags = {
    Name   = "${local.name_prefix}-hosted-zone"
    Domain = var.domain_name
  }
}

##############################################################################
# Health Check — monitora o endpoint principal via CloudFront
#
# Não há integração com alarme CloudWatch neste health check para evitar
# dependência circular. O alarme de monitoramento está em monitoring.tf.
##############################################################################

resource "aws_route53_health_check" "main" {
  fqdn              = var.domain_name
  port              = 443
  type              = "HTTPS"
  resource_path     = var.health_check_path
  failure_threshold = 3
  request_interval  = 30
  measure_latency   = true

  tags = {
    Name = "${local.name_prefix}-health-check"
  }
}

##############################################################################
# DNS Records — alias para CloudFront
##############################################################################

# Apex (escolatech.com.br) — IPv4
resource "aws_route53_record" "apex" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

# www — IPv4
resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

# Apex — IPv6
resource "aws_route53_record" "apex_aaaa" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

# www — IPv6
resource "aws_route53_record" "www_aaaa" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "www.${var.domain_name}"
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}