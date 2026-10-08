# AWS Go-Live Checklist — NexCloud

## Antes do primeiro apply

- [ ] Conta AWS correta
- [ ] Identidade administrativa configurada
- [ ] MFA habilitado
- [ ] Billing/alertas conferidos
- [ ] Região: sa-east-1
- [ ] AWS CLI funcionando
- [ ] Terraform funcionando
- [ ] Domínio real disponível
- [ ] Name Servers do Route 53 serão configurados no registrador
- [ ] terraform.tfvars criado localmente
- [ ] terraform.tfvars fora do Git
- [ ] terraform init concluído
- [ ] terraform fmt concluído
- [ ] terraform validate concluído
- [ ] terraform plan revisado

## Depois do apply

- [ ] ACM CloudFront validado
- [ ] ACM ALB validado
- [ ] Route 53 resolvendo
- [ ] CloudFront distribuindo
- [ ] WAF associado
- [ ] ALB healthy
- [ ] 2 EC2 healthy
- [ ] RDS PostgreSQL available
- [ ] RDS Multi-AZ ativo
- [ ] RDS sem acesso público
- [ ] Secrets Manager com credencial master gerenciada pelo RDS
- [ ] IAM DB Authentication funcionando
- [ ] ASG min/desired/max correto
- [ ] SSM funcionando
- [ ] SNS confirmado
- [ ] CloudWatch dashboard funcionando
- [ ] Logs Nginx, bootstrap e API chegando no CloudWatch
- [ ] Alarmes RDS ativos
- [ ] /health = 200
- [ ] /api/health = 200 com database=ok
- [ ] POST /api/enrollments = 201
- [ ] Registro persistido no PostgreSQL
- [ ] ALB direto = 403
- [ ] site público funcionando

## Evidências para portfolio

- [ ] Diagrama
- [ ] VPC
- [ ] ALB
- [ ] ASG
- [ ] EC2
- [ ] CloudFront
- [ ] WAF
- [ ] CloudWatch
- [ ] SSM
- [ ] GitHub Actions
- [ ] URL pública
