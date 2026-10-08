##############################################################################
# cloudfront.tf — NexCloud TCC
# CloudFront Distribution — Escola Tech
# Requisitos: R04 (HTTPS), R06 (Performance CDN)
##############################################################################

##############################################################################
# Origin Access Control — S3 assets
##############################################################################

resource "aws_cloudfront_origin_access_control" "s3_assets" {
  name                              = "${local.name_prefix}-oac-assets"
  description                       = "OAC para S3 de assets — Escola Tech"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

##############################################################################
# CloudFront Distribution
##############################################################################

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Escola Tech — ${var.environment} — NexCloud TCC"
  default_root_object = "index.html"
  price_class         = var.cloudfront_price_class
  aliases             = var.use_custom_domain ? [var.domain_name, "www.${var.domain_name}"] : []
  http_version        = "http2and3"
  wait_for_deployment = false

  ##########################################################################
  # Origin 1: ALB
  #
  # CloudFront -> ALB usa HTTPS.
  # O ALB utiliza certificado wildcard para o dominio configurado.
  # O hostname da origem e um registro Route 53 dedicado (origin.<dominio>)
  # que aponta por alias para o ALB, permitindo validacao TLS correta.
  ##########################################################################

  origin {
    domain_name = var.use_custom_domain ? "${var.origin_subdomain}.${var.domain_name}" : aws_lb.main.dns_name
    origin_id   = "ALB-${local.name_prefix}"

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = var.use_custom_domain ? "https-only" : "http-only"
      origin_ssl_protocols     = ["TLSv1.2"]
      origin_keepalive_timeout = 60
      origin_read_timeout      = 60
    }

    custom_header {
      name  = "X-CF-Origin-Secret"
      value = random_password.cf_origin_secret.result
    }
  }

  ##########################################################################
  # Origin 2: S3 assets estáticos
  ##########################################################################

  origin {
    domain_name              = aws_s3_bucket.assets.bucket_regional_domain_name
    origin_id                = "S3-${local.name_prefix}-assets"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3_assets.id
  }

  ##########################################################################
  # Cache Behavior padrão — ALB (conteúdo dinâmico / HTML)
  ##########################################################################

  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "ALB-${local.name_prefix}"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    cache_policy_id          = aws_cloudfront_cache_policy.no_cache.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.alb_forward.id
  }

  ##########################################################################
  # Cache Behavior — assets estáticos servidos pelo S3
  ##########################################################################

  ordered_cache_behavior {
    path_pattern           = "/static/*"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    target_origin_id       = "S3-${local.name_prefix}-assets"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    cache_policy_id        = aws_cloudfront_cache_policy.static_assets.id
  }

  ##########################################################################
  # SSL — certificado ACM us-east-1
  ##########################################################################

  viewer_certificate {
    cloudfront_default_certificate = !var.use_custom_domain
    acm_certificate_arn             = var.use_custom_domain ? aws_acm_certificate_validation.cloudfront[0].certificate_arn : null
    ssl_support_method              = var.use_custom_domain ? "sni-only" : null
    minimum_protocol_version        = var.use_custom_domain ? "TLSv1.2_2021" : null
  }

  ##########################################################################
  # WAF
  ##########################################################################

  web_acl_id = aws_wafv2_web_acl.main.arn

  ##########################################################################
  # Restrições geográficas — desabilitadas (site global)
  ##########################################################################

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  ##########################################################################
  # Logs de acesso
  ##########################################################################

  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.logs.bucket_domain_name
    prefix          = "cloudfront/"
  }

  tags = {
    Name = "${local.name_prefix}-cloudfront"
  }

  depends_on = [
    aws_wafv2_web_acl.main,
    aws_s3_bucket_acl.logs
  ]
}

##############################################################################
# Cache Policies
##############################################################################

# Sem cache — para conteúdo dinâmico servido pelo ALB
resource "aws_cloudfront_cache_policy" "no_cache" {
  name        = "${local.name_prefix}-no-cache"
  comment     = "Sem cache — conteudo dinamico do ALB"
  default_ttl = 0
  max_ttl     = 0
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "none"
    }
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true
  }
}

# Cache longo — para assets estáticos no S3
resource "aws_cloudfront_cache_policy" "static_assets" {
  name        = "${local.name_prefix}-static-assets"
  comment     = "Cache longo para assets estaticos (CSS, JS, imagens)"
  default_ttl = var.cloudfront_default_ttl # 86400s (24h)
  max_ttl     = var.cloudfront_max_ttl     # 604800s (7d)
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "none"
    }
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true
  }
}

##############################################################################
# Origin Request Policy — ALB
# Encaminha headers necessários para o ALB processar a requisição corretamente
##############################################################################

resource "aws_cloudfront_origin_request_policy" "alb_forward" {
  name    = "${local.name_prefix}-alb-forward"
  comment = "Encaminha headers necessarios para o ALB"

  cookies_config {
    cookie_behavior = "all"
  }

  headers_config {
    header_behavior = "whitelist"
    headers {
      items = [
        "Host",
        "Accept",
        "Accept-Language",
        "User-Agent",
        "X-Forwarded-For"
      ]
    }
  }

  query_strings_config {
    query_string_behavior = "all"
  }
}