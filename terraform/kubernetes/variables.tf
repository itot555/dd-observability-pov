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
    すべてのリソース名・タグ・Datadog service/env の先頭に付与する識別子。
    パートナー様ごとに一意な名前（例: acme-poc）に変更してご利用ください。
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
  description = "Private subnet CIDR blocks (2 つ以上必須 — RDS DB Subnet Group と EKS ノード用)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "allowed_ip" {
  description = <<-EOT
    EKS API サーバーのパブリックエンドポイントへのアクセスを許可する送信元 CIDR 一覧。
    デフォルトは 0.0.0.0/0（全公開）ですが、環境に応じて IP を絞ってください。
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

#==============================================================================
# EKS
#==============================================================================

variable "eks_cluster_version" {
  description = "EKS Kubernetes version (SCP 要件: 1.33 以上 / Standard Support のみ許可)"
  type        = string
  default     = "1.33"
}

variable "node_instance_type" {
  description = "EKS worker node instance type (Java + Python + Datadog Agent が同居するため t3.medium 以上を推奨)"
  type        = string
  default     = "t3.medium"
}

variable "node_volume_size" {
  description = "EKS worker node root volume size in GB"
  type        = number
  default     = 30
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 3
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
  description = "PostgreSQL engine version on RDS"
  type        = string
  default     = "17.10"
}

variable "db_allocated_storage" {
  description = "Allocated storage in GB for RDS (gp3, minimum 20)"
  type        = number
  default     = 20
}
