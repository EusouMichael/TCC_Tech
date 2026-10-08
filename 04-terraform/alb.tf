##############################################################################
# alb.tf — NexCloud TCC
# Application Load Balancer, Target Group, Listeners
# Requisitos: R01 (Alta disponibilidade), R04 (HTTPS)
##############################################################################

##############################################################################
# Application Load Balancer
##############################################################################

resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = var.alb_deletion_protection
  enable_http2               = true
  idle_timeout               = var.alb_idle_timeout

  access_logs {
    bucket  = aws_s3_bucket.logs.bucket
    prefix  = "alb"
    enabled = true
  }

  tags = {
    Name = "${local.name_prefix}-alb"
  }

  depends_on = [aws_s3_bucket_policy.logs]
}

##############################################################################
# Target Group
#
# O health check aponta para /health, que é servido REALMENTE pelo Nginx
# na EC2. Isso garante que o ALB detecte instâncias com Nginx parado
# e as remova do tráfego, permitindo que o ASG as substitua.
##############################################################################

resource "aws_lb_target_group" "main" {
  name                 = "${local.name_prefix}-tg"
  port                 = 80
  protocol             = "HTTP"
  vpc_id               = aws_vpc.main.id
  deregistration_delay = 30

  stickiness {
    type    = "lb_cookie"
    enabled = false
  }

  health_check {
    enabled             = true
    path                = var.health_check_path # /health — servido pelo Nginx
    protocol            = "HTTP"
    port                = "traffic-port"
    interval            = var.health_check_interval
    timeout             = 10
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    matcher             = "200"
  }

  tags = {
    Name = "${local.name_prefix}-tg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

##############################################################################
# Listener HTTP:80 — redireciona para HTTPS
##############################################################################

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = var.use_custom_domain ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = var.use_custom_domain ? [] : [1]
    content {
      type = "fixed-response"
      fixed_response {
        content_type = "text/plain"
        message_body = "Forbidden"
        status_code  = "403"
      }
    }
  }

  tags = {
    Name = "${local.name_prefix}-listener-http"
  }
}

##############################################################################
# Listener HTTPS:443
#
# Valida o custom header secreto injetado pelo CloudFront.
# Requisições sem o header correto recebem 403.
# Isso impede acesso direto ao ALB bypassando CloudFront e WAF.
##############################################################################

resource "aws_lb_listener" "https" {
  count = var.use_custom_domain ? 1 : 0
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.alb.certificate_arn

  # Ação padrão: bloquear requisições que NÃO passem pela regra do header
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }

  tags = {
    Name = "${local.name_prefix}-listener-https"
  }
}

##############################################################################
# Listener Rule — aceitar apenas requisições com o header secreto do CloudFront
##############################################################################

resource "aws_lb_listener_rule" "cloudfront_only" {
  listener_arn = var.use_custom_domain ? aws_lb_listener.https[0].arn : aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  condition {
    http_header {
      http_header_name = "X-CF-Origin-Secret"
      values           = [random_password.cf_origin_secret.result]
    }
  }

  tags = {
    Name = "${local.name_prefix}-rule-cf-only"
  }
}