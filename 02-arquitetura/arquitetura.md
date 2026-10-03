# Arquitetura da Solução — NexCloud TCC

> **Projeto:** Escola Tech na AWS — Case 3  
> **Equipe:** NexCloud | **Região:** sa-east-1 (São Paulo)  
> **IaC:** Terraform >= 1.5.0 | **SO:** Amazon Linux 2023

---

## Diagrama ASCII

```
                        INTERNET
                            │
                    ┌───────▼────────┐
                    │   Route 53     │
                    │  Hosted Zone   │
                    │  A/AAAA alias  │
                    │  Health Check  │
                    └───────┬────────┘
                            │
                    ┌───────▼────────┐
                    │  CloudFront    │
                    │  CDN / TLS     │
                    │  WAF acoplado  │
                    └───────┬────────┘
                            │  HTTPS (usuário → CF)
                    ┌───────▼────────┐
                    │   AWS WAF      │
                    │  5 regras      │
                    │  Rate Limit    │
                    └───────┬────────┘
                            │  HTTP + X-CF-Origin-Secret header
          ┌─────────────────▼──────────────────────┐
          │         VPC  10.0.0.0/16                │
          │                                         │
          │  ┌──── sa-east-1a ──┐  ┌─sa-east-1b──┐ │
          │  │ Subnet Pública   │  │Subnet Pública│ │
          │  │ 10.0.1.0/24      │  │10.0.2.0/24   │ │
          │  │  NAT-GW-A  IGW◄──┼──┼──►IGW NAT-B  │ │
          │  │    ▲             │  │         ▲    │ │
          │  └────┼─────────────┘  └─────────┼────┘ │
          │       │                           │      │
          │  ┌────┼─────────────────────────┐ │      │
          │  │    │   ALB  (multi-AZ)        │ │      │
          │  │    └──────────┬──────────────┘ │      │
          │  └───────────────┼────────────────┘      │
          │                  │ Target Group           │
          │  ┌───────────────▼──────────────────────┐ │
          │  │         Auto Scaling Group            │ │
          │  │  min=2  desired=2  max=4              │ │
          │  │  Target Tracking  CPU→70%             │ │
          │  └───────────┬──────────────┬────────────┘ │
          │              │              │               │
          │  ┌───────────▼──┐  ┌───────▼────────────┐  │
          │  │Subnet Privada│  │  Subnet Privada    │  │
          │  │10.0.10.0/24  │  │  10.0.11.0/24      │  │
          │  │              │  │                    │  │
          │  │ EC2 t3.small │  │  EC2 t3.small      │  │
          │  │ AL2023       │  │  AL2023            │  │
          │  │ Nginx        │  │  Nginx             │  │
          │  │ EBS gp3 20GB │  │  EBS gp3 20GB      │  │
          │  └──────────────┘  └────────────────────┘  │
          │                                            │
          │  ┌─────────────────────────────────────┐   │
          │  │  S3 (3 buckets — fora da VPC)        │   │
          │  │  assets | logs | backups             │   │
          │  └─────────────────────────────────────┘   │
          └────────────────────────────────────────────┘

Serviços transversais (fora da VPC):
  CloudWatch (alarmes + dashboard + logs)
  SNS (alertas por e-mail)
  AWS Backup (snapshots EBS diários)
  SSM Session Manager (acesso administrativo)
  ACM (certificados TLS — us-east-1 e sa-east-1)
```

---

## Fluxo de Tráfego

### Requisição do usuário (caminho completo)

```
1. Usuário → HTTPS → Route 53
   └─ Resolve DNS: alias A/AAAA → CloudFront distribution domain

2. Route 53 → CloudFront (edge location)
   └─ TLS terminado no CloudFront (cert ACM us-east-1)
   └─ WAF inspeciona a requisição

3. CloudFront → ALB (origin)
   └─ Protocolo HTTP (porta 80)
   └─ Header X-CF-Origin-Secret injetado

4. ALB Listener HTTPS:443 (recebe em HTTPS do usuário via CF)
   └─ Listener rule valida X-CF-Origin-Secret
   └─ Sem o header → retorna 403
   └─ Com o header → encaminha para Target Group

5. Target Group → EC2 (subnet privada)
   └─ HTTP porta 80
   └─ Nginx serve /health (health check) ou index.html

6. EC2 → S3 (apenas no bootstrap)
   └─ aws s3 cp s3://bucket/site/index.html /var/www/html/
   └─ Via NAT Gateway (EC2 está em subnet privada)
```

