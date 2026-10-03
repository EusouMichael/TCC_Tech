##############################################################################
# variables.tf — NexCloud TCC
# Variáveis do projeto Escola Tech
##############################################################################

variable "aws_region" {
  description = "Região AWS onde os recursos serão provisionados"
  type        = string
  default     = "sa-east-1"
}

variable "project_name" {
  description = "Nome do projeto — usado como prefixo em todos os recursos"
  type        = string
  default     = "escolatech"
}

variable "environment" {
  description = "Ambiente de deployment"
  type        = string
  default     = "tcc"
  validation {
    condition     = contains(["tcc", "production", "staging", "dev"], var.environment)
    error_message = "O ambiente deve ser: tcc, production, staging ou dev."
  }
}

variable "domain_name" {
  description = "Domínio principal do site. Deve estar registrado e com DNS delegado ao Route 53. Sem domínio real, use o CloudFront domain diretamente."
  type        = string
  default     = "escolatech.com.br"
}

variable "alert_email" {
  description = "E-mail para receber alertas do CloudWatch via SNS. Confirme a assinatura após o apply."
  type        = string
  default     = "ops@escolatech.com.br"
}

variable "vpc_cidr" {
  description = "CIDR block da VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Zonas de disponibilidade (mínimo 2 para Multi-AZ)"
  type        = list(string)
  default     = ["sa-east-1a", "sa-east-1b"]
  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "Informe pelo menos 2 AZs para arquitetura Multi-AZ."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDRs das subnets públicas — ALB e NAT Gateway"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas — instâncias EC2"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "enable_nat_gateway" {
  description = "Habilita NAT Gateway para subnets privadas. Necessário para que as EC2 acessem a internet (S3, SSM, dnf)."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "true = 1 NAT Gateway; false = 1 NAT por AZ."
  type        = bool
  default     = false
}

variable "instance_type" {
  description = "Tipo de instância EC2. t3.small usa CPU credits."
  type        = string
  default     = "t3.small"
}

variable "ebs_volume_size" {
  description = "Tamanho do volume EBS root em GB"
  type        = number
  default     = 20
}

variable "ebs_volume_type" {
  description = "Tipo do volume EBS"
  type        = string
  default     = "gp3"
}

variable "ebs_iops" {
  description = "IOPS para volumes gp3"
  type        = number
  default     = 3000
}

variable "ebs_throughput" {
  description = "Throughput em MB/s para volumes gp3"
  type        = number
  default     = 125
}

variable "asg_min_size" {
  description = "Número mínimo de instâncias no ASG. Mínimo 2 para Multi-AZ."
  type        = number
  default     = 2
  validation {
    condition     = var.asg_min_size >= 2
    error_message = "asg_min_size deve ser >= 2 para manter Multi-AZ."
  }
}

variable "asg_desired_capacity" {
  description = "Capacidade desejada de instâncias no ASG"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Número máximo de instâncias no ASG"
  type        = number
  default     = 4
}

variable "asg_cpu_target" {
  description = "Meta de CPU (%) para Target Tracking"
  type        = number
  default     = 70
}

variable "health_check_grace_period" {
  description = "Segundos para aguardar após lançamento antes do health check ELB"
  type        = number
  default     = 300
}

variable "alb_idle_timeout" {
  description = "Timeout de idle do ALB em segundos"
  type        = number
  default     = 60
}

variable "health_check_path" {
  description = "Path do health check do ALB e Target Group"
  type        = string
  default     = "/health"
}

variable "health_check_interval" {
  description = "Intervalo em segundos entre health checks"
  type        = number
  default     = 30
}

variable "health_check_healthy_threshold" {
  description = "Checks consecutivos saudáveis"
  type        = number
  default     = 2
}

variable "health_check_unhealthy_threshold" {
  description = "Checks consecutivos não-saudáveis"
  type        = number
  default     = 3
}

variable "cloudfront_price_class" {
  description = "Classe de preço do CloudFront"
  type        = string
  default     = "PriceClass_All"
  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.cloudfront_price_class)
    error_message = "Valores válidos: PriceClass_100, PriceClass_200, PriceClass_All."
  }
}

variable "cloudfront_default_ttl" {
  description = "TTL padrão de cache para assets estáticos (segundos)"
  type        = number
  default     = 86400
}

variable "cloudfront_max_ttl" {
  description = "TTL máximo de cache para assets estáticos (segundos)"
  type        = number
  default     = 604800
}

variable "s3_logs_transition_days" {
  description = "Dias até mover logs do S3 Standard para S3-IA"
  type        = number
  default     = 30
}

variable "s3_logs_glacier_days" {
  description = "Dias até mover logs do S3-IA para Glacier"
  type        = number
  default     = 90
}

variable "s3_logs_expiration_days" {
  description = "Dias até expirar logs"
  type        = number
  default     = 365
}

variable "cpu_high_threshold" {
  description = "CPU (%) para alarme de alta utilização"
  type        = number
  default     = 70
}

variable "alb_5xx_threshold" {
  description = "Quantidade de erros 5xx por minuto"
  type        = number
  default     = 10
}

variable "alb_latency_threshold" {
  description = "Latência p95 do ALB em segundos"
  type        = number
  default     = 2
}
