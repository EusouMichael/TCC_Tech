# Estimativa de Custos — NexCloud TCC

> **Projeto:** Escola Tech na AWS  
> **Região:** sa-east-1 (São Paulo)  
> **Caráter:** Estimativa de referência — não representa fatura real  
> **Câmbio:** Não fixado. Usar cotação do dia da apresentação.  
> **Ferramenta de referência:** [AWS Pricing Calculator](https://calculator.aws/pricing/2/calculator)

---

## Premissas da Estimativa

| Premissa | Valor adotado | Observação |
|----------|--------------|------------|
| Horas/mês | 720h | 30 dias × 24h — ambiente ativo 24/7 |
| EC2 pricing | On-Demand | Sem Reserved Instances ou Savings Plans |
| ASG desired | 2 instâncias | Conforme `variables.tf` |
| NAT Gateways | 2 (1 por AZ) | Configuração padrão `single_nat_gateway = false` |
| Tráfego NAT | ~100 GB/mês | Estimativa conservadora para updates e APIs AWS |
| CloudFront transfer | ~50 GB/mês | Estimativa para site com tráfego moderado |
| CloudFront requests | ~1.000.000/mês | Estimativa |
| S3 armazenamento | ~5 GB total | Assets + logs (início de operação) |
| CloudWatch Logs | ~3 GB/mês | Nginx access + error + bootstrap |
| EBS Snapshots | 2 vol × 20 GB | Backup diário, armazenamento estimado |
| t3.small CPU | Normal | Sem surplus credits na estimativa |

> **Atenção t3 (burstable):** Instâncias t3.small têm baseline de CPU de 20%. Se a CPU ficar acima do baseline por período prolongado, pode gerar cobrança adicional de surplus credits (~$0,05/vCPU-hora). Monitorar o alarme `cpu_high` do CloudWatch.

---

## Estimativa Mensal por Serviço

| # | Serviço | Cálculo | Estimativa/mês |
|---|---------|---------|----------------|
| 1 | EC2 t3.small × 2 | 2 × 720h × $0,034/h | **$48,96** |
| 2 | NAT Gateway × 2 (fixo) | 2 × 720h × $0,059/h | **$32,86** |
| 3 | NAT Gateway × 2 (dados) | ~100 GB × $0,059/GB | **~$5,90** |
| 4 | ALB (fixo) | 720h × $0,0225/h | **$16,43** |
| 5 | ALB (LCUs) | ~2 LCU × $0,008/h × 720h | **~$6,00** |
| 6 | EBS gp3 20 GB × 2 | 2 × 20 GB × $0,10/GB | **$4,00** |
| 7 | CloudFront (transfer) | ~50 GB × $0,085/GB | **~$4,25** |
| 8 | CloudFront (requests) | ~1M × $0,009/10k | **~$0,90** |
| 9 | WAF Web ACL | 1 ACL × $5,00 | **$5,00** |
| 10 | WAF Managed Rules | 5 grupos × $1,00 | **$5,00** |
| 11 | WAF Requests | ~1M × $0,60/1M | **~$0,60** |
| 12 | Route 53 Hosted Zone | 1 zona | **$0,50** |
| 13 | Route 53 Health Check | 1 check (latency) | **$0,50** |
| 14 | S3 (storage) | ~5 GB × $0,023/GB | **~$0,12** |
| 15 | CloudWatch Alarmes | 5 alarmes × $0,10 | **$0,50** |
| 16 | CloudWatch Dashboard | 1 dashboard | **$3,00** |
| 17 | CloudWatch Logs | ~3 GB × $0,50/GB | **~$1,50** |
| 18 | AWS Backup (EBS snapshots) | ~2 vol × 20 GB × $0,05 | **~$1,00** |
| 19 | ACM Certificados | 2 certs para serviços AWS | **$0,00** |
| 20 | Shield Standard | Proteção DDoS L3/L4 | **$0,00** |
| | **TOTAL ESTIMADO** | | **~$156/mês** |

> Itens marcados com `~` são **variáveis** — dependem de tráfego real, volume de dados e padrão de uso.

---

## Conversão para BRL

O câmbio USD/BRL varia diariamente. **Não usar valor fixo como fato.**

Exemplos de referência para contextualizar na apresentação:

| Câmbio (hipotético) | Total mensal estimado |
|--------------------|----------------------|
| R$ 5,00/USD | ~R$ 780/mês |
| R$ 5,50/USD | ~R$ 858/mês |
| R$ 6,00/USD | ~R$ 936/mês |

> Usar o câmbio do dia da apresentação e declarar explicitamente: *"estimativa com câmbio de R$ X,XX/USD em DD/MM/AAAA".*

---

## Breakdown por Categoria

| Categoria | Estimativa/mês | % do total |
|-----------|---------------|-----------|
| Rede (NAT Gateway) | ~$38,76 | ~25% |
| Computação (EC2) | ~$48,96 | ~31% |
| Balanceamento (ALB) | ~$22,43 | ~14% |
| Segurança (WAF) | ~$10,60 | ~7% |
| CDN (CloudFront) | ~$5,15 | ~3% |
| Armazenamento (EBS + S3) | ~$4,12 | ~3% |
| Monitoramento (CW + Backup) | ~$6,00 | ~4% |
| DNS (Route 53) | ~$1,00 | ~1% |
| Gratuitos (ACM + Shield) | $0,00 | 0% |
| **Total** | **~$156** | 100% |

> NAT Gateway é o maior custo individual (~25%). Alternativa para reduzir: `single_nat_gateway = true` economiza ~$16/mês mas elimina redundância de NAT por AZ.

---

## Oportunidades de Otimização (não implementadas nesta versão)

| Otimização | Economia estimada | Trade-off |
|------------|------------------|-----------|
| EC2 Reserved Instances (1 ano) | ~$20/mês | Compromisso de 1 ano |
| EC2 Savings Plans (1 ano) | ~$19/mês | Compromisso de 1 ano |
| Single NAT Gateway | ~$16/mês | Perde HA no NAT por AZ |
| VPC Endpoints para S3/SSM | ~$5/mês | Elimina parte do tráfego NAT |
| CloudFront PriceClass_100 | Pequena | Menos edge locations |

---

## Serviços Gratuitos Utilizados

| Serviço | Por que é gratuito |
|---------|-------------------|
| ACM (SSL/TLS) | Certificados provisionados para serviços AWS são gratuitos |
| Shield Standard | Incluído automaticamente em CloudFront, ALB e Route 53 |
| SSM Session Manager | Gratuito para EC2 gerenciadas pelo SSM |
| VPC, Internet Gateway | Sem custo de provisionamento |
| EC2 Detailed Monitoring | Incluso no monitoramento da instância |

---

## Comparativo com On-Premises

> **Aviso:** Não há dados reais de custo on-premises fornecidos pelo case. O comparativo abaixo é um **cenário hipotético ilustrativo** para fins didáticos. Não deve ser apresentado como economia comprovada.

**Cenário hipotético:** Servidor dedicado local com link de internet, energia, rack e suporte técnico.

| Item | Hipotético On-Premises | AWS (estimativa) |
|------|----------------------|-----------------|
| Hardware/depreciação | ~R$ 1.200/mês | — |
| Link internet | ~R$ 800/mês | Incluso no NAT/CF |
| Energia + rack | ~R$ 400/mês | — |
| Suporte TI | ~R$ 400/mês | — |
| **Total hipotético** | **~R$ 2.800/mês** | **~R$ 858/mês** |

> Este comparativo assume câmbio de R$ 5,50 e premissas **não verificadas** para o cenário on-premises. Apresentar como *"estimativa hipotética para contextualizar o valor da nuvem"*, não como dado real do case.

---

## Custo de Demonstração (TCC)

Para uma demonstração pontual de 4 horas:

| Estimativa | Cálculo |
|------------|---------|
| Custo por hora | ~$156 ÷ 720h ≈ $0,22/hora |
| 4 horas de demo | ~$0,88 |
| Margem de segurança | ~$5,00 |

> Executar `terraform destroy` imediatamente após a apresentação para evitar custos contínuos.

---

*Estimativa elaborada pela equipe NexCloud — valores devem ser validados no [AWS Pricing Calculator](https://calculator.aws/pricing/2/calculator) antes da apresentação.*