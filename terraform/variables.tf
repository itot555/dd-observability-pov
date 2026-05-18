#==============================================================================
# General
#==============================================================================

variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "name_prefix" {
  description = <<-EOT
    すべてのリソース名・タグの先頭に付与する識別子。
    パートナー様ごとに一意な名前（例: acme-poc）に変更してご利用ください。
    なお EC2 内のログディレクトリやサービス名にも反映されます。
  EOT
  type        = string
  default     = "pov"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix は小文字英数字とハイフンのみ（3-32 文字、先頭は英字、末尾は英数字）で指定してください。"
  }
}

#==============================================================================
# Network
#==============================================================================

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks (2 つ以上必須)"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks (2 つ以上必須 — RDS DB Subnet Group の要件)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "allowed_ip" {
  description = <<-EOT
    SSH (22) および Spring Boot (8080) へのインバウンドを許可する送信元 CIDR 一覧。
    デフォルトは 0.0.0.0/0（全公開）ですが、環境に応じて IP を絞ってください。
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

#==============================================================================
# EC2
#==============================================================================

variable "java_ec2_instance_type" {
  description = "EC2 instance type for Java/Spring Boot server"
  type        = string
  default     = "t3.medium"
}

variable "python_ec2_instance_type" {
  description = "EC2 instance type for Python server"
  type        = string
  default     = "t3.small"
}

variable "java_ec2_volume_size" {
  description = "Root volume size in GB for Java EC2"
  type        = number
  default     = 30
}

variable "python_ec2_volume_size" {
  description = "Root volume size in GB for Python EC2"
  type        = number
  default     = 20
}

#==============================================================================
# RDS PostgreSQL
#==============================================================================

variable "db_instance_class" {
  description = "RDS instance class (Graviton t4g.micro for minimum cost)"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_engine_version" {
  description = "PostgreSQL engine version on RDS (latest available 17.x minor)"
  type        = string
  default     = "17.10"
}

variable "db_allocated_storage" {
  description = "Allocated storage in GB for RDS (gp3, minimum 20)"
  type        = number
  default     = 20
}
