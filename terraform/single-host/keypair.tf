#------------------------------------------------------------------------------
# SSH Key Pair Management
#------------------------------------------------------------------------------

resource "tls_private_key" "ec2" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.ec2.private_key_pem
  filename        = "${path.module}/keys/${local.name_prefix}-ssh-key"
  file_permission = "0600"

  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/keys"
  }

  depends_on = [tls_private_key.ec2]
}

resource "local_file" "public_key" {
  content         = tls_private_key.ec2.public_key_openssh
  filename        = "${path.module}/keys/${local.name_prefix}-ssh-key.pub"
  file_permission = "0644"

  depends_on = [tls_private_key.ec2]
}

resource "aws_key_pair" "ec2" {
  key_name   = "${local.name_prefix}-keypair"
  public_key = local_file.public_key.content

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-keypair"
    }
  )
}
