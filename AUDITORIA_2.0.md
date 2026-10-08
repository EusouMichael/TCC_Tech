# Auditoria 2.0 — NexCloud TCC

Data: 2026-10-08

## Resultado

O projeto foi revisado e atualizado para uma arquitetura aplicável na AWS, incluindo persistência de dados e uma API de cadastro.

### Principais correções aplicadas

- RDS PostgreSQL privado em subnets privadas.
- RDS Multi-AZ para alta disponibilidade.
- RDS criptografado e com backup automático de 7 dias.
- Secrets Manager gerenciado pelo próprio RDS para a credencial master.
- IAM Database Authentication para o usuário da aplicação.
- Security Group do RDS permitindo TCP/5432 somente do Security Group das EC2.
- API Node.js/Express + PostgreSQL.
- Endpoint `POST /api/enrollments` para cadastro.
- Endpoint `GET /api/health` para validar a camada de dados.
- Formulário do site integrado à API.
- TLS validado entre API e RDS com CA oficial do Amazon RDS.
- Logs da API enviados ao CloudWatch.
- Alarmes CloudWatch adicionais para CPU e armazenamento do RDS.
- CI alterado para somente leitura: `terraform fmt -check` + `terraform validate`.
- Removido commit/push automático do GitHub Actions.
- Exemplo de `terraform.tfvars` atualizado.
- Documentação e matriz de requisitos atualizadas.
- Estimativa de custos atualizada para incluir RDS.

## Arquitetura final

```
Internet
   |
Route 53
   |
CloudFront
   |
WAF
   |
ALB
   |
ASG
   |
EC2 privadas
   |--- Nginx
   |--- Node.js API
   |
   +---- RDS PostgreSQL Multi-AZ
             |
       Secrets Manager
       IAM DB Authentication

EC2 --> S3
EC2 --> CloudWatch
EC2 --> SSM
```

## Segurança

A aplicação não usa a senha master como credencial normal de acesso ao banco. A senha master é gerenciada pelo RDS/Secrets Manager e usada somente no bootstrap para preparar o usuário da aplicação. As conexões normais da API utilizam IAM Database Authentication.

O banco não possui acesso público e aceita conexões somente das EC2.

## Checklist antes do apply

- [ ] Conta AWS correta
- [ ] IAM administrativo configurado
- [ ] MFA habilitado
- [ ] Billing/alertas conferidos
- [ ] AWS CLI autenticado
- [ ] Terraform instalado
- [ ] Domínio e DNS planejados
- [ ] `terraform.tfvars` criado localmente
- [ ] `terraform.tfvars` não versionado
- [ ] `terraform init`
- [ ] `terraform fmt -check -recursive`
- [ ] `terraform validate`
- [ ] `terraform plan`
- [ ] Revisar custos
- [ ] Executar `terraform apply`
- [ ] Confirmar SNS
- [ ] Confirmar ACM
- [ ] Confirmar CloudFront
- [ ] Confirmar 2 EC2 healthy
- [ ] Confirmar RDS available
- [ ] Confirmar `/api/health`
- [ ] Executar cadastro de teste
- [ ] Confirmar registro no PostgreSQL
- [ ] Confirmar CloudWatch Dashboard
- [ ] Confirmar logs da API
- [ ] Guardar evidências para a apresentação

## Limitações conscientes

O ambiente continua sendo um TCC e não um ambiente de produção empresarial completo. O estado Terraform permanece local para simplificar o laboratório. O RDS usa Multi-AZ, mas a arquitetura não implementa RDS Proxy, rotação de credenciais do usuário da aplicação nem pipeline de deploy automático para produção.

Esses itens podem ser evolução posterior; não são necessários para demonstrar os requisitos atuais.

## Status

**Código atualizado:** sim  
**Banco de dados:** implementado  
**API:** implementada  
**Formulário:** integrado  
**IaC:** atualizado  
**CI:** endurecido  
**Documentação:** atualizada  
**Pronto para iniciar o deploy AWS:** sim, após executar localmente `terraform init/validate/plan` e revisar o plano antes do `apply`.
