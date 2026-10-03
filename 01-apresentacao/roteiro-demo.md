# Roteiro de Demonstração — NexCloud TCC

> **Duração estimada:** 10–12 minutos  
> **Ambiente:** Console AWS + Terminal local  
> **Pré-requisito:** `terraform apply` executado com sucesso

---

## Checklist Pré-Demo (executar antes de entrar em sala)

- [ ] `terraform apply` concluído sem erros
- [ ] Assinatura SNS confirmada no e-mail
- [ ] Site acessível via CloudFront domain (output `website_url_cloudfront`)
- [ ] Target Group com pelo menos 2 instâncias `healthy`
- [ ] CloudWatch dashboard aberto em aba separada
- [ ] Console AWS aberto na região `sa-east-1`
- [ ] Terminal aberto na pasta `04-terraform/`
- [ ] `05-website/index.html` aberto localmente como contingência

---

## PARTE 1 — Site Funcionando (2 min)

### Passo 1.1 — Acessar o site

```
Ação: abrir no navegador o output "website_url_cloudfront"
      (ex: https://xxxxx.cloudfront.net)
      Se domínio estiver configurado: https://escolatech.com.br
```

- Mostrar o **HTTPS** na barra do navegador (CloudFront + ACM)
- Rolar a página: hero → cursos → depoimentos → seção AWS → formulário
- Dizer: *"O site está sendo servido via CloudFront com TLS 1.2+. O certificado foi provisionado automaticamente pelo ACM."*

### Passo 1.2 — Headers HTTP

```
Ação: F12 → Network → recarregar → clicar na requisição principal
```

- Mostrar `Server: CloudFront` (ou ausência do header do Nginx — CloudFront oculta)
- Mostrar que a conexão é HTTPS
- Dizer: *"O tráfego do usuário termina no CloudFront. A EC2 não é exposta diretamente."*

---

## PARTE 2 — Console AWS (5 min)

### Passo 2.1 — VPC

```
Console → VPC → Your VPCs
```

- Mostrar `escolatech-tcc-vpc`, CIDR `10.0.0.0/16`
- Ir em **Subnets**: mostrar as 4 subnets (2 públicas, 2 privadas, 2 AZs)
- Dizer: *"As EC2 estão nas subnets privadas — sem IP público. O ALB fica nas subnets públicas."*

### Passo 2.2 — EC2 e Auto Scaling

```
Console → EC2 → Auto Scaling Groups → escolatech-tcc-asg
```

- Mostrar: **min=2 / desired=2 / max=4**
- Aba **Instance management**: 2 instâncias `InService`
- Clicar em uma instância → confirmar que está na **subnet privada**
- Confirmar que não tem **IP público**
- Dizer: *"O ASG mantém pelo menos 2 instâncias, uma em cada AZ. Se uma falhar, o ASG cria uma substituta automaticamente."*

```
Console → EC2 → Auto Scaling Groups → Automatic scaling
```

- Mostrar a política **cpu-target-tracking** (Target Tracking, CPU alvo 70%)
- Dizer: *"Quando a CPU média ultrapassa 70%, o ASG adiciona instâncias. Quando cai, remove — sempre respeitando o mínimo de 2."*

### Passo 2.3 — ALB e Target Group

```
Console → EC2 → Load Balancers → escolatech-tcc-alb
```

- Mostrar: **internet-facing**, 2 AZs ativas
- Aba **Listeners**: HTTP:80 (redirect), HTTPS:443

```
Console → EC2 → Target Groups → escolatech-tcc-tg
```

- Aba **Targets**: mostrar as 2 instâncias com status **healthy**
- Health check: protocolo HTTP, path `/health`, interval 30s
- Dizer: *"O ALB verifica o endpoint /health de cada instância a cada 30 segundos. Uma instância unhealthy é removida do tráfego e o ASG cria uma substituta."*

### Passo 2.4 — CloudFront e WAF

```
Console → CloudFront → Distributions → escolatech-tcc-cloudfront
```

- Mostrar: status **Enabled**, aliases com o domínio
- Origins: ALB (HTTP) e S3 (OAC)
- **Security** tab: WAF associado → `escolatech-tcc-waf`
- Dizer: *"Toda requisição passa pelo WAF antes de chegar ao ALB. O WAF bloqueia SQLi, XSS, IPs maliciosos e rate limiting de 2000 req/5min por IP."*

### Passo 2.5 — S3

```
Console → S3 → escolatech-tcc-assets-<account>
```

- Mostrar: **Block Public Access** ativo em todos os buckets
- Navegar para `site/index.html` — mostrar que o arquivo existe
- Dizer: *"O Terraform fez o upload do index.html para o S3 durante o apply. Cada nova EC2 criada pelo ASG busca esse arquivo automaticamente no bootstrap."*

---

## PARTE 3 — CloudWatch (2 min)

