# Mapeamento de Requisitos — NexCloud TCC

> **Projeto:** Escola Tech na AWS — Case 3  
> **Equipe:** NexCloud  
> **Fonte de verdade:** código Terraform em `04-terraform/`

---

## Tabela de Requisitos

| ID | Categoria | Requisito | Serviço(s) AWS | Status |
|----|-----------|-----------|---------------|--------|
| R01 | Disponibilidade | Alta disponibilidade — sem ponto único de falha | ALB + ASG + Multi-AZ | ✅ IMPLEMENTADO |
| R02 | Escalabilidade | Escalonamento automático conforme demanda | Auto Scaling Group | ✅ IMPLEMENTADO |
| R03 | Segurança | Proteção contra ataques web e DDoS L3/L4 | WAF + Shield Standard | ✅ IMPLEMENTADO |
| R04 | Segurança | HTTPS ponta-a-ponta para o usuário | ACM + CloudFront + ALB TLS 1.2+ | ✅ IMPLEMENTADO |
| R05 | DNS | Gerenciamento de DNS com monitoramento | Route 53 + Health Check | ✅ IMPLEMENTADO |
| R06 | Performance | Redução de latência via CDN | CloudFront | ✅ IMPLEMENTADO |
| R07 | Armazenamento | Armazenamento confiável para aplicação | EBS gp3 + S3 | ✅ IMPLEMENTADO |
| R08 | Backup | Backup automatizado com retenção | AWS Backup (EBS) + S3 versioning | ✅ IMPLEMENTADO |
| R09 | Monitoramento | Monitoramento proativo e alertas | CloudWatch + SNS | ✅ IMPLEMENTADO |
| R10 | IaC | Infraestrutura como Código versionável | Terraform | ✅ IMPLEMENTADO |
| R11 | Custo | Custo estimado e defensável | Pay-as-you-go (estimativa ~$156/mês) | ✅ IMPLEMENTADO |
| R12 | Segurança de rede | Isolamento de rede com acesso mínimo | VPC + Security Groups + SSM | ✅ IMPLEMENTADO |

---

## Detalhamento por Requisito

### R01 — Alta Disponibilidade

**Problema:** Servidor único on-premises — qualquer falha derruba o site.

**Implementação:**
- ALB Multi-AZ: distribui tráfego entre instâncias nas subnets públicas de `sa-east-1a` e `sa-east-1b`
- ASG `min_size=2`: garante ao menos uma instância em cada AZ
- `health_check_type=ELB`: instância com Nginx parado é removida do tráfego automaticamente
- ASG repõe instância falha sem intervenção manual
- CloudFront com cache reduz dependência da origem para conteúdo estático

**O que não está implementado:** failover ativo/passivo no Route 53 (não há registros PRIMARY/SECONDARY). A resiliência de DNS é provida pela disponibilidade intrínseca do CloudFront.

**Referência no código:** `ec2.tf` (ASG), `alb.tf` (Target Group health check), `vpc.tf` (Multi-AZ subnets)

---

### R02 — Escalabilidade

**Problema:** Picos de acesso durante matrículas derrubavam o servidor.

**Implementação:**
- Política **Target Tracking** — `ASGAverageCPUUtilization`, alvo 70%
- O ASG adiciona instâncias quando a CPU média ultrapassa 70% e remove quando cai abaixo
- `min=2`, `desired=2`, `max=4`
- `estimated_instance_warmup=300s` para aguardar o bootstrap antes de contar CPU
- Scheduled scaling: aumenta capacidade às 08h BRT em dias úteis
- Toda nova instância recebe o site automaticamente via S3 no bootstrap

**Como funciona o Target Tracking:** o ASG calcula a CPU média de todas as instâncias e ajusta a quantidade para manter a média próxima de 70%. Não é necessário definir threshold de scale-in separadamente — a política gerencia automaticamente.

**Referência no código:** `ec2.tf` (aws_autoscaling_policy.cpu_target_tracking, aws_autoscaling_schedule.business_hours)

---

### R03 — Segurança contra Ataques

**Problema:** Sem proteção WAF ou DDoS no servidor on-premises.

**Implementação:**
- **AWS WAF** associado ao CloudFront (escopo CLOUDFRONT, us-east-1) com 5 regras:
  1. `AWSManagedRulesCommonRuleSet` — OWASP Top 10
  2. `AWSManagedRulesSQLiRuleSet` — SQL Injection
  3. `AWSManagedRulesKnownBadInputsRuleSet` — inputs maliciosos conhecidos
  4. `AWSManagedRulesAmazonIpReputationList` — IPs com má reputação
  5. Rate-based rule — bloqueia IPs com mais de 2000 req/5min
- **Shield Standard** (gratuito): proteção automática contra DDoS Layer 3/4 em CloudFront, ALB e Route 53
- **Custom Header secreto**: ALB rejeita requisições sem `X-CF-Origin-Secret` correto — impede bypass do WAF

