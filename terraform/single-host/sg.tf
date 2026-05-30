#------------------------------------------------------------------------------
# RDS SG — App EC2 から PostgreSQL (:5432) への通信を許可
#------------------------------------------------------------------------------

resource "aws_security_group" "rds" {
  name   = "${local.name_prefix}-rds-sg"
  vpc_id = aws_vpc.this.id

  ingress {
    description     = "PostgreSQL from App EC2"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-sg"
  })
}
