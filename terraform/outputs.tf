#------------------------------------------------------------------------------
# Bastion EC2 (Java / Public Subnet)
#------------------------------------------------------------------------------

output "java_ec2_instance_id" {
  description = "Java front-end EC2 instance ID"
  value       = aws_instance.java.id
}

output "java_ec2_public_ip" {
  description = "Java front-end EC2 public IP address"
  value       = aws_instance.java.public_ip
}

output "java_ec2_ssh_command" {
  description = "SSH command to connect to the Java front-end EC2"
  value       = "ssh -i keys/${local.name_prefix}-ssh-key ubuntu@${aws_instance.java.public_ip}"
}

output "java_ec2_spring_boot_url" {
  description = "URL to access the Spring Boot application"
  value       = "http://${aws_instance.java.public_ip}:8080"
}

#------------------------------------------------------------------------------
# Python EC2 (Private Subnet)
#------------------------------------------------------------------------------

output "python_ec2_instance_id" {
  description = "Python back-end EC2 instance ID"
  value       = aws_instance.python.id
}

output "python_ec2_private_ip" {
  description = "Python back-end EC2 private IP address"
  value       = aws_instance.python.private_ip
}

output "python_ec2_ssh_command" {
  description = "SSH command to connect to the Python back-end EC2 via the bastion EC2 as a jump host"
  value       = "ssh -i keys/${local.name_prefix}-ssh-key -J ubuntu@${aws_instance.java.public_ip} ubuntu@${aws_instance.python.private_ip}"
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

    ## [${local.name_prefix}-bastion] SSH 接続
    ssh -i keys/${local.name_prefix}-ssh-key ubuntu@${aws_instance.java.public_ip}

    ## [${local.name_prefix}-bastion] アプリビルド＆起動
    sudo mkdir -p /var/log/${local.name_prefix}
    sudo chown ubuntu:ubuntu /var/log/${local.name_prefix}
    cd ~/apps/java-app
    ./mvnw -q package -DskipTests
    PYTHON_API_URL=http://${aws_instance.python.private_ip}:8000 \
    LOGGING_FILE_NAME=/var/log/${local.name_prefix}/java-app.log \
    nohup java -jar target/*.jar > /var/log/${local.name_prefix}/java-app.log 2>&1 &

    ---

    ## [${local.name_prefix}-py] SSH 接続（${local.name_prefix}-bastion 経由）
    ssh -i keys/${local.name_prefix}-ssh-key -J ubuntu@${aws_instance.java.public_ip} ubuntu@${aws_instance.python.private_ip}

    ## [${local.name_prefix}-py] アプリ起動
    sudo mkdir -p /var/log/${local.name_prefix}
    sudo chown ubuntu:ubuntu /var/log/${local.name_prefix}
    cd ~/apps/python-app
    python3 -m venv venv 2>/dev/null || true
    source venv/bin/activate
    pip install -q -r requirements.txt
    set -a; source /home/ubuntu/.env; set +a
    LOG_DIR=/var/log/${local.name_prefix} \
    nohup python3 app.py > /var/log/${local.name_prefix}/python-app.log 2>&1 &

  EOT
}

output "demo_step2_install_agent" {
  description = "Step 2: Install Datadog Agent with SSI on both EC2 instances"
  value       = <<-EOT

    ===== STEP 2: Datadog Agent インストール（SSI）=====
    DD_API_KEY: Datadog UI > Organization Settings > API Keys からコピー

    ## [${local.name_prefix}-bastion] EC2 内で実行
    export DD_API_KEY="<DD_API_KEY>"
    export DD_SITE="datadoghq.com"
    export DD_ENV="${local.name_prefix}"
    export DD_APM_INSTRUMENTATION_ENABLED=host
    export DD_APM_INSTRUMENTATION_LIBRARIES=java:1
    bash -c "$(curl -L https://install.datadoghq.com/scripts/install_script_agent7.sh)"

    ---

    ## [${local.name_prefix}-py] EC2 内で実行
    export DD_API_KEY="<DD_API_KEY>"
    export DD_SITE="datadoghq.com"
    export DD_ENV="${local.name_prefix}"
    export DD_APM_INSTRUMENTATION_ENABLED=host
    export DD_APM_INSTRUMENTATION_LIBRARIES=python:3
    bash -c "$(curl -L https://install.datadoghq.com/scripts/install_script_agent7.sh)"

  EOT
}

output "demo_step3_configure_logs" {
  description = "Step 3: Configure log collection on both EC2 instances"
  value       = <<-EOT

    ===== STEP 3: ログ収集設定 =====

    ## [${local.name_prefix}-bastion] EC2 内で実行
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
    sudo systemctl restart datadog-agent

    ---

    ## [${local.name_prefix}-py] EC2 内で実行
    sudo sed -i 's/^# *logs_enabled:.*$/logs_enabled: true/' /etc/datadog-agent/datadog.yaml
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

    ## [${local.name_prefix}-bastion] EC2 内で実行
    # SSI が JAVA_TOOL_OPTIONS 経由で -javaagent を自動注入する
    pkill -f 'java.*jar' || true
    sleep 2
    cd ~/apps/java-app
    PYTHON_API_URL=http://${aws_instance.python.private_ip}:8000 \
    LOGGING_FILE_NAME=/var/log/${local.name_prefix}/java-app.log \
    DD_SERVICE=${local.name_prefix}-java-front DD_ENV=${local.name_prefix} DD_LOGS_INJECTION=true \
    nohup java -jar target/*.jar > /var/log/${local.name_prefix}/java-app.log 2>&1 &

    ---

    ## [${local.name_prefix}-py] EC2 内で実行
    # venv 利用のため ddtrace-run 経由で計装する
    pkill -f 'python3 app.py' || true
    sleep 2
    cd ~/apps/python-app
    source venv/bin/activate
    set -a; source /home/ubuntu/.env; set +a
    LOG_DIR=/var/log/${local.name_prefix} \
    DD_SERVICE=${local.name_prefix}-py-back DD_ENV=${local.name_prefix} DD_LOGS_INJECTION=true \
    nohup ddtrace-run python3 app.py \
      > /var/log/${local.name_prefix}/python-app.log 2>&1 &

  EOT
}
