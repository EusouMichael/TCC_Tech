#!/bin/bash
# =============================================================================
# user_data.sh.tpl — Bootstrap Escola Tech
# SO: Amazon Linux 2023 (AL2023)
# Equipe: NexCloud
#
# Este script é executado automaticamente no primeiro boot de cada instância
# criada pelo Auto Scaling Group. Toda nova EC2 receberá o site atualizado
# diretamente do S3, garantindo que o ASG possa substituir instâncias sem
# intervenção manual.
#
# Variáveis injetadas pelo Terraform via templatefile():
#   aws_region    — região da instância (ex: sa-east-1)
#   assets_bucket — nome do bucket S3 com o site
#   project_name  — nome do projeto
#   environment   — ambiente (tcc, production, etc.)
#   log_group_prefix — prefixo dos Log Groups do CloudWatch
# =============================================================================

set -o errexit
set -o nounset
set -o pipefail

LOG=/var/log/user-data.log
exec > >(tee -a "$LOG") 2>&1

echo "=== Bootstrap iniciado: $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
echo "=== Projeto: ${project_name} | Ambiente: ${environment} ==="
echo "=== Região: ${aws_region} | Bucket: ${assets_bucket} ==="

# ─── 1. Atualizar pacotes ─────────────────────────────────────────────────────
echo "--- Atualizando pacotes ---"
dnf update -y --quiet

# ─── 2. Instalar Nginx ────────────────────────────────────────────────────────
# AL2023 usa dnf. O pacote nginx está disponível diretamente no repositório.
echo "--- Instalando Nginx ---"
dnf install -y nginx

# ─── 3. Instalar CloudWatch Agent ────────────────────────────────────────────
echo "--- Instalando CloudWatch Agent ---"
dnf install -y amazon-cloudwatch-agent nodejs22 nodejs22-npm

# ─── 4. Criar estrutura de diretórios ────────────────────────────────────────
echo "--- Criando diretórios ---"
mkdir -p /var/www/html
mkdir -p /var/www/html/static
chown -R nginx:nginx /var/www/html

# ─── 5. Configurar Nginx ──────────────────────────────────────────────────────
echo "--- Configurando Nginx ---"
cat > /etc/nginx/conf.d/escolatech.conf << 'NGINX_CONF'
server {
    listen 80;
    server_name _;
    root /var/www/html;
    index index.html;

    # Endpoint de health check para o ALB Target Group.
    # Retorna HTTP 200 com corpo "healthy" se o Nginx estiver respondendo.
    location /health {
        access_log  off;
        return 200  "healthy\n";
        add_header  Content-Type text/plain;
    }

    # Assets estáticos com cache longo
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|otf)$ {
        expires     7d;
        add_header  Cache-Control "public, no-transform";
        try_files   $uri =404;
    }

    # API de cadastro — encaminhada para Node.js local
    location /api/ {
        proxy_pass http://127.0.0.1:3000/api/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 5s;
        proxy_read_timeout 30s;
    }

    # Conteúdo principal — serve index.html para qualquer rota não encontrada
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Headers de segurança
    add_header X-Frame-Options          "SAMEORIGIN"                  always;
    add_header X-Content-Type-Options   "nosniff"                     always;
    add_header Referrer-Policy          "no-referrer-when-downgrade"  always;
    # HSTS: ativado pois o tráfego HTTP é redirecionado para HTTPS no ALB
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # Ocultar versão do Nginx
    server_tokens off;
}
NGINX_CONF

# Remover configuração padrão para evitar conflito
rm -f /etc/nginx/conf.d/default.conf

# Validar configuração antes de prosseguir
nginx -t

# ─── 6. Buscar o site do S3 ───────────────────────────────────────────────────
# O index.html é armazenado no S3 e copiado para cada nova instância no boot.
# Isso garante que o ASG crie instâncias com o site atualizado sem intervenção.
echo "--- Buscando site do S3 ---"

S3_BUCKET="${assets_bucket}"
S3_KEY="site/index.html"
DEST="/var/www/html/index.html"

# Tentar buscar o index.html do S3 com retry
MAX_ATTEMPTS=3
ATTEMPT=1
while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    echo "--- Tentativa $ATTEMPT/$MAX_ATTEMPTS de download do S3 ---"
    if aws s3 cp "s3://$S3_BUCKET/$S3_KEY" "$DEST" --region "${aws_region}" 2>>/var/log/user-data.log; then
        echo "--- index.html obtido do S3 com sucesso ---"
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    sleep 5
done

