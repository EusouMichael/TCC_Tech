##############################################################################
# monitoring.tf — NexCloud TCC
# CloudWatch Alarms, Dashboard, SNS, AWS Backup (EBS)
# Requisitos: R09 (Monitoramento), R08 (Backup EBS)
##############################################################################

##############################################################################
# SNS — Tópico de alertas
#
# Após o terraform apply, confirme a assinatura no e-mail recebido.
# Sem confirmação, os alertas não chegam.
##############################################################################

resource "aws_sns_topic" "alerts" {
  name         = "${local.name_prefix}-alertas"
  display_name = "NexCloud Alertas — Escola Tech"

  tags = {
    Name = "${local.name_prefix}-sns-alertas"
  }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

##############################################################################
# CloudWatch Alarms — EC2 / ASG
##############################################################################

# CPU alta — alarme informativo via SNS.
# O scaling é gerenciado pela política Target Tracking (ec2.tf),
# NÃO por este alarme. Alarm_actions não inclui a scaling policy.
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${local.name_prefix}-cpu-high"
  alarm_description   = "CPU media das EC2 acima de ${var.cpu_high_threshold}% por 2 minutos"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = var.cpu_high_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.main.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "${local.name_prefix}-alarm-cpu-high"
  }
}

# Status check EC2 — detecta falha de instância
resource "aws_cloudwatch_metric_alarm" "ec2_status_check" {
  alarm_name          = "${local.name_prefix}-ec2-status-check"
  alarm_description   = "Status check de instancia EC2 no ASG falhou"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.main.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "${local.name_prefix}-alarm-ec2-status"
  }
}

##############################################################################
# CloudWatch Alarms — ALB
##############################################################################

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${local.name_prefix}-alb-5xx"
  alarm_description   = "ALB: mais de ${var.alb_5xx_threshold} erros 5xx em 1 minuto"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = var.alb_5xx_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "${local.name_prefix}-alarm-alb-5xx"
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_latency" {
  alarm_name          = "${local.name_prefix}-alb-latency"
  alarm_description   = "ALB: latencia p95 acima de ${var.alb_latency_threshold}s por 2 minutos"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  extended_statistic  = "p95"
  threshold           = var.alb_latency_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "${local.name_prefix}-alarm-alb-latency"
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  alarm_name          = "${local.name_prefix}-alb-unhealthy-hosts"
  alarm_description   = "ALB: existem instancias unhealthy no Target Group"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.main.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "${local.name_prefix}-alarm-unhealthy-hosts"
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_no_healthy_hosts" {
  alarm_name          = "${local.name_prefix}-alb-no-healthy-hosts"
  alarm_description   = "CRITICO: nenhuma instancia saudavel no Target Group"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Minimum"
  threshold           = 0
  treat_missing_data  = "breaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.main.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "${local.name_prefix}-alarm-no-healthy-hosts"
  }
}

##############################################################################
# CloudWatch Log Groups
##############################################################################

resource "aws_cloudwatch_log_group" "nginx_access" {
  name              = "/aws/ec2/${local.name_prefix}/nginx-access"
  retention_in_days = 30
  tags              = { Name = "${local.name_prefix}-nginx-access" }
}

resource "aws_cloudwatch_log_group" "nginx_error" {
  name              = "/aws/ec2/${local.name_prefix}/nginx-error"
  retention_in_days = 30
  tags              = { Name = "${local.name_prefix}-nginx-error" }
}

resource "aws_cloudwatch_log_group" "bootstrap" {
  name              = "/aws/ec2/${local.name_prefix}/bootstrap"
  retention_in_days = 14
  tags              = { Name = "${local.name_prefix}-bootstrap" }
}

