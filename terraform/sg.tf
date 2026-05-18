#------------------------------------------------------------------------------
# Python SG — Java EC2 から Python API (:8000) への通信を許可
#------------------------------------------------------------------------------

resource "aws_security_group" "python" {
  name   = "${local.name_prefix}-python-sg"
  vpc_id = aws_vpc.this.id

  ingress {
    description     = "Python API from Java EC2 (via bastion-sg)"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-python-sg"
  })
}

#------------------------------------------------------------------------------
# RDS SG — Python EC2 (bastion-sg 経由) から PostgreSQL (:5432) への通信を許可
#------------------------------------------------------------------------------

resource "aws_security_group" "rds" {
  name   = "${local.name_prefix}-rds-sg"
  vpc_id = aws_vpc.this.id

  ingress {
    description     = "PostgreSQL from Python EC2 (via bastion-sg)"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-sg"
  })
}
