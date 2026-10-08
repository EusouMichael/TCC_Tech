# Escola Tech AWS — TCC NexCloud

> **Equipe:** NexCloud | **Case:** 3 — Hospedagem de Site Institucional  
> **Região:** sa-east-1 (São Paulo) | **IaC:** Terraform ≥ 1.5.0  
> **SO:** Amazon Linux 2023 | **Servidor web:** Nginx + API Node.js

---

## 1. Visão Geral

Este projeto provisiona a infraestrutura AWS para o site institucional da **Escola Tech** — uma plataforma de cursos de tecnologia. A solução migra um servidor on-premises com ponto único de falha para uma arquitetura cloud-native Multi-AZ com escalabilidade automática, segurança em camadas e monitoramento proativo.

Todo o ambiente é gerenciado como Infraestrutura como Código via Terraform. O código neste repositório é a fonte de verdade — a documentação reflete o que está implementado, não o que seria ideal.

---

## 2. Problema

O site on-premises apresentava indisponibilidade durante períodos de matrícula por:
- Servidor único (ponto único de falha)
- Sem capacidade de escalonamento horizontal
- Sem proteção WAF ou DDoS
- Backup sem automação

---

## 3. Objetivo

Prover uma arquitetura AWS que:
- Elimine o ponto único de falha (Multi-AZ)
- Escale automaticamente conforme demanda (ASG)
- Proteja contra ataques web (WAF) e DDoS L3/L4 (Shield Standard)
- Garanta HTTPS ponta-a-ponta para o usuário (CloudFront + ACM)
- Seja completamente reproducível (Terraform)
- Tenha monitoramento proativo com alertas (CloudWatch + SNS)
- Faça backup automatizado dos volumes EBS e do banco RDS
- Permita cadastro persistente de alunos/clientes com PostgreSQL

---

## 4. Arquitetura

```
Internet → Route 53 → CloudFront → WAF → ALB → ASG → EC2 (Nginx + API)
                                                ↓
                                         RDS PostgreSQL privado
                                                ↕
                                         Secrets Manager / IAM

EC2 → S3 (assets) | CloudWatch | SSM | NAT Gateway
```

**Detalhes:**
- VPC 10.0.0.0/16 com 4 subnets (2 públicas + 2 privadas) em 2 AZs
- CloudFront → ALB: protocolo **HTTPS** via `origin.<dominio>` com certificado ACM e header secreto `X-CF-Origin-Secret`
  - O ALB rejeita (403) qualquer requisição sem o header correto
  - TLS é mantido também entre CloudFront e ALB; o hostname `origin.<dominio>` aponta por alias para o ALB
- EC2 em subnets privadas: sem IP público, acesso via SSM Session Manager
- ASG: min=2 / desired=2 / max=4, política Target Tracking CPU 70%

Diagrama completo e fluxo detalhado: [`02-arquitetura/arquitetura.md`](02-arquitetura/arquitetura.md)

---

## 5. Serviços AWS

| Serviço | Uso |
|---------|-----|
| Route 53 | DNS + health check |
| CloudFront | CDN + TLS ponta-a-ponta + WAF |
| AWS WAF | Proteção L7 (OWASP, SQLi, rate limit) |
| Shield Standard | DDoS L3/L4 (gratuito, automático) |
| ACM | Certificados TLS (gratuito para serviços AWS) |
| ALB | Balanceamento de carga Multi-AZ |
| Auto Scaling Group | Escalabilidade automática |
| EC2 t3.small | Amazon Linux 2023, Nginx |
| S3 | Assets do site, logs, backups |
| CloudWatch | Métricas, alarmes, dashboard, logs |
| SNS | Alertas por e-mail |
| AWS Backup | Snapshots EBS diários + retenção |
| Amazon RDS PostgreSQL | Cadastro persistente de alunos/clientes, Multi-AZ |
| Secrets Manager | Credencial master gerenciada pelo RDS |
| IAM DB Authentication | Acesso da API ao PostgreSQL sem senha persistente |
| SSM Session Manager | Acesso administrativo (sem SSH) |

---

## 6. Segurança

