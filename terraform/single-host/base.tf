#==============================================================================
# base.tf
#
# single-host 構成の「土台」リソースをまとめたファイルです。
# EC2 を Public Subnet に 1 台配置するシンプル構成のため NAT Gateway は不要です。
# Private Subnet は RDS DB Subnet Group の要件（2 AZ 必須）を満たすためだけに存在し、
# インターネットへのルートは持ちません。
#
# このファイルに含まれるリソース
#   - VPC / 2x Public Subnet / 2x Private Subnet（RDS 専用）
#   - Internet Gateway
#   - Route Table（Public のみ）
#   - app SG（SSH 22 + Spring Boot 8080）
#   - IAM Role / Instance Profile（SSM Session Manager 対応）
#==============================================================================

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

#------------------------------------------------------------------------------
# VPC
#------------------------------------------------------------------------------

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

#------------------------------------------------------------------------------
# Subnets
#------------------------------------------------------------------------------

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-${local.azs[count.index]}"
  })
}

# RDS DB Subnet Group には 2 AZ にまたがるサブネットが必要なため作成する。
# EC2 は Public Subnet に置くため、このサブネットはインターネットへのルートを持たない。
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-${local.azs[count.index]}"
  })
}

#------------------------------------------------------------------------------
# Internet Gateway
#------------------------------------------------------------------------------

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw"
  })
}

#------------------------------------------------------------------------------
# Route Table (Public のみ — Private は RDS 専用でインターネット不要)
#------------------------------------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

#------------------------------------------------------------------------------
# Security Group: app
#   単一 EC2 で Java (8080) と Python (8000) を同居させる構成。
#   - SSH (22) を var.allowed_ip から許可
#   - Spring Boot (8080) を var.allowed_ip から許可
#   - Python API (8000) はローカルループバック経由のみ利用するため外部開放しない
#------------------------------------------------------------------------------

resource "aws_security_group" "app" {
  name        = "${local.name_prefix}-app-sg"
  description = "Allow SSH and Spring Boot HTTP for the Datadog observability POV (single-host)"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "SSH from allowed CIDRs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ip
  }

  ingress {
    description = "Spring Boot HTTP from allowed CIDRs"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.allowed_ip
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-app-sg"
  })
}

#------------------------------------------------------------------------------
# IAM Role / Instance Profile
#   AmazonSSMManagedInstanceCore をアタッチして SSM Session Manager 接続を可能にする。
#------------------------------------------------------------------------------

resource "aws_iam_role" "app" {
  name = "${local.name_prefix}-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-app-role"
  })
}

resource "aws_iam_role_policy_attachment" "app_ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app" {
  name = "${local.name_prefix}-app-profile"
  role = aws_iam_role.app.name

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-app-profile"
  })
}
