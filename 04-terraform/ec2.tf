##############################################################################
# ec2.tf — NexCloud TCC
# Launch Template + Auto Scaling Group + Scaling Policy
# SO: Amazon Linux 2023 (AL2023)
# Requisitos: R01 (Alta disponibilidade), R02 (Escalabilidade), R07 (Armazenamento)
##############################################################################

##############################################################################
# User Data — Bootstrap AL2023
# Executado no primeiro boot de cada instância criada pelo ASG.
# O script busca o index.html do S3 para garantir que toda nova instância
# criada automaticamente pelo ASG tenha o site atualizado.
##############################################################################

locals {
  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    aws_region    = var.aws_region
    assets_bucket = "${local.name_prefix}-assets-${local.account_id}"
    project_name  = var.project_name
    environment   = var.environment
  }))
}

##############################################################################
# Launch Template
##############################################################################

resource "aws_launch_template" "main" {
  name_prefix   = "${local.name_prefix}-lt-"
  description   = "Launch Template Escola Tech — Amazon Linux 2023, Nginx"
  image_id      = local.ami_id # AL2023 via SSM parameter em main.tf
  instance_type = var.instance_type

  user_data = local.user_data

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2.arn
  }

  # Security groups definidos aqui; NÃO usar vpc_security_group_ids
  # junto com network_interfaces (conflito no provider AWS)
  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.ec2.id]
    delete_on_termination       = true
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.ebs_volume_size
      volume_type           = var.ebs_volume_type
      iops                  = var.ebs_iops
      throughput            = var.ebs_throughput
      encrypted             = true
      delete_on_termination = true
    }
  }

  # Monitoramento detalhado: métricas a cada 1 minuto (custo adicional mínimo)
  monitoring {
    enabled = true
  }

  # IMDSv2 obrigatório — protege contra SSRF que tenta acessar metadados
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${local.name_prefix}-ec2"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "${local.name_prefix}-ebs"
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.name_prefix}-launch-template"
  }
}

##############################################################################
# Auto Scaling Group
##############################################################################

resource "aws_autoscaling_group" "main" {
  name             = "${local.name_prefix}-asg"
  min_size         = var.asg_min_size         # >= 2 — garante Multi-AZ
  max_size         = var.asg_max_size         # 4
  desired_capacity = var.asg_desired_capacity # 2

  # Subnets privadas nas duas AZs — instâncias nunca ficam em subnet pública
  vpc_zone_identifier = aws_subnet.private[*].id

  target_group_arns = [aws_lb_target_group.main.arn]

  # ELB health check: instância é removida do tráfego se o ALB marcar como unhealthy
  health_check_type         = "ELB"
  health_check_grace_period = var.health_check_grace_period

  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }

  # Balanceia instâncias entre AZs automaticamente
  capacity_rebalance = true

  # Cooldown padrão entre ações de scaling
  default_cooldown = 300

  termination_policies = ["OldestLaunchTemplate", "OldestInstance"]

  # Ignorar mudanças de desired_capacity feitas pelas políticas de scaling
  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }

  dynamic "tag" {
    for_each = {
      Name        = "${local.name_prefix}-ec2"
      Project     = "EscolaTech"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  depends_on = [
    aws_lb_target_group.main,
    aws_nat_gateway.main,
    aws_s3_object.index_html
  ]
}

##############################################################################
# Scaling Policy — Target Tracking (CPU)
#
# Uma única política Target Tracking é suficiente e clara para o TCC.
# O ASG adiciona/remove instâncias automaticamente para manter a CPU média
# próxima de var.asg_cpu_target (padrão: 70%).
# NÃO adicionar esta policy como alarm_action — ela é gerenciada internamente.
##############################################################################

resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                      = "${local.name_prefix}-cpu-target-tracking"
  autoscaling_group_name    = aws_autoscaling_group.main.name
  policy_type               = "TargetTrackingScaling"
  estimated_instance_warmup = 300

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.asg_cpu_target # 70%

    # Não escalar para menos que min_size (2) — mantém Multi-AZ
    disable_scale_in = false
  }
}

##############################################################################
# Scheduled Scaling — horários de pico
#
# Garante capacidade mínima de 2 em horário comercial e mantém 2 durante
# a noite também, pois min=2 é requisito da arquitetura Multi-AZ.
##############################################################################

resource "aws_autoscaling_schedule" "business_hours" {
  scheduled_action_name  = "${local.name_prefix}-business-hours"
  autoscaling_group_name = aws_autoscaling_group.main.name
  min_size               = 2
  max_size               = 4
  desired_capacity       = 2
  # 08:00 BRT = 11:00 UTC, dias úteis
  recurrence = "0 11 * * 1-5"
  time_zone  = "America/Sao_Paulo"
}