- **WAF** associado ao CloudFront com 5 regras gerenciadas
- **Custom header secreto** (`X-CF-Origin-Secret`) gerado aleatoriamente pelo Terraform — ALB bloqueia requisições sem ele
- **SG EC2**: aceita porta 80 apenas do SG do ALB
- **EC2 sem IP público**: subnets privadas, acesso via SSM
- **IMDSv2** obrigatório nas instâncias
- **EBS criptografado** (AES-256)
- **S3** com Block Public Access em todos os buckets
- **RDS** privado, sem acesso público, SG aceitando 5432 somente do SG EC2
- **RDS** com armazenamento criptografado e backup automático
- **API** usa usuário PostgreSQL dedicado com autenticação IAM e privilégios mínimos
- **VPC Flow Logs** habilitados

---

## 7. Alta Disponibilidade

- ALB distribuído em 2 AZs (`sa-east-1a` e `sa-east-1b`)
- ASG com `min_size=2` garante ao menos uma instância por AZ
- Health check ELB: instâncias com Nginx parado são removidas do tráfego automaticamente
- ASG repõe instâncias falhas sem intervenção manual

> A arquitetura é projetada para alta disponibilidade. Disponibilidade real depende dos SLAs dos serviços AWS individuais, do correto funcionamento do bootstrap e de outros fatores operacionais.

---

## 8. Auto Scaling

- Política **Target Tracking** — CPU alvo 70%
- O ASG aumenta instâncias quando a CPU média sobe e remove quando cai (sem descer abaixo de min=2)
- Cada nova instância executada pelo ASG recebe o site automaticamente via `user_data.sh.tpl`:
  1. Instala Nginx via `dnf` (AL2023)
  2. Busca `index.html` do S3 (`aws s3 cp`)
  3. Configura e inicia Nginx
  4. Valida `/health` retorna HTTP 200

---

## 9. Monitoramento

6 alarmes CloudWatch configurados em `monitoring.tf`:

| Alarme | Threshold | Ação |
|--------|-----------|------|
| cpu-high | CPU ≥ 70%, 2×60s | E-mail SNS |
| ec2-status-check | Falha de status | E-mail SNS |
| alb-5xx | ≥ 10 erros 5xx/min | E-mail SNS |
| alb-latency | p95 ≥ 2s, 2×60s | E-mail SNS |
| alb-unhealthy-hosts | ≥ 1 unhealthy | E-mail SNS |
| alb-no-healthy-hosts | = 0 healthy | E-mail SNS |

> Os alarmes apenas **notificam**. O scaling é gerenciado exclusivamente pela política Target Tracking.

**Após o `terraform apply`:** confirmar a assinatura no e-mail SNS recebido.

---

## 10. Banco de dados e cadastro

- **RDS PostgreSQL** em subnets privadas, sem acesso público e Multi-AZ.
- **Secrets Manager** gerencia a senha do usuário master; a aplicação não recebe uma senha fixa em código.
- A API cria o usuário `app_user` e usa **IAM Database Authentication** para conexões da aplicação.
- O formulário do site envia `POST /api/enrollments` e grava os dados na tabela `enrollments`.
- Conexões EC2 → RDS usam TLS com o bundle oficial de CA do RDS.
- O SG do RDS permite TCP/5432 somente do SG das EC2.

## 11. Backup

- **AWS Backup**: snapshots EBS diários, retenção 7 dias.
- **RDS**: backup automático, retenção 7 dias e Multi-AZ.
- **S3 Versioning**: no bucket de assets, protege contra sobrescrita do `index.html`.

---

## 12. Terraform

### Pré-requisitos

```bash
# Terraform >= 1.5.0
terraform -version

# AWS CLI configurado
aws configure
# ou via variáveis de ambiente:
# export AWS_ACCESS_KEY_ID=...
# export AWS_SECRET_ACCESS_KEY=...
# export AWS_DEFAULT_REGION=sa-east-1
```

### Estrutura dos arquivos

```
04-terraform/
├── main.tf              # provider AWS + Random + data sources (AMI AL2023)
├── variables.tf         # todas as variáveis com descriptions
├── outputs.tf           # outputs pós-apply
├── vpc.tf               # VPC, subnets, IGW, NAT GW, route tables, flow logs
├── security.tf          # SGs, WAF, ACM, IAM, header secreto
├── ec2.tf               # Launch Template, ASG, Target Tracking
├── alb.tf               # ALB, Target Group, listeners
├── cloudfront.tf        # CDN, cache policies, OAC
├── route53.tf           # Hosted Zone, records A/AAAA, health check
├── s3.tf                # 3 buckets + upload do index.html
├── monitoring.tf        # CloudWatch alarmes, dashboard, SNS, AWS Backup
├── user_data.sh.tpl     # bootstrap AL2023 (dnf + Nginx + S3 download)
└── terraform.tfvars.example  # variáveis de exemplo
```