### Acesso administrativo

```
Engenheiro → AWS Console → SSM Session Manager → EC2 (subnet privada)
Sem SSH. Sem bastion host. Sem porta 22 aberta.
```

### Bootstrap de nova instância (ASG scale-out)

```
ASG cria EC2 → user_data.sh.tpl executa:
  1. dnf update + dnf install nginx amazon-cloudwatch-agent
  2. Configura Nginx + endpoint /health
  3. aws s3 cp s3://<assets-bucket>/site/index.html /var/www/html/
  4. Inicia Nginx e CloudWatch Agent
  5. Valida /health (curl localhost/health → 200)
  6. Registra log em /var/log/user-data.log
→ ALB health check detecta instância healthy
→ Target Group registra instância
→ ALB começa a enviar tráfego
```

---

## Componentes

### Rede

| Recurso | Configuração | Arquivo |
|---------|-------------|---------|
| VPC | 10.0.0.0/16, DNS habilitado | vpc.tf |
| Subnet pública AZ-a | 10.0.1.0/24, sa-east-1a | vpc.tf |
| Subnet pública AZ-b | 10.0.2.0/24, sa-east-1b | vpc.tf |
| Subnet privada AZ-a | 10.0.10.0/24, sa-east-1a | vpc.tf |
| Subnet privada AZ-b | 10.0.11.0/24, sa-east-1b | vpc.tf |
| Internet Gateway | 1 por VPC | vpc.tf |
| NAT Gateway AZ-a | Subnet pública AZ-a, EIP | vpc.tf |
| NAT Gateway AZ-b | Subnet pública AZ-b, EIP | vpc.tf |
| VPC Flow Logs | CloudWatch Logs, retenção 30d | vpc.tf |

### Computação

| Recurso | Configuração | Arquivo |
|---------|-------------|---------|
| AMI | Amazon Linux 2023 via SSM Parameter | main.tf |
| Tipo | t3.small (2 vCPU, 2 GB RAM) | variables.tf |
| EBS | gp3, 20 GB, 3000 IOPS, 125 MB/s, criptografado | ec2.tf |
| ASG min | 2 (garante presença nas 2 AZs) | variables.tf |
| ASG desired | 2 | variables.tf |
| ASG max | 4 | variables.tf |
| Scaling | Target Tracking, CPU alvo 70% | ec2.tf |
| IMDSv2 | Obrigatório (http_tokens=required) | ec2.tf |
| IP público | Não (subnet privada) | ec2.tf |
| Acesso admin | SSM Session Manager | security.tf |

### Balanceamento e CDN

| Recurso | Configuração | Arquivo |
|---------|-------------|---------|
| ALB | internet-facing, Multi-AZ, subnets públicas | alb.tf |
| Listener HTTP:80 | Redirect → HTTPS 301 | alb.tf |
| Listener HTTPS:443 | Default action: 403 | alb.tf |
| Listener Rule | Valida X-CF-Origin-Secret → forward TG | alb.tf |
| Target Group | HTTP:80, health check /health | alb.tf |
| Health Check | /health, interval=30s, threshold=2 | alb.tf |
| CloudFront | Multi-AZ edge, aliases domínio | cloudfront.tf |
| CloudFront → ALB | HTTP (origin), header secreto | cloudfront.tf |
| Viewer protocol | redirect-to-https | cloudfront.tf |
| TLS | TLSv1.2_2021, ACM us-east-1 | cloudfront.tf |

### Segurança

| Recurso | Configuração | Arquivo |
|---------|-------------|---------|
| SG ALB | Ingress 80/443 da internet | security.tf |
| SG EC2 | Ingress 80 apenas do SG ALB | security.tf |
| WAF | CLOUDFRONT scope, 5 regras | security.tf |
| Custom Header | X-CF-Origin-Secret, valor aleatório | security.tf |
| ACM CloudFront | us-east-1, wildcard | security.tf |
| ACM ALB | sa-east-1, wildcard | security.tf |
| Shield Standard | Automático (gratuito) | — |
| IMDSv2 | Obrigatório nas EC2 | ec2.tf |
| EBS criptografado | AES-256 | ec2.tf |
| S3 Block Public | Todos os buckets | s3.tf |
| S3 encryption | SSE-S3 (AES-256) | s3.tf |

