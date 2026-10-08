##############################################################################
# variables.tf — NexCloud TCC
# Variáveis do projeto Escola Tech
##############################################################################

# ── Geral ────────────────────────────────────────────────────────────────────

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

variable "use_custom_domain" {
  description = "Usa domínio próprio com ACM/Route 53. false = usa o domínio padrão *.cloudfront.net, sem domínio registrado."
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "Domínio próprio do site. Obrigatório somente quando use_custom_domain = true."
  type        = string
  default     = ""

  validation {
    condition     = !var.use_custom_domain || length(trimspace(var.domain_name)) > 0
    error_message = "domain_name deve ser informado quando use_custom_domain = true."
  }
}

variable "origin_subdomain" {
  description = "Subdomínio usado como hostname da origem HTTPS do CloudFront"
  type        = string
  default     = "origin"
}

variable "alert_email" {
  description = "E-mail para receber alertas do CloudWatch via SNS. Confirme a assinatura após o apply."
  type        = string
  default     = "ops@escolatech.com.br"
}

# ── VPC e Rede ───────────────────────────────────────────────────────────────

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
  description = "Habilita NAT Gateway para subnets privadas. Necessário para que as EC2 acessem a internet (S3, SSM, dnf). Desabilitar apenas em ambientes de teste sem saída de internet."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "true = 1 NAT Gateway (economiza ~$16/mês, mas elimina redundância por AZ). false = 1 NAT por AZ (recomendado para HA)."
  type        = bool
  default     = false
}

# ── EC2 e Auto Scaling ───────────────────────────────────────────────────────

variable "instance_type" {
  description = "Tipo de instância EC2. t3.small usa CPU credits — monitorar surplus credits para evitar custo adicional."
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
  description = "IOPS para volumes gp3 (baseline gratuito: 3000)"
  type        = number
  default     = 3000
}

variable "ebs_throughput" {
  description = "Throughput em MB/s para volumes gp3 (baseline gratuito: 125)"
  type        = number
  default     = 125
}

variable "asg_min_size" {
  description = "Número mínimo de instâncias no ASG. Mínimo 2 para garantir Multi-AZ e alta disponibilidade."
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
  description = "Meta de CPU (%) para a política Target Tracking. O ASG escala para manter a CPU próxima deste valor."
  type        = number
  default     = 70
}

variable "health_check_grace_period" {
  description = "Segundos para aguardar após lançamento antes do health check ELB no ASG"
  type        = number
  default     = 300
}

# ── ALB ──────────────────────────────────────────────────────────────────────

variable "alb_deletion_protection" {
  description = "Protege o ALB contra exclusão acidental. Para laboratório/portfolio, false facilita terraform destroy."
  type        = bool
  default     = false
}

variable "alb_idle_timeout" {
  description = "Timeout de idle do ALB em segundos"
  type        = number
  default     = 60
}

variable "health_check_path" {
  description = "Path do health check do ALB e Target Group. Deve ser servido pela aplicação na EC2."
  type        = string
  default     = "/api/health"
}

variable "health_check_interval" {
  description = "Intervalo em segundos entre health checks"
  type        = number
  default     = 30
}

variable "health_check_healthy_threshold" {
  description = "Checks consecutivos saudáveis para marcar instância como healthy"
  type        = number
  default     = 2
}

variable "health_check_unhealthy_threshold" {
  description = "Checks consecutivos não-saudáveis para marcar instância como unhealthy"
  type        = number
  default     = 3
}

# ── CloudFront ───────────────────────────────────────────────────────────────

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

# ── S3 ───────────────────────────────────────────────────────────────────────

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
  description = "Dias até expirar (deletar) logs"
  type        = number
  default     = 365
}

# ── Monitoramento ────────────────────────────────────────────────────────────

variable "cpu_high_threshold" {
  description = "CPU (%) para alarme de alta utilização — apenas notificação via SNS"
  type        = number
  default     = 70
}

variable "alb_5xx_threshold" {
  description = "Quantidade de erros 5xx por minuto para disparar alarme"
  type        = number
  default     = 10
}

variable "alb_latency_threshold" {
  description = "Latência p95 do ALB em segundos para disparar alarme"
  type        = number
  default     = 2
}

# ── Banco de dados PostgreSQL ────────────────────────────────────────────────

variable "db_name" {
  description = "Nome lógico do banco PostgreSQL"
  type        = string
  default     = "escolatech"
}

variable "db_master_username" {
  description = "Usuário administrativo inicial do RDS. A senha é gerenciada pelo Secrets Manager."
  type        = string
  default     = "app_admin"
}

variable "db_instance_class" {
  description = "Classe da instância RDS PostgreSQL"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "Armazenamento inicial do RDS em GB"
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "Limite de autoscaling de armazenamento do RDS em GB"
  type        = number
  default     = 50
}

variable "db_multi_az" {
  description = "Habilita standby Multi-AZ para alta disponibilidade"
  type        = bool
  default     = true
}

variable "db_backup_retention_period" {
  description = "Retenção de backups automáticos do RDS em dias"
  type        = number
  default     = 7
}

variable "db_deletion_protection" {
  description = "Proteção contra exclusão acidental do RDS"
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "Em TCC, permite terraform destroy sem snapshot final"
  type        = bool
  default     = true
}


variable "db_app_username" {
  description = "Usuário da aplicação PostgreSQL. Autenticação via IAM, sem senha persistente."
  type        = string
  default     = "app_user"
}