### Deploy

```bash
cd 04-terraform

# Copiar e editar as variáveis
cp terraform.tfvars.example terraform.tfvars
# Editar terraform.tfvars: domain_name, alert_email, etc.

# Inicializar providers
terraform init

# Validar estrutura (requer Terraform CLI)
terraform validate

# Revisar o plano
terraform plan -var-file=terraform.tfvars

# Aplicar
terraform apply -var-file=terraform.tfvars

# Ver outputs
terraform output
```

### Outputs principais após apply

| Output | Descrição |
|--------|-----------|
| `website_url_cloudfront` | URL via CloudFront — funciona sem domínio registrado |
| `website_url` | URL com domínio customizado (requer DNS delegado) |
| `alb_dns_name` | DNS do ALB para testes diretos |
| `route53_name_servers` | Name servers para configurar no registrador |
| `asg_name` | Nome do ASG |
| `s3_assets_bucket` | Nome do bucket de assets |

### Destruir (após apresentação)

```bash
terraform destroy -var-file=terraform.tfvars
```

> **Importante:** executar `terraform destroy` após a apresentação para evitar custos contínuos. Custo estimado para 4 horas de demo: inferior a $1.

### Backend

O estado é armazenado **localmente** em `terraform.tfstate`. Para uso em equipe, descomente e configure o bloco `backend "s3"` em `main.tf` (instrução no próprio arquivo).

---

## 13. Custos

Estimativa de referência para ambiente ativo 24/7, agora incluindo RDS Multi-AZ:

| Categoria | Estimativa/mês |
|-----------|---------------|
| EC2 t3.small × 2 (On-Demand) | ~$49 |
| NAT Gateway × 2 (fixo + dados) | ~$39 |
| ALB | ~$22 |
| WAF | ~$11 |
| CloudFront | ~$5 |
| RDS PostgreSQL Multi-AZ db.t4g.micro + 20 GB | ~$75 |
| Demais (EBS, S3, CW, R53, Backup) | ~$12 |
| **Total estimado** | **~$230/mês** |

> Valores variáveis dependem de tráfego, requests e volume de dados. Câmbio BRL não fixado — usar cotação do dia. Detalhamento em [`03-custos/estimativa-custos.md`](03-custos/estimativa-custos.md).

---

## 14. Deploy do Site

O `index.html` em `05-website/` é enviado para o S3 automaticamente pelo Terraform:

```hcl
resource "aws_s3_object" "index_html" {
  bucket = aws_s3_bucket.assets.id
  key    = "site/index.html"
  source = "../05-website/index.html"
}
```

Para atualizar o site: editar `05-website/index.html` e rodar `terraform apply`.  
Cada nova EC2 criada pelo ASG busca automaticamente o arquivo mais recente do S3 no bootstrap.

---

## 15. Testes

Após o `terraform apply`:

```bash
# 1. Site acessível
curl -I https://<cloudfront_domain_name>

# 2. Health check
curl https://<cloudfront_domain_name>/health
# Esperado: HTTP 200, body "healthy"

# 3. ALB rejeita sem header (via DNS direto do ALB)
curl -I https://<alb_dns_name>
# Esperado: HTTP 403 (sem o header secreto do CloudFront)

# 4. Verificar API e banco
curl https://<cloudfront_domain_name>/api/health
# Esperado: HTTP 200 e {"status":"ok","database":"ok"}

# 5. Testar cadastro
curl -X POST https://<cloudfront_domain_name>/api/enrollments \
  -H "Content-Type: application/json" \
  -d '{"firstName":"Aluno Teste","email":"teste@example.com","course":"aws","experience":"iniciante","message":"Teste TCC"}'
# Esperado: HTTP 201 com o ID do cadastro

# 6. Verificar instâncias no Target Group
aws elbv2 describe-target-health \
  --target-group-arn <target_group_arn> \
  --region sa-east-1
```

Checklist funcional completo: [`06-monitoramento/monitoramento.md`](06-monitoramento/monitoramento.md)

---

## 16. Demonstração