**O que o WAF protege:** ataques web Layer 7. O que o Shield Standard protege: ataques volumétricos Layer 3 e de protocolo Layer 4. Para proteção avançada Layer 7 DDoS, seria necessário Shield Advanced ($3.000/mês — não implementado).

**Referência no código:** `security.tf` (aws_wafv2_web_acl.main, random_password.cf_origin_secret), `alb.tf` (aws_lb_listener_rule.cloudfront_only)

---

### R04 — HTTPS

**Problema:** Acesso HTTP sem criptografia expunha dados dos alunos.

**Implementação:**
- Usuário → CloudFront: **HTTPS**, TLSv1.2_2021, certificado ACM us-east-1
- CloudFront → ALB: **HTTP** (protocolo de origem)
  - Justificativa: tráfego permanece dentro da rede AWS; o cert ACM cobre o domínio, não o DNS interno do ALB. O custom header secreto garante que só o CloudFront possa enviar requisições ao ALB.
- ALB → EC2: **HTTP** porta 80 (dentro da VPC)
- ALB listener HTTP:80 redireciona para HTTPS:443 (301)
- Certificados ACM provisionados e renovados automaticamente pela AWS

**Referência no código:** `security.tf` (aws_acm_certificate), `alb.tf` (listeners), `cloudfront.tf` (viewer_certificate, origin http-only)

---

### R05 — DNS

**Problema:** DNS sem gerenciamento centralizado ou monitoramento.

**Implementação:**
- Route 53 Hosted Zone para `var.domain_name`
- Registros A/AAAA para apex e www com alias para CloudFront
- Health Check HTTPS `/health` monitorando o endpoint principal
- **Pré-requisito:** domínio registrado e name servers delegados para a Hosted Zone. Sem isso, os registros não têm efeito. Para testes sem domínio, usar o output `website_url_cloudfront`.

**O que não está implementado:** failover ativo/passivo (sem registros com routing policy FAILOVER). O health check é de monitoramento apenas.

**Referência no código:** `route53.tf`

---

### R06 — Performance

**Problema:** Todos os usuários acessavam diretamente o servidor em São Paulo.

**Implementação:**
- CloudFront com `PriceClass_All` distribui conteúdo a partir de edge locations próximas ao usuário
- Cache behavior `/static/*`: TTL padrão 86400s (24h) para assets estáticos no S3
- Conteúdo dinâmico (HTML do ALB): TTL=0 (sem cache)
- Compressão gzip/brotli habilitada no CloudFront

**O que não é afirmado:** latência específica em ms (não foi medida). A melhoria de performance é esperada pela natureza do CDN, mas depende da localização do usuário, tamanho dos arquivos e taxa de cache hit.

**Referência no código:** `cloudfront.tf` (cache policies, ordered_cache_behavior)

---

### R07 — Armazenamento

**Problema:** Disco local sem IOPS garantido, sem redundância.

**Implementação:**
- EBS gp3 20 GB por instância: 3000 IOPS e 125 MB/s baseline inclusos, criptografado
- S3 bucket de assets: privado, versionamento, OAC para CloudFront e acesso para EC2
- `aws_s3_object` faz upload do `index.html` via Terraform no `apply`
- Durabilidade do S3: 99,999999999% (SLA AWS — não afirmamos como próprio)

**Referência no código:** `ec2.tf` (block_device_mappings), `s3.tf` (aws_s3_bucket.assets, aws_s3_object.index_html)

---

### R08 — Backup

**Problema:** Sem backup automatizado. RTO e RPO indefinidos.

**Implementação:**
- **AWS Backup Plan** `ebs-daily`: snapshot diário de todos os volumes EBS com tag `ManagedBy=Terraform`, às 02:00 UTC (23h BRT), retenção 7 dias
- **S3 Versioning** no bucket de assets: protege contra sobrescrita acidental do index.html, versões antigas expiram em 30 dias
- **S3 Lifecycle** no bucket de backups: Standard → S3-IA (7d) → Glacier (30d)

**O que não existe:** backup de banco de dados. Este projeto não possui banco de dados — o site é HTML estático servido pelo Nginx. Não há cron job manual — o backup é gerenciado pelo AWS Backup.

**RPO estimado:** até 24h (frequência do snapshot). **RTO estimado:** depende do tempo de provisionamento de nova instância + restauração de snapshot — não foi medido.

**Referência no código:** `monitoring.tf` (aws_backup_plan.ebs_daily, aws_backup_selection.ebs, aws_backup_vault.main)

---

### R09 — Monitoramento

**Problema:** Sem visibilidade sobre a saúde da aplicação.

**Implementação:**
- **5 alarmes CloudWatch** com notificação via SNS:
  - `cpu-high`: CPU ≥ 70% por 2 minutos
  - `ec2-status-check`: falha de status check
  - `alb-5xx`: erros 5xx ≥ 10/min
  - `alb-latency`: p95 latência ≥ 2s
  - `alb-unhealthy-hosts`: hosts unhealthy no TG
  - `alb-no-healthy-hosts`: zero hosts saudáveis (crítico)