##############################################################################
# CloudWatch Dashboard
# Reflete os recursos reais definidos neste projeto.
# Números no dashboard (ex: min=2) batem com variables.tf.
##############################################################################

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.name_prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "## 🎓 Escola Tech — NexCloud TCC | Região: ${var.aws_region} | ASG: min=2 desired=2 max=4"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "CPU — Auto Scaling Group"
          region = var.aws_region
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName",
              aws_autoscaling_group.main.name,
            { stat = "Average", label = "CPU Média" }],
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName",
              aws_autoscaling_group.main.name,
            { stat = "Maximum", label = "CPU Máxima" }]
          ]
          yAxis = { left = { min = 0, max = 100 } }
          annotations = {
            horizontal = [
              { label = "Target Tracking (70%)", value = 70, color = "#FF9800" }
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "ALB — Requisições (Sum/min)"
          region = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "RequestCount",
              "LoadBalancer", aws_lb.main.arn_suffix,
            { stat = "Sum", period = 60 }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "ALB — Latência (p50 / p95 / p99)"
          region = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime",
            "LoadBalancer", aws_lb.main.arn_suffix, { stat = "p50", label = "p50" }],
            ["AWS/ApplicationELB", "TargetResponseTime",
            "LoadBalancer", aws_lb.main.arn_suffix, { stat = "p95", label = "p95" }],
            ["AWS/ApplicationELB", "TargetResponseTime",
            "LoadBalancer", aws_lb.main.arn_suffix, { stat = "p99", label = "p99" }]
          ]
          yAxis = { left = { min = 0, max = 10 } }
          annotations = {
            horizontal = [{ label = "Limite alarme (${var.alb_latency_threshold}s)", value = var.alb_latency_threshold }]
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 8
        height = 6
        properties = {
          title  = "ALB — Códigos HTTP"
          region = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_2XX_Count",
            "LoadBalancer", aws_lb.main.arn_suffix, { stat = "Sum", label = "2xx" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count",
            "LoadBalancer", aws_lb.main.arn_suffix, { stat = "Sum", label = "4xx" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count",
            "LoadBalancer", aws_lb.main.arn_suffix, { stat = "Sum", label = "5xx" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 7
        width  = 8
        height = 6
        properties = {
          title  = "ASG — Instâncias em Serviço"
          region = var.aws_region
          metrics = [
            ["AWS/AutoScaling", "GroupInServiceInstances",
              "AutoScalingGroupName", aws_autoscaling_group.main.name,
            { stat = "Average", label = "InService" }]
          ]
          yAxis = { left = { min = 0, max = 6 } }
          annotations = {
            horizontal = [
              { label = "Máximo (4)", value = 4 },
              { label = "Mínimo (2)", value = 2 }
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 7
        width  = 8
        height = 6
        properties = {
          title  = "Target Group — Hosts Saudáveis"
          region = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount",
              "LoadBalancer", aws_lb.main.arn_suffix,
              "TargetGroup", aws_lb_target_group.main.arn_suffix,
            { stat = "Minimum", label = "Healthy" }],
            ["AWS/ApplicationELB", "UnHealthyHostCount",
              "LoadBalancer", aws_lb.main.arn_suffix,
              "TargetGroup", aws_lb_target_group.main.arn_suffix,
            { stat = "Maximum", label = "Unhealthy" }]
          ]
        }
      }
    ]
  })
}

##############################################################################
# AWS Backup — EBS Snapshots diários
# Requisito R08: backup automatizado com retenção de 7 dias.
# Seleciona volumes EBS com tag ManagedBy=Terraform.
##############################################################################

resource "aws_backup_vault" "main" {
  name = "${local.name_prefix}-backup-vault"

  tags = {
    Name = "${local.name_prefix}-backup-vault"
  }
}

resource "aws_iam_role" "backup" {
  name = "${local.name_prefix}-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
    }]
  })

  tags = {
    Name = "${local.name_prefix}-backup-role"
  }
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_backup_plan" "ebs_daily" {
  name = "${local.name_prefix}-ebs-daily"

  rule {
    rule_name         = "daily-7-days"
    target_vault_name = aws_backup_vault.main.name
    # 02:00 BRT = 05:00 UTC
    schedule = "cron(0 5 * * ? *)"

    lifecycle {
      delete_after = 7
    }
  }

  tags = {
    Name = "${local.name_prefix}-backup-plan"
  }
}

# Seleciona volumes EBS tagueados com ManagedBy=Terraform
resource "aws_backup_selection" "ebs" {
  name         = "${local.name_prefix}-ebs-selection"
  plan_id      = aws_backup_plan.ebs_daily.id
  iam_role_arn = aws_iam_role.backup.arn

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "ManagedBy"
    value = "Terraform"
  }
}