Roteiro completo de 10–12 minutos: [`01-apresentacao/roteiro-demo.md`](01-apresentacao/roteiro-demo.md)

Slides (16 slides navegáveis): abrir [`01-apresentacao/slides.html`](01-apresentacao/slides.html) no navegador.

---

## 17. Estrutura do Repositório

```
nexcloud-tcc/
├── README.md
├── 01-apresentacao/
│   ├── slides.html              ← 16 slides navegáveis (HTML, abre no navegador)
│   └── roteiro-demo.md          ← roteiro da demonstração ao vivo
├── 02-arquitetura/
│   ├── arquitetura.md           ← diagrama ASCII + fluxo + decisões
│   └── requisitos.md            ← R01-R12 com rastreabilidade para arquivos .tf
├── 03-custos/
│   ├── estimativa-custos.md     ← análise detalhada com premissas declaradas
│   └── custos.csv               ← tabela com matemática verificada
├── 04-terraform/
│   ├── main.tf                  ← providers + AMI AL2023 via SSM
│   ├── variables.tf             ← variáveis com validações
│   ├── outputs.tf               ← outputs pós-apply
│   ├── vpc.tf                   ← VPC Multi-AZ
│   ├── security.tf              ← SGs, WAF, ACM, IAM, header secreto
│   ├── ec2.tf                   ← Launch Template + ASG + Target Tracking
│   ├── alb.tf                   ← ALB + Target Group + listeners
│   ├── cloudfront.tf            ← CDN + cache policies + OAC
│   ├── route53.tf               ← DNS + health check
│   ├── s3.tf                    ← buckets + upload do index.html
│   ├── monitoring.tf            ← CloudWatch + SNS + AWS Backup
│   ├── user_data.sh.tpl         ← bootstrap AL2023 + API
│   ├── database.tf              ← RDS PostgreSQL Multi-AZ
│   └── terraform.tfvars.example ← variáveis de exemplo
├── 05-website/
│   └── index.html               ← site + formulário conectado à API
├── 06-monitoramento/
│   └── monitoramento.md
└── 07-api/
    ├── package.json              ← dependências da API
    └── server.js                 ← API Node.js + PostgreSQL/IAM
    └── monitoramento.md         ← alarmes, logs, backup, runbooks
```

---

## 18. Deploy na AWS

O passo a passo operacional está em [`AWS_DEPLOYMENT.md`](AWS_DEPLOYMENT.md) e o checklist de go-live em [`AWS_GO_LIVE_CHECKLIST.md`](AWS_GO_LIVE_CHECKLIST.md).

O pipeline inicial em `.github/workflows/terraform-check.yml` executa `terraform fmt` e `terraform validate`. O deploy automático com OIDC será configurado depois que o primeiro ambiente manual estiver validado.

## 19. Limitações

- **Banco:** o primeiro bootstrap cria o usuário da aplicação e a tabela de cadastros usando o usuário master gerenciado pelo RDS; as conexões normais da API usam IAM Database Authentication.
- **Domínio:** `escolatech.com.br` deve ser registrado e ter name servers delegados para a Hosted Zone do Route 53. Sem isso, usar o output `website_url_cloudfront`.
- **Terraform CLI:** necessário para `terraform apply`. Versão mínima: 1.5.0. Download: https://developer.hashicorp.com/terraform/install
- **Credenciais AWS:** conta AWS com permissões para criar os recursos listados.
- **t3 CPU credits:** instâncias t3.small podem gerar custo adicional de surplus credits se a CPU ficar acima de 20% de forma prolongada. Monitorar o alarme `cpu-high`.
- **Validação `terraform validate`:** o GitHub Actions executa `terraform fmt -check` e `terraform validate` a cada alteração relevante; o apply continua sendo uma etapa deliberada no ambiente AWS.
- **Terraform plan:** o número exato de recursos só é conhecido após executar `terraform plan` no ambiente com credenciais AWS.

---

## 20. Próximos Passos

- CI/CD com CodePipeline + S3 para deploy automático do site
- EC2 Reserved Instances (1 ano) para reduzir custo EC2 em ~40%
- VPC Endpoints para S3 e SSM (reduz tráfego pelo NAT Gateway)
- HTTPS CloudFront→ALB com subdomínio de origem dedicado
- AWS Config para conformidade de recursos

---

*NexCloud TCC — Computação em Nuvem — AWS sa-east-1 (São Paulo)*