- **Dashboard CloudWatch** com CPU, ALB requests, latência, códigos HTTP, instâncias ASG e hosts
- **CloudWatch Logs**: nginx-access, nginx-error, bootstrap (via CW Agent nas EC2)
- **SNS**: notificação por e-mail — requer confirmação da assinatura após `terraform apply`

**Importante:** alarmes CloudWatch são diferentes de scaling policies. O scaling é controlado exclusivamente pela política Target Tracking. Os alarmes apenas notificam.

**Referência no código:** `monitoring.tf`

---

### R10 — Infraestrutura como Código

**Implementação:**
- Terraform >= 1.5.0, provider AWS ~> 5.0, provider Random ~> 3.6
- 12 arquivos `.tf` + `user_data.sh.tpl` + `terraform.tfvars.example`
- Backend: local (state em `terraform.tfstate`). Instruções para backend S3 comentadas em `main.tf`
- Quantidade real de recursos: executar `terraform plan` para obter o número exato. Não declaramos "N recursos" sem evidência do plan.

**Comandos:**
```bash
cd 04-terraform
terraform init
terraform validate
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

**Referência:** `04-terraform/` (todos os arquivos .tf)

---

### R11 — Custo Otimizado

**Implementação:**
- Modelo pay-as-you-go (On-Demand), sem compromisso
- Estimativa mensal de referência: **~$156/mês**
- Detalhamento completo em `03-custos/estimativa-custos.md` e `03-custos/custos.csv`
- Conversão para BRL depende do câmbio do dia — não fixado
- Comparativo com on-premises é **cenário hipotético** rotulado — sem dados reais do case

**Referência:** `03-custos/`

---

### R12 — Isolamento de Rede

**Implementação:**
- EC2 em subnets privadas: sem IP público, inacessível diretamente da internet
- ALB em subnets públicas: único ponto de entrada controlado
- SG ALB: ingress 80/443 da internet
- SG EC2: ingress 80 apenas do SG ALB
- Sem SSH aberto: acesso via SSM Session Manager
- NAT Gateway: permite saída das EC2 (updates, S3, SSM) sem exposição de IP
- S3 com Block Public Access em todos os buckets
- VPC Flow Logs habilitados para auditoria de tráfego

**Referência no código:** `vpc.tf`, `security.tf`

---

## Matriz de Rastreabilidade

```
R01 → ec2.tf (asg min_size=2, health_check_type=ELB)
      alb.tf (target group health check /health)
      vpc.tf (subnets multi-AZ)

R02 → ec2.tf (aws_autoscaling_policy.cpu_target_tracking)
      ec2.tf (aws_autoscaling_schedule.business_hours)
      user_data.sh.tpl (site do S3 no boot)

R03 → security.tf (aws_wafv2_web_acl.main)
      security.tf (random_password.cf_origin_secret)
      alb.tf (aws_lb_listener_rule.cloudfront_only)

R04 → security.tf (aws_acm_certificate.cloudfront, aws_acm_certificate.alb)
      alb.tf (aws_lb_listener.http redirect, aws_lb_listener.https)
      cloudfront.tf (viewer_certificate TLSv1.2_2021)

R05 → route53.tf (aws_route53_zone.main)
      route53.tf (aws_route53_record apex/www A/AAAA)
      route53.tf (aws_route53_health_check.main)

R06 → cloudfront.tf (aws_cloudfront_distribution.main)
      cloudfront.tf (aws_cloudfront_cache_policy.static_assets)

R07 → ec2.tf (block_device_mappings gp3 20GB)
      s3.tf (aws_s3_bucket.assets)
      s3.tf (aws_s3_object.index_html)

R08 → monitoring.tf (aws_backup_plan.ebs_daily)
      monitoring.tf (aws_backup_selection.ebs)
      monitoring.tf (aws_backup_vault.main)
      s3.tf (aws_s3_bucket_versioning.assets)

R09 → monitoring.tf (aws_cloudwatch_metric_alarm x5)
      monitoring.tf (aws_cloudwatch_dashboard.main)
      monitoring.tf (aws_sns_topic.alerts)
      monitoring.tf (aws_cloudwatch_log_group x3)
      user_data.sh.tpl (CW Agent config inline)

R10 → 04-terraform/ (todos os arquivos .tf)
      04-terraform/user_data.sh.tpl
      04-terraform/terraform.tfvars.example

R11 → 03-custos/estimativa-custos.md
      03-custos/custos.csv

R12 → vpc.tf (subnets privadas, NAT GW, route tables)
      security.tf (aws_security_group.alb, aws_security_group.ec2)
      vpc.tf (aws_flow_log.main)
```

---

*NexCloud TCC — Status baseado no código em `04-terraform/` — não em documentação anterior*