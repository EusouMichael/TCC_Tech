##############################################################################
# ec2.tf — NexCloud TCC
# Launch Template + Auto Scaling Group + Scaling Policy
# SO: Amazon Linux 2023 (AL2023)
##############################################################################

locals {
  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    aws_region    = var.aws_region
    assets_bucket = "${local.name_prefix}-assets-${local.account_id}"
    project_name  = var.project_name
    environment   = var.environment
  }))
}

resource "aws_launch_template" "main" {
  name_prefix   = "${local.name_prefix}-lt-"
  description   = "Launch Template Escola Tech — Amazon Linux 2023, Nginx"
  image_id      = local.ami_id
  instance_type = var.instance_type
  user_data     = local.user_data

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2.arn
  }

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

  monitoring { enabled = true }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags = { Name = "${local.name_prefix}-ec2" }
  }

  tag_specifications {
    resource_type = "volume"
    tags = { Name = "${local.name_prefix}-ebs" }
  }

  lifecycle { create_before_destroy = true }
  tags = { Name = "${local.name_prefix}-launch-template" }
}

resource "aws_autoscaling_group" "main" {
  name             = "${local.name_prefix}-asg"
  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired_capacity
  vpc_zone_identifier = aws_subnet.private[*].id
  target_group_arns    = [aws_lb_target_group.main.arn]

  health_check_type         = "ELB"
  health_check_grace_period = var.health_check_grace_period
  capacity_rebalance        = true
  default_cooldown          = 300
  termination_policies      = ["OldestLaunchTemplate", "OldestInstance"]

  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }

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

resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                      = "${local.name_prefix}-cpu-target-tracking"
  autoscaling_group_name    = aws_autoscaling_group.main.name
  policy_type               = "TargetTrackingScaling"
  estimated_instance_warmup = 300

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value    = var.asg_cpu_target
    disable_scale_in = false
  }
}

resource "aws_autoscaling_schedule" "business_hours" {
  scheduled_action_name  = "${local.name_prefix}-business-hours"
  autoscaling_group_name = aws_autoscaling_group.main.name
  min_size               = 2
  max_size               = 4
  desired_capacity       = 2
  recurrence             = "0 11 * * 1-5"
  time_zone              = "America/Sao_Paulo"
}