### DNS

| Recurso | Configuração | Arquivo |
|---------|-------------|---------|
| Route 53 Hosted Zone | var.domain_name | route53.tf |
| A/AAAA apex | Alias → CloudFront | route53.tf |
| A/AAAA www | Alias → CloudFront | route53.tf |
| Health Check | HTTPS /health, 30s, threshold=3 | route53.tf |

> **Nota:** O health check monitora o endpoint principal. Não há failover ativo/passivo configurado (sem registros PRIMARY/SECONDARY). A resiliência é provida pelo ASG e pelo ALB Multi-AZ.

### Storage

| Recurso | Configuração | Arquivo |
|---------|-------------|---------|
| S3 assets | Privado, OAC, versionamento, lifecycle | s3.tf |
| S3 logs | ALB + CloudFront logs, lifecycle 365d | s3.tf |
| S3 backups | Assets/config, lifecycle Glacier 30d | s3.tf |
| aws_s3_object | index.html enviado pelo Terraform | s3.tf |

### Monitoramento e Backup

| Recurso | Configuração | Arquivo |
|---------|-------------|---------|
| SNS | e-mail, requer confirmação | monitoring.tf |
| CloudWatch Alarmes | 5 alarmes (ver tabela abaixo) | monitoring.tf |
| CloudWatch Dashboard | CPU, ALB, ASG, hosts | monitoring.tf |
| CloudWatch Log Groups | nginx-access, nginx-error, bootstrap | monitoring.tf |
| AWS Backup | EBS diário 02h UTC, retenção 7 dias | monitoring.tf |
| CW Agent | Configuração inline, sem SSM externo | user_data.sh.tpl |

**Alarmes CloudWatch:**

| Alarme | Métrica | Threshold | Ação |
|--------|---------|-----------|------|
| cpu-high | CPUUtilization (ASG) | ≥ 70%, 2×60s | SNS |
| ec2-status-check | StatusCheckFailed | ≥ 1, 1×60s | SNS |
| alb-5xx | HTTPCode_Target_5XX_Count | ≥ 10, 1×60s | SNS |
| alb-latency | TargetResponseTime p95 | ≥ 2s, 2×60s | SNS |
| alb-unhealthy-hosts | UnHealthyHostCount | ≥ 1, 1×60s | SNS |
| alb-no-healthy-hosts | HealthyHostCount | ≤ 0, 1×60s | SNS |

> Scaling é gerenciado pela política **Target Tracking** (cpu_target_tracking em ec2.tf), não pelos alarmes CloudWatch.

---

## Decisões de Arquitetura

| Decisão | Justificativa |
|---------|--------------|
| AL2023 (não AL2) | AL2 está em fim de suporte. AL2023 usa dnf, sem amazon-linux-extras. |
| AMI via SSM Parameter | Sempre obtém a AMI mais recente sem filtros frágeis por nome. |
| HTTP CloudFront→ALB | Evita erro 502 por mismatch de certificado. O cert ACM cobre o domínio, não o DNS interno do ALB. Segurança garantida pelo header secreto. |
| Custom Header aleatório | Valor gerado por `random_password` no Terraform. Não exposto em documentação. |
| ALB default action 403 | Sem o header do CloudFront, o ALB rejeita a requisição diretamente. |
| min_size = 2 | Garante presença em ambas as AZs mesmo sem tráfego. |
| Uma política Target Tracking | Simples, defensável e suficiente. Evita conflito entre múltiplas políticas. |
| Site no S3 → EC2 no boot | Toda instância criada pelo ASG obtém o site automaticamente, sem intervenção manual. |
| AWS Backup para EBS | Snapshots diários com retenção de 7 dias sem necessidade de cron manual. |
| Sem failover R53 | O Case 3 não exige endpoint secundário. Resiliência é responsabilidade do ALB+ASG. |
| Sem PHP-FPM | O site é HTML estático. PHP não é necessário e aumenta a superfície de ataque. |

---

*NexCloud TCC — Código é a fonte de verdade — sa-east-1*