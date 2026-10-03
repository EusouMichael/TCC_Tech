# Estratégia de Monitoramento — NexCloud TCC

> **Projeto:** Escola Tech na AWS  
> **Equipe:** NexCloud | **Requisito:** R09  
> **Fonte de verdade:** `04-terraform/monitoring.tf`

---

## Visão Geral

O monitoramento é baseado em três pilares, todos implementados via Terraform:

| Pilar | Ferramenta | O que cobre |
|-------|-----------|------------|
| Métricas | CloudWatch Metrics (nativas AWS) | CPU, latência, erros HTTP, hosts saudáveis |
| Logs | CloudWatch Logs + CW Agent | Nginx access/error, bootstrap das EC2 |
| Alertas | CloudWatch Alarms + SNS | Notificação por e-mail |
| Backup | AWS Backup | Snapshots EBS diários |

---

## Alarmes CloudWatch

Os alarmes abaixo estão **implementados** em `monitoring.tf`. Todos enviam notificação via SNS para o e-mail configurado em `var.alert_email`.

> **Importante:** os alarmes CloudWatch **não** controlam o scaling. O scaling é responsabilidade exclusiva da política **Target Tracking** (`aws_autoscaling_policy.cpu_target_tracking` em `ec2.tf`), que opera de forma independente dos alarmes.

| Alarme | Recurso Terraform | Métrica | Threshold | Períodos | Ação |
|--------|------------------|---------|-----------|----------|------|
| cpu-high | `aws_cloudwatch_metric_alarm.cpu_high` | CPUUtilization (ASG) | ≥ 70% | 2 × 60s | SNS |
| ec2-status-check | `aws_cloudwatch_metric_alarm.ec2_status_check` | StatusCheckFailed | ≥ 1 | 1 × 60s | SNS |
| alb-5xx | `aws_cloudwatch_metric_alarm.alb_5xx` | HTTPCode_Target_5XX_Count | ≥ 10 | 1 × 60s | SNS |
| alb-latency | `aws_cloudwatch_metric_alarm.alb_latency` | TargetResponseTime p95 | ≥ 2s | 2 × 60s | SNS |
| alb-unhealthy-hosts | `aws_cloudwatch_metric_alarm.alb_unhealthy_hosts` | UnHealthyHostCount | ≥ 1 | 1 × 60s | SNS |
| alb-no-healthy-hosts | `aws_cloudwatch_metric_alarm.alb_no_healthy_hosts` | HealthyHostCount | ≤ 0 | 1 × 60s | SNS |

**Total: 6 alarmes configurados.**

---

## SNS — Notificações

| Parâmetro | Valor |
|-----------|-------|
| Recurso | `aws_sns_topic.alerts` |
| Nome | `escolatech-tcc-alertas` |
| Protocolo | e-mail |
| Endpoint | `var.alert_email` (configurável) |

> **Ação obrigatória após `terraform apply`:** confirmar a assinatura no e-mail recebido. Sem confirmação, os alertas não serão entregues.

---

## CloudWatch Logs

Os logs são coletados pelo CloudWatch Agent instalado em cada EC2 durante o bootstrap. A configuração está inline no `user_data.sh.tpl` — sem dependência de parâmetro SSM externo.

| Log Group | Recurso Terraform | Fonte | Retenção |
|-----------|------------------|-------|---------|
| `/aws/ec2/escolatech-tcc/nginx-access` | `aws_cloudwatch_log_group.nginx_access` | Nginx access.log | 30 dias |
| `/aws/ec2/escolatech-tcc/nginx-error` | `aws_cloudwatch_log_group.nginx_error` | Nginx error.log | 30 dias |
| `/aws/ec2/escolatech-tcc/bootstrap` | `aws_cloudwatch_log_group.bootstrap` | /var/log/user-data.log | 14 dias |
| `/aws/vpc/escolatech-tcc-flow-logs` | `aws_cloudwatch_log_group.vpc_flow_logs` | VPC Flow Logs | 30 dias |

---

## CloudWatch Dashboard

O dashboard `escolatech-tcc-dashboard` exibe:

