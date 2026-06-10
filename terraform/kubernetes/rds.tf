#------------------------------------------------------------------------------
# RDS PostgreSQL
#
# single-host と同様の設計方針:
#   - skip_final_snapshot / deletion_protection=false / backup_retention_period=0
#   - Performance Insights / Enhanced Monitoring 無効（POV 用途でコスト最小化）
#   - DB 接続情報は terraform output コマンドで取得し kubectl create secret で投入
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
