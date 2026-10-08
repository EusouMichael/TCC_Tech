##############################################################################
# database.tf — NexCloud TCC
# Amazon RDS PostgreSQL — cadastro de alunos/clientes
#
# Banco privado em subnets privadas, Multi-AZ, criptografado e com senha
# gerenciada pelo AWS Secrets Manager.
##############################################################################

resource "aws_db_subnet_group" "postgres" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name    = "${local.name_prefix}-db-subnet-group"
    Purpose = "RDS PostgreSQL privado"
  }
}

resource "aws_db_instance" "postgres" {
  identifier = "${local.name_prefix}-postgres"

  engine         = "postgres"
  instance_class = var.db_instance_class
  db_name        = var.db_name
  username       = var.db_master_username

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  manage_master_user_password = true

  multi_az               = var.db_multi_az
  publicly_accessible    = false
  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  backup_retention_period = var.db_backup_retention_period
  backup_window           = "05:00-05:30"
  maintenance_window      = "sun:06:00-sun:06:30"
  copy_tags_to_snapshot   = true

  deletion_protection = var.db_deletion_protection
  skip_final_snapshot = var.db_skip_final_snapshot

  auto_minor_version_upgrade = true
  apply_immediately          = false
  ca_cert_identifier         = "rds-ca-rsa2048-g1"

  performance_insights_enabled = false

  tags = {
    Name    = "${local.name_prefix}-postgres"
    Purpose = "Cadastro Escola Tech"
  }

  depends_on = [aws_security_group.rds]
}

output "rds_endpoint" {
  description = "Endpoint privado do PostgreSQL"
  value       = aws_db_instance.postgres.address
}

output "rds_port" {
  description = "Porta do PostgreSQL"
  value       = aws_db_instance.postgres.port
}

output "rds_database_name" {
  description = "Nome do banco"
  value       = aws_db_instance.postgres.db_name
}

output "rds_secret_arn" {
  description = "ARN do segredo gerenciado pelo RDS/Secrets Manager"
  value       = aws_db_instance.postgres.master_user_secret[0].secret_arn
  sensitive   = true
}