```
Console → CloudWatch → Dashboards → escolatech-tcc-dashboard
```

- Mostrar CPU das EC2 (esperado: baixo, ~5-20% em idle)
- Mostrar ALB Request Count (atividade do acesso feito agora)
- Mostrar Target Group: **2 Healthy, 0 Unhealthy**

```
Console → CloudWatch → Alarms
```

- Mostrar os 6 alarmes em estado **OK** (ou INSUFFICIENT_DATA para alarmes recentes)
- Dizer: *"Se qualquer métrica ultrapassar o threshold, um e-mail é enviado automaticamente. Os alarmes não controlam o scaling — isso é responsabilidade da política Target Tracking."*

---

## PARTE 4 — Terraform (1 min)

```
Ação: terminal → cd 04-terraform
```

```bash
terraform validate
```

- Mostrar: `Success! The configuration is valid.`

```bash
terraform output
```

Saída esperada (valores reais do ambiente):
```
alb_dns_name              = "escolatech-tcc-alb-xxx.sa-east-1.elb.amazonaws.com"
asg_name                  = "escolatech-tcc-asg"
cloudfront_domain_name    = "xxxxx.cloudfront.net"
website_url               = "https://escolatech.com.br"
website_url_cloudfront    = "https://xxxxx.cloudfront.net"
```

- Dizer: *"Toda essa infraestrutura foi criada por Terraform. Um `terraform destroy` remove tudo em minutos, sem custo residual."*

---

## PARTE 5 — Custos (1 min)

```
Ação: abrir 03-custos/estimativa-custos.md
```

- Mostrar a tabela de estimativa: **~$156/mês**
- Destacar os maiores custos: EC2 (~$49) e NAT Gateway (~$39)
- Mencionar o câmbio do dia: *"Com câmbio de R$ X,XX, isso equivale a ~R$ Y/mês"*
- Dizer: *"Para uma demonstração, o custo de 4 horas é inferior a $1. Executamos terraform destroy após a apresentação."*

---

## Plano de Contingência

| Problema | Solução imediata |
|----------|-----------------|
| Site fora do ar | Mostrar `05-website/index.html` localmente |
| Console AWS lento | Usar prints preparados com antecedência |
| `terraform validate` com erro | Mostrar os arquivos .tf no editor — explicar a estrutura |
| Domínio não resolve | Usar URL CloudFront diretamente (output `website_url_cloudfront`) |
| Target Group unhealthy | Mostrar logs de bootstrap no CloudWatch Logs → bootstrap |
| Instâncias em 0 | Verificar se NAT Gateway está ativo; EC2 precisa do NAT para baixar do S3 |

---

## Perguntas Frequentes Esperadas

**P: Por que CloudFront→ALB usa HTTP e não HTTPS?**  
R: O cert ACM cobre o domínio `escolatech.com.br`, não o DNS interno do ALB. Para usar HTTPS nesse trecho, precisaríamos de um subdomínio de origem com cert separado. A segurança é garantida pelo header secreto (`X-CF-Origin-Secret`) validado pelo ALB — sem ele, o ALB retorna 403. O tráfego permanece dentro da rede AWS.

**P: Por que min=2 e não min=1?**  
R: Com min=1, o ASG pode colocar a única instância em uma AZ. Se essa AZ tiver problema, o site fica indisponível. Com min=2, garantimos presença em ambas as AZs continuamente.

**P: O alarme de CPU dispara o scaling?**  
R: Não. O scaling é controlado pela política Target Tracking, que opera de forma independente. O alarme de CPU apenas envia notificação por e-mail via SNS.

**P: Qual o RPO do backup?**  
R: O AWS Backup cria snapshots EBS diariamente às 02h BRT. O RPO é de até 24 horas. Não há banco de dados neste projeto — o site é HTML estático. O RTO não foi medido em laboratório.

**P: Por que não usar Amazon Linux 2?**  
R: O Amazon Linux 2 entrou em fim de suporte padrão. O AL2023 usa `dnf` (sem `amazon-linux-extras`), é mais atual e é a recomendação oficial da AWS para novas workloads.

**P: Como uma nova instância recebe o site?**  
R: O `user_data.sh.tpl` é executado no boot de cada instância. Ele instala o Nginx, busca o `index.html` do S3 (`aws s3 cp`) e inicia o serviço. O Terraform fez o upload do HTML durante o `apply`.

**P: O WAF bloqueia DDoS?**  
R: O WAF protege contra ataques Layer 7 (web). O Shield Standard (gratuito, automático) protege contra DDoS Layer 3 e 4 em CloudFront, ALB e Route 53. Para DDoS Layer 7 avançado, seria necessário o Shield Advanced ($3.000/mês — não implementado neste TCC).

---

*NexCloud TCC — Roteiro baseado na infraestrutura real em `04-terraform/`*