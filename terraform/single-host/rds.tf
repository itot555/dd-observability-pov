#------------------------------------------------------------------------------
# RDS PostgreSQL
#
# Apply/Destroy easiness — designed for frequent recreation:
#   - skip_final_snapshot / deletion_protection=false / backup_retention_period=0
#   - delete_automated_backups=true
#   - Performance Insights / Enhanced Monitoring / CloudWatch Logs export 全無効
#   - parameter_group は作らず RDS デフォルトを使用（依存を減らす）
#
# Credentials は Secrets Manager を使わず、Terraform から SSH 経由で
# App EC2 の /home/ec2-user/.env に直接書き込む（null_resource.deploy_env）。
#------------------------------------------------------------------------------

resource "random_password" "db" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>?"
}

resource "aws_db_subnet_group" "postgres" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-db-subnet-group"
  })
}

resource "aws_db_instance" "postgres" {
  identifier     = "${local.name_prefix}-postgres"
  engine         = "postgres"
  engine_version = var.db_engine_version

  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "appdb"
  username = "postgres"
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false

  skip_final_snapshot      = true
  deletion_protection      = false
  backup_retention_period  = 0
  delete_automated_backups = true
  copy_tags_to_snapshot    = false
  apply_immediately        = true

  performance_insights_enabled    = false
  monitoring_interval             = 0
  enabled_cloudwatch_logs_exports = []
  auto_minor_version_upgrade      = false

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-postgres"
  })
}

#------------------------------------------------------------------------------
# Deploy /home/ec2-user/.env to App EC2 via remote-exec (direct SSH)
#------------------------------------------------------------------------------

resource "null_resource" "deploy_env" {
  triggers = {
    db_endpoint = aws_db_instance.postgres.address
    db_password = random_password.db.result
    instance_id = aws_instance.app.id
  }

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = tls_private_key.ec2.private_key_pem
    host        = aws_instance.app.public_ip
    timeout     = "10m"
  }

  # Values are single-quoted so that bash `source` does not interpret
  # shell metacharacters ($, <, >, *, etc.) inside the random password.
  # random_password.override_special excludes "'" so values never contain
  # an apostrophe that would terminate the quoted string.
  provisioner "remote-exec" {
    inline = [
      "umask 077",
      "cat > /home/ec2-user/.env <<'EOF'",
      "DB_HOST='${aws_db_instance.postgres.address}'",
      "DB_PORT='${aws_db_instance.postgres.port}'",
      "DB_NAME='${aws_db_instance.postgres.db_name}'",
      "DB_USER='${aws_db_instance.postgres.username}'",
      "DB_PASSWORD='${random_password.db.result}'",
      "EOF",
      "chmod 600 /home/ec2-user/.env",
    ]
  }

  depends_on = [
    null_resource.upload_apps,
  ]
}