# Se o download falhar, servir página de fallback para não deixar o site vazio
if [ ! -f "$DEST" ]; then
    echo "--- AVISO: falha ao obter index.html do S3, usando fallback ---"
    cat > "$DEST" << 'FALLBACK'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Escola Tech</title>
  <style>
    body { font-family: sans-serif; text-align: center; padding: 60px;
           background: #0d1b2a; color: #e0e6f0; }
    h1   { color: #4db8ff; }
  </style>
</head>
<body>
  <h1>🎓 Escola Tech</h1>
  <p>Infraestrutura provisionada via Terraform + AWS.</p>
  <p>Site em carregamento — aguarde alguns instantes.</p>
</body>
</html>
FALLBACK
fi

chown nginx:nginx "$DEST"

# ─── 6.5 Baixar CA oficial do Amazon RDS ──────────────────────────────────────
echo "--- Instalando CA oficial do RDS ---"
mkdir -p /etc/pki/rds
curl -fsSL https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem \
  -o /etc/pki/rds/global-bundle.pem
chmod 644 /etc/pki/rds/global-bundle.pem

# ─── 7. Instalar e configurar API de cadastro ─────────────────────────────────
echo "--- Instalando API Escola Tech ---"
mkdir -p /opt/escolatech-api
touch /var/log/escolatech-api.log
chown ec2-user:ec2-user /var/log/escolatech-api.log
aws s3 cp "s3://${assets_bucket}/api/package.json" /opt/escolatech-api/package.json --region "${aws_region}"
aws s3 cp "s3://${assets_bucket}/api/server.js" /opt/escolatech-api/server.js --region "${aws_region}"

cd /opt/escolatech-api
npm install --omit=dev --no-audit --no-fund

echo "--- Obtendo credenciais do RDS via Secrets Manager ---"
SECRET_ARN=$(aws rds describe-db-instances   --db-instance-identifier "${project_name}-${environment}-postgres"   --region "${aws_region}"   --query 'DBInstances[0].MasterUserSecret.SecretArn'   --output text)

cat > /etc/escolatech-api.env << ENV
AWS_REGION=${aws_region}
DB_HOST=${aws_rds_host}
DB_PORT=5432
DB_NAME=${db_name}
DB_APP_USERNAME=${db_app_username}
DB_SECRET_ARN=${SECRET_ARN}
ENVIRONMENT=${environment}
ENV

chmod 600 /etc/escolatech-api.env

cat > /etc/systemd/system/escolatech-api.service << 'SYSTEMD'
[Unit]
Description=Escola Tech Enrollment API
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/escolatech-api
EnvironmentFile=/etc/escolatech-api.env
ExecStart=/usr/bin/node /opt/escolatech-api/server.js
Restart=always
RestartSec=5
User=ec2-user
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/escolatech-api /var/log/escolatech-api.log
StandardOutput=append:/var/log/escolatech-api.log
StandardError=append:/var/log/escolatech-api.log

[Install]
WantedBy=multi-user.target
SYSTEMD

chown -R ec2-user:ec2-user /opt/escolatech-api
systemctl daemon-reload
systemctl enable escolatech-api
systemctl start escolatech-api

# ─── 7. Configurar CloudWatch Agent ───────────────────────────────────────────
# Configuração inline — sem dependência de parâmetro SSM externo
echo "--- Configurando CloudWatch Agent ---"
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CW_CONF'
{
  "agent": {
    "run_as_user": "root"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/nginx/access.log",
            "log_group_name": "${log_group_prefix}/nginx-access",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 30
          },
          {
            "file_path": "/var/log/nginx/error.log",
            "log_group_name": "${log_group_prefix}/nginx-error",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 30
          },
          {
            "file_path": "/var/log/escolatech-api.log",
            "log_group_name": "${log_group_prefix}/api",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 14
          },
          {
            "file_path": "/var/log/user-data.log",
            "log_group_name": "${log_group_prefix}/bootstrap",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 14
          }
        ]
      }
    }
  }
}
CW_CONF

# ─── 8. Iniciar e habilitar serviços ──────────────────────────────────────────
echo "--- Habilitando e iniciando Nginx ---"
systemctl enable nginx
systemctl start  nginx

echo "--- Habilitando e iniciando CloudWatch Agent ---"
systemctl enable amazon-cloudwatch-agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -s \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# ─── 9. Validar health check ──────────────────────────────────────────────────
echo "--- Validando endpoint /health ---"
sleep 2
HTTP_CODE=$(curl -s -o /dev/null -w "%%{http_code}" http://localhost/health)
if [ "$HTTP_CODE" = "200" ]; then
    echo "--- /health retornou 200 — OK ---"
else
    echo "--- AVISO: /health retornou $HTTP_CODE ---"
fi

# ─── 10. Identificar instância via tag ────────────────────────────────────────
echo "--- Tagueando instância ---"
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
    -H "X-aws-ec2-metadata-token: $(curl -s -X PUT \
        -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600' \
        http://169.254.169.254/latest/api/token)" \
    http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")

if [ "$INSTANCE_ID" != "unknown" ] && [ -n "$INSTANCE_ID" ]; then
    aws ec2 create-tags \
        --region "${aws_region}" \
        --resources "$INSTANCE_ID" \
        --tags "Key=Name,Value=${project_name}-${environment}-$INSTANCE_ID" \
        2>>/var/log/user-data.log || true
fi

echo "=== Bootstrap concluído: $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="