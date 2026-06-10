#------------------------------------------------------------------------------
# RDS SG — VPC 内（EKS ノード）から PostgreSQL (:5432) への通信を許可
#------------------------------------------------------------------------------

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "Allow PostgreSQL access from within the VPC (EKS nodes)"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "PostgreSQL from VPC (EKS nodes in private subnets)"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-sg"
  })
}
