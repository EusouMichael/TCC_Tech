# AWS Deployment Runbook — NexCloud TCC

Este documento é o roteiro operacional para colocar o projeto no ar na AWS com o mínimo de risco e com possibilidade de desmontar o ambiente depois da demonstração.

> **Regra:** não execute `terraform apply` antes de concluir as etapas 1–5 e revisar o `terraform plan`.

## 0. Arquitetura que será criada

```
Internet
  |
  v
Route 53
  |
  v
CloudFront + WAF
  |
  | HTTPS
  v
origin.<dominio> -> ALB :443
  |
  | HTTP
  v
Target Group
  |
  +--> EC2 AZ-A (private)
  |
  +--> EC2 AZ-B (private)

EC2 -> NAT Gateway -> Internet
EC2 -> S3 / CloudWatch / SSM
CloudWatch -> SNS
AWS Backup -> EBS snapshots
```

## 1. Preparar a conta AWS

### 1.1 Conta e acesso administrativo

- Não usar o usuário root para o trabalho diário.
- Usar uma identidade administrativa apropriada para o laboratório.
- Habilitar MFA na identidade administrativa.
- Confirmar que a região principal será **sa-east-1 (São Paulo)**.

### 1.2 Billing

Antes do primeiro `apply`:

- configurar alertas de faturamento;
- confirmar o método de pagamento;
- conferir se existe Free Tier aplicável;
- lembrar que NAT Gateway, ALB, WAF, CloudFront e CloudWatch podem gerar cobrança.

## 2. Pré-requisitos locais

Instalar:

- AWS CLI
- Terraform >= 1.5
- Git
- opcional: VS Code

Validar:

```bash
aws --version
terraform version
git --version
```

## 3. Configurar credenciais AWS

Para o primeiro laboratório, configurar a AWS CLI com a identidade administrativa destinada ao projeto:

```bash
aws configure
```

Testar:

```bash
aws sts get-caller-identity
aws configure get region
```

O comando `sts get-caller-identity` deve retornar a conta e a identidade utilizadas.

> **Nunca** colocar Access Key, Secret Key ou `terraform.tfvars` real no GitHub.

## 4. Domínio

A configuração atual utiliza:

- `var.domain_name` para o domínio público;
- ACM em **us-east-1** para CloudFront;
- ACM em **sa-east-1** para o ALB;
- `origin.<dominio>` como hostname HTTPS da origem;
- Route 53 para os registros.

Portanto, antes do `apply`, precisamos ter um domínio real e controlável.

Exemplo:

```
escolatech.com.br
www.escolatech.com.br
origin.escolatech.com.br
```

O Terraform cria a Hosted Zone, mas o registrador precisa receber os Name Servers retornados pelo output `route53_name_servers`.

## 5. Configurar Terraform

```bash
cd 04-terraform
cp terraform.tfvars.example terraform.tfvars
```

Edite:

```hcl
domain_name = "SEU-DOMINIO.COM.BR"
alert_email = "SEU-EMAIL"
```

Para o primeiro laboratório:

```hcl
alb_deletion_protection = false
```

Não versionar `terraform.tfvars`.

## 6. Inicialização

```bash
terraform init
```

Depois:

```bash
terraform fmt -check -recursive
terraform validate
```

Se houver erro, **parar aqui**. Não executar `apply`.

## 7. Revisar o plano

```bash
terraform plan -var-file=terraform.tfvars
```

Conferir principalmente:

- VPC;
- 2 subnets públicas;
- 2 subnets privadas;
- 2 NAT Gateways;
- ALB;
- Target Group;
- ASG 2/2/4;
- EC2;
- S3;
- CloudFront;
- WAF;
- ACM;
- Route 53;
- CloudWatch;
- SNS;
- AWS Backup.

Se aparecer qualquer recurso inesperado, parar e revisar.

## 8. Primeiro apply

Somente após revisar o plano:

```bash
terraform apply -var-file=terraform.tfvars
```

Durante o apply, pode haver espera para:

- ACM DNS validation;
- CloudFront distribution;
- WAF;
- ALB;
- ASG;
- EC2 health checks.

