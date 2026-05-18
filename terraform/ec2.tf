#------------------------------------------------------------------------------
# Java / Spring Boot EC2 (Public Subnet)
#------------------------------------------------------------------------------

resource "aws_instance" "java" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.java_ec2_instance_type
  subnet_id                   = aws_subnet.public[0].id
  associate_public_ip_address = true
  key_name                    = aws_key_pair.ec2.key_name
  iam_instance_profile        = aws_iam_instance_profile.bastion.name

  vpc_security_group_ids = [
    aws_security_group.bastion.id,
  ]

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.java_ec2_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/scripts/java_userdata.sh", {
    COMMON_PUBLIC_KEY  = tls_private_key.ec2.public_key_openssh
    COMMON_PRIVATE_KEY = tls_private_key.ec2.private_key_pem
    NAME_PREFIX        = local.name_prefix
  })

  user_data_replace_on_change = true

  # NAT GW + Public Route Table が利用可能になってから user_data を実行
  # （apt-get update がネットワーク不到達でコケるのを防止）
  depends_on = [
    aws_route_table_association.public,
    aws_internet_gateway.this,
  ]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-bastion"
  })
}

#------------------------------------------------------------------------------
# Python EC2 (Private Subnet)
#------------------------------------------------------------------------------

resource "aws_instance" "python" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.python_ec2_instance_type
  subnet_id                   = aws_subnet.private[0].id
  associate_public_ip_address = false
  key_name                    = aws_key_pair.ec2.key_name
  iam_instance_profile        = aws_iam_instance_profile.bastion.name

  vpc_security_group_ids = [
    aws_security_group.bastion.id,
    aws_security_group.python.id,
  ]

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.python_ec2_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/scripts/python_userdata.sh", {
    COMMON_PUBLIC_KEY  = tls_private_key.ec2.public_key_openssh
    COMMON_PRIVATE_KEY = tls_private_key.ec2.private_key_pem
    NAME_PREFIX        = local.name_prefix
  })

  user_data_replace_on_change = true

  # NAT GW + Private Route Table が利用可能になってから user_data を実行
  # （Private Subnet からの apt-get update がネットワーク不到達でコケるのを防止）
  depends_on = [
    aws_nat_gateway.this,
    aws_route_table_association.private,
  ]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-py"
  })
}
