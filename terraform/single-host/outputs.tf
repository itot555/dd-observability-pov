#------------------------------------------------------------------------------
# App EC2 (single-host: Java + Python)
#------------------------------------------------------------------------------

output "ec2_instance_id" {
  description = "App EC2 instance ID"
  value       = aws_instance.app.id
}

output "ec2_public_ip" {
  description = "App EC2 public IP address"
  value       = aws_instance.app.public_ip
}

output "ec2_ssh_command" {
  description = "SSH command to connect to the App EC2"
  value       = "ssh -i keys/${local.name_prefix}-ssh-key ec2-user@${aws_instance.app.public_ip}"
}

output "ec2_spring_boot_url" {
  description = "URL to access the Spring Boot application"
  value       = "http://${aws_instance.app.public_ip}:8080"
}

#------------------------------------------------------------------------------
# RDS PostgreSQL
#------------------------------------------------------------------------------

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint (hostname)"
  value       = aws_db_instance.postgres.address
}

output "rds_port" {
  description = "RDS PostgreSQL port"
  value       = aws_db_instance.postgres.port
}

output "rds_db_name" {
  description = "RDS PostgreSQL initial database name"
  value       = aws_db_instance.postgres.db_name
}

output "rds_username" {
  description = "RDS PostgreSQL master username"
  value       = aws_db_instance.postgres.username
}

#------------------------------------------------------------------------------
# Demo Instructions (設定手順)
#------------------------------------------------------------------------------

output "demo_step1_before" {
  description = "Step 1: Start apps in Before state (no Datadog)"
  value       = <<-EOT

    ===== STEP 1: Before 状態（Datadog なし）=====

    ## SSH 接続
    ssh -i keys/${local.name_prefix}-ssh-key ec2-user@${aws_instance.app.public_ip}

    ## [EC2 内] Java アプリビルド＆起動
    sudo mkdir -p /var/log/${local.name_prefix}
    sudo chown ec2-user:ec2-user /var/log/${local.name_prefix}
    cd ~/apps/java-app
    ./mvnw -q package -DskipTests
    PYTHON_API_URL=http://localhost:8000 \
    LOGGING_FILE_NAME=/var/log/${local.name_prefix}/java-app.log \
    nohup java -jar target/*.jar > /var/log/${local.name_prefix}/java-app.log 2>&1 &

    ## [EC2 内] Python アプリ起動
    cd ~/apps/python-app
    python3 -m venv venv 2>/dev/null || true
    source venv/bin/activate
    pip install -q -r requirements.txt
    set -a; source /home/ec2-user/.env; set +a
    LOG_DIR=/var/log/${local.name_prefix} \
    nohup python3 app.py > /var/log/${local.name_prefix}/python-app.log 2>&1 &

  EOT
}

output "demo_step2_install_agent" {
  description = "Step 2: Install Datadog Agent with SSI on the App EC2"
  value       = <<-EOT

    ===== STEP 2: Datadog Agent インストール（SSI）=====
    DD_API_KEY: Datadog UI > Organization Settings > API Keys からコピー

    ## [EC2 内] Java + Python の SSI を同時に有効化
    export DD_API_KEY="<DD_API_KEY>"
    export DD_SITE="datadoghq.com"
    export DD_ENV="${local.name_prefix}"
    export DD_APM_INSTRUMENTATION_ENABLED=host
    export DD_APM_INSTRUMENTATION_LIBRARIES="java:1,python:3"
    bash -c "$(curl -L https://install.datadoghq.com/scripts/install_script_agent7.sh)"

  EOT
}

output "demo_step3_configure_logs" {
  description = "Step 3: Configure log collection on the App EC2"
  value       = <<-EOT

    ===== STEP 3: ログ収集設定 =====

    ## [EC2 内] logs_enabled 有効化 + Java / Python ログ収集設定
    sudo sed -i 's/^# *logs_enabled:.*$/logs_enabled: true/' /etc/datadog-agent/datadog.yaml

    sudo mkdir -p /etc/datadog-agent/conf.d/java.d
    sudo chown dd-agent:dd-agent /etc/datadog-agent/conf.d/java.d
    sudo tee /etc/datadog-agent/conf.d/java.d/conf.yaml > /dev/null << 'EOF'
logs:
  - type: file
    path: /var/log/${local.name_prefix}/java-app.log
    service: ${local.name_prefix}-java-front
    source: java
    sourcecategory: sourcecode
EOF
    sudo chown dd-agent:dd-agent /etc/datadog-agent/conf.d/java.d/conf.yaml

    sudo mkdir -p /etc/datadog-agent/conf.d/python.d
    sudo chown dd-agent:dd-agent /etc/datadog-agent/conf.d/python.d
    sudo tee /etc/datadog-agent/conf.d/python.d/conf.yaml > /dev/null << 'EOF'
logs:
  - type: file
    path: /var/log/${local.name_prefix}/python-app.log
    service: ${local.name_prefix}-py-back
    source: python
    sourcecategory: sourcecode
EOF
    sudo chown dd-agent:dd-agent /etc/datadog-agent/conf.d/python.d/conf.yaml

    sudo systemctl restart datadog-agent

  EOT
}

output "demo_step4_after" {
  description = "Step 4: Restart apps in After state (APM auto-instrumented via SSI)"
  value       = <<-EOT

    ===== STEP 4: After 状態（APM 計装済み）=====

    ## [EC2 内] Java アプリ再起動（SSI が JAVA_TOOL_OPTIONS 経由で -javaagent を自動注入）
    pkill -f 'java.*jar' || true
    sleep 2
    cd ~/apps/java-app
    PYTHON_API_URL=http://localhost:8000 \
    LOGGING_FILE_NAME=/var/log/${local.name_prefix}/java-app.log \
    DD_SERVICE=${local.name_prefix}-java-front DD_ENV=${local.name_prefix} DD_LOGS_INJECTION=true \
    nohup java -jar target/*.jar > /var/log/${local.name_prefix}/java-app.log 2>&1 &

    ## [EC2 内] Python アプリ再起動（venv 利用のため ddtrace-run 経由で計装）
    pkill -f 'python3 app.py' || true
    sleep 2
    cd ~/apps/python-app
    source venv/bin/activate
    set -a; source /home/ec2-user/.env; set +a
    LOG_DIR=/var/log/${local.name_prefix} \
    DD_SERVICE=${local.name_prefix}-py-back DD_ENV=${local.name_prefix} DD_LOGS_INJECTION=true \
    nohup ddtrace-run python3 app.py \
      > /var/log/${local.name_prefix}/python-app.log 2>&1 &

  EOT
}