## 9. Confirmar SNS

Verificar o e-mail informado em `alert_email`.

Confirmar a assinatura do SNS.

Sem essa confirmação, os alarmes não enviarão e-mails.

## 10. Obter os outputs

```bash
terraform output
```

Guardar:

- `website_url_cloudfront`
- `website_url`
- `cloudfront_domain_name`
- `alb_dns_name`
- `asg_name`
- `s3_assets_bucket`
- `cloudwatch_dashboard_name`
- `route53_name_servers`

Não publicar secrets ou o state Terraform.

## 11. Testes funcionais

### Site

Abrir:

```
https://SEU-DOMINIO.COM.BR
```

### Health

```
curl -I https://SEU-DOMINIO.COM.BR/health
```

Esperado:

```
HTTP 200
```

### ALB direto

O acesso direto ao ALB em HTTPS deve receber:

```
HTTP 403
```

porque o header `X-CF-Origin-Secret` não estará presente.

### Target Group

```bash
aws elbv2 describe-target-health \
  --target-group-arn "$(terraform output -raw target_group_arn)" \
  --region sa-east-1
```

Esperado: pelo menos duas instâncias `healthy`.

## 12. SSM

Não abrir SSH na Internet.

Usar:

**AWS Console → Systems Manager → Session Manager**

A EC2 deve aparecer como managed instance.

## 13. CloudWatch

Abrir o dashboard:

```
terraform output -raw cloudwatch_dashboard_name
```

Validar:

- CPU;
- RequestCount;
- latência;
- HTTP 2xx/4xx/5xx;
- instâncias InService;
- hosts saudáveis.

## 14. Teste de Auto Scaling

Não gerar carga agressiva.

O objetivo é demonstrar o conceito:

```
CPU aumenta
   ↓
Target Tracking
   ↓
ASG aumenta capacidade
   ↓
ALB registra nova instância
```

## 15. Teste de recuperação

Para demonstração controlada:

1. identificar uma instância;
2. interromper a instância pela Console;
3. observar Target Group;
4. observar ASG;
5. verificar substituição automática.

Não encerrar múltiplas instâncias ao mesmo tempo.

## 16. Teste de segurança

### Sem header

Acessar diretamente o ALB:

```
https://ALB-DNS-NAME
```

Esperado:

```
403 Forbidden
```

### EC2

Confirmar:

- sem IP público;
- sem porta 22 aberta;
- porta 80 apenas pelo Security Group do ALB.

## 17. Portfolio

Depois dos testes:

- colocar a URL pública no README;
- adicionar screenshots do CloudWatch;
- adicionar screenshot da arquitetura;
- registrar outputs não sensíveis;
- documentar o fluxo de deploy;
- adicionar o projeto ao currículo/LinkedIn.

## 18. Encerrar o ambiente quando não estiver usando

O projeto foi preparado para laboratório/portfolio, mas vários serviços são cobrados por uso.

Antes de destruir, guardar evidências:

- arquitetura;
- CloudWatch;
- EC2;
- ALB;
- CloudFront;
- WAF;
- Route 53;
- Terraform plan/apply.

Depois:

```bash
terraform destroy -var-file=terraform.tfvars
```

Buckets de assets/backups possuem proteção contra exclusão automática enquanto contiverem objetos. Se o destroy falhar por causa de buckets não vazios, esvaziá-los conscientemente antes de repetir.

## Ordem oficial do nosso laboratório

```
01. Conta AWS / identidade administrativa
02. Billing / alertas
03. AWS CLI
04. Domínio / DNS
05. terraform.tfvars
06. terraform init
07. terraform fmt
08. terraform validate
09. terraform plan
10. Revisão do plan
11. terraform apply
12. ACM / Route 53
13. VPC
14. NAT
15. ALB
16. ASG + EC2
17. S3
18. CloudFront
19. WAF
20. CloudWatch / SNS
21. SSM
22. Testes
23. Evidências
24. Portfolio
25. Destroy quando necessário
```

**Não pule etapas.**
