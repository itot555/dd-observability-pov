#==============================================================================
# base.tf
#
# スタンドアロン構成で必要となる「土台」リソースをまとめたファイルです。
# 本リポジトリは単独で `terraform apply` できるよう、VPC・サブネット・IAM・
# セキュリティグループ等の基盤リソースもここに集約しています。
#
# このファイルに含まれるリソース
#   - VPC / 2x Public Subnet / 2x Private Subnet
#   - Internet Gateway / NAT Gateway（コスト抑制のため Single NAT）
#   - Route Table（Public / Private）
#   - bastion SG（SSH 22 + Spring Boot 8080 + 内部通信用 self、両 EC2 で共用）
#   - bastion IAM Role / Instance Profile（SSM Session Manager 対応）
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
# NAT Gateway (Single NAT for cost efficiency)
#------------------------------------------------------------------------------

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-eip"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat"
  })

  depends_on = [aws_internet_gateway.this]
}

#------------------------------------------------------------------------------
# Route Tables
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

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-rt"
  })
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

#------------------------------------------------------------------------------
# Security Group: bastion
#   両 EC2 で共通利用する SG。Java EC2 がパブリック踏み台（bastion）兼
#   Spring Boot 公開ホストの役割を担うため bastion 命名としている。
#   - SSH (22) を var.allowed_ip から許可
#   - Spring Boot (8080) を var.allowed_ip から許可（Java 用、Python は private で実害なし）
#   - SG 内部の self ingress を許可することで Java -> Python の ProxyJump SSH や
#     python-sg / rds-sg からの security_groups 参照を成立させる
#------------------------------------------------------------------------------

resource "aws_security_group" "bastion" {
  name        = "${local.name_prefix}-bastion-sg"
  description = "Allow SSH, Spring Boot HTTP, and intra-SG traffic for the Datadog observability POV"
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

  ingress {
    description = "Intra-SG traffic between Java and Python EC2 (ProxyJump SSH, DD agent ports, etc.)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-bastion-sg"
  })
}

#------------------------------------------------------------------------------
# IAM Role / Instance Profile for both EC2 instances
#   Datadog SSI 自体には IAM 権限は不要だが、
#   SSM Session Manager 経由での接続を可能にするため
#   AmazonSSMManagedInstanceCore をアタッチする。
#------------------------------------------------------------------------------

resource "aws_iam_role" "bastion" {
  name = "${local.name_prefix}-bastion-role"

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
    Name = "${local.name_prefix}-bastion-role"
  })
}

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${local.name_prefix}-bastion-profile"
  role = aws_iam_role.bastion.name

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-bastion-profile"
  })
}