| Widget | Métrica | Recursos |
|--------|---------|---------|
| CPU (ASG) | CPUUtilization avg/max | ASG |
| ALB Requisições | RequestCount Sum/min | ALB |
| ALB Latência | TargetResponseTime p50/p95/p99 | ALB |
| ALB Códigos HTTP | 2xx / 4xx / 5xx Sum | ALB |
| ASG Instâncias | GroupInServiceInstances | ASG |
| Hosts Saudáveis | HealthyHostCount / UnHealthyHostCount | Target Group |

**Anotações no dashboard batem com o código:**
- Linha de referência: CPU 70% (Target Tracking)
- ASG: min=2 e max=4

---

## AWS Backup — EBS Snapshots

Implementado em `monitoring.tf` (recurso `aws_backup_plan.ebs_daily`).

| Parâmetro | Valor |
|-----------|-------|
| Frequência | Diária |
| Horário | 05:00 UTC (02:00 BRT) |
| Retenção | 7 dias |
| Seleção | Volumes EBS com tag `ManagedBy=Terraform` |
| Vault | `escolatech-tcc-backup-vault` |
| IAM Role | `escolatech-tcc-backup-role` |

**Escopo:** apenas volumes EBS (sistema operacional + dados do site). Não há banco de dados neste projeto.

**RPO estimado:** até 24h. **RTO estimado:** não foi medido — depende do tempo de criação de nova instância e restauração do snapshot no ambiente da AWS.

---

## Health Check Architecture

```
Route 53 Health Check
  └─ HTTPS GET escolatech.com.br/health (a cada 30s)

CloudFront
  └─ Passa a requisição para o ALB

ALB Target Group Health Check
  └─ HTTP GET /health na EC2 (a cada 30s)
  └─ Espera: HTTP 200
  └─ Threshold saudável: 2 checks consecutivos
  └─ Threshold não-saudável: 3 checks consecutivos

Nginx (EC2)
  └─ location /health { return 200 "healthy\n"; }
  └─ Retorna HTTP 200 real — não é fixed-response do ALB
```

---

## Procedimento de Resposta a Incidentes

### Alarme `alb-no-healthy-hosts` (crítico)

```
Sintoma: site retornando 502/503
Tempo de detecção: ≤ 1 minuto (period=60s, evaluation=1)

1. Console → EC2 → Auto Scaling Groups → Activity → verificar eventos
2. Console → EC2 → Target Groups → ver status de cada instância
3. Console → CloudWatch → Log Groups → nginx-error → buscar erros recentes
4. Console → CloudWatch → Log Groups → bootstrap → verificar falha no user_data
5. Se bootstrap falhou: revisar user_data.sh.tpl e criar nova versão do Launch Template
6. Se Nginx parou: SSM Session Manager → systemctl status nginx → systemctl start nginx
```

### Alarme `alb-5xx`

```
Sintoma: erros 5xx no ALB
1. CloudWatch Logs → nginx-error → identificar causa
2. Verificar se o S3 tem o index.html (aws s3 ls s3://bucket/site/)
3. Verificar se o Nginx está servindo o arquivo correto
```

### Alarme `cpu-high`

```
Sintoma: CPU acima de 70%
1. O Target Tracking já está adicionando instâncias automaticamente
2. Aguardar ~5 minutos para nova instância ficar healthy
3. Verificar CloudWatch → ASG → GroupInServiceInstances (deve aumentar)
4. Se CPU alta em instância específica: investigar via SSM Session Manager
```

---

## Checklist de Monitoramento

Após o `terraform apply`:

- [ ] Confirmar assinatura SNS no e-mail recebido
- [ ] Abrir o dashboard `escolatech-tcc-dashboard` no CloudWatch
- [ ] Verificar que os 6 alarmes estão em estado `OK` ou `INSUFFICIENT_DATA`
- [ ] Verificar que o Target Group tem instâncias `healthy`
- [ ] Verificar que o health check do Route 53 está `Healthy`
- [ ] Confirmar que os Log Groups foram criados e têm log streams das instâncias
- [ ] Verificar no AWS Backup Console que o backup vault foi criado

---

*NexCloud TCC — Monitoramento reflete exatamente o código em `04-terraform/monitoring.tf`*