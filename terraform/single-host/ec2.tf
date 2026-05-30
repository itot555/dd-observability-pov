#------------------------------------------------------------------------------
# App EC2 (Public Subnet) — Java + Python を同居させる単一インスタンス
#------------------------------------------------------------------------------

resource "aws_instance" "app" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.ec2_instance_type
  subnet_id                   = aws_subnet.public[0].id
  associate_public_ip_address = true
  key_name                    = aws_key_pair.ec2.key_name
  iam_instance_profile        = aws_iam_instance_profile.app.name

  vpc_security_group_ids = [
    aws_security_group.app.id,
  ]

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.ec2_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/scripts/userdata.sh", {
    COMMON_PUBLIC_KEY  = tls_private_key.ec2.public_key_openssh
    COMMON_PRIVATE_KEY = tls_private_key.ec2.private_key_pem
    NAME_PREFIX        = local.name_prefix
  })

  user_data_replace_on_change = true

  depends_on = [
    aws_route_table_association.public,
    aws_internet_gateway.this,
  ]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-app"
  })
}
