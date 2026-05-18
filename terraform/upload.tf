#------------------------------------------------------------------------------
# Upload apps/ to EC2 instances via file provisioner
#------------------------------------------------------------------------------

resource "null_resource" "upload_java_app" {
  triggers = {
    src_hash    = sha256(join(",", [for f in sort(fileset("${path.module}/../apps/java-app", "**")) : filesha256("${path.module}/../apps/java-app/${f}")]))
    instance_id = aws_instance.java.id
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.ec2.private_key_pem
    host        = aws_instance.java.public_ip
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = ["mkdir -p /home/ubuntu/apps"]
  }

  provisioner "file" {
    source      = "${path.module}/../apps/java-app"
    destination = "/home/ubuntu/apps"
  }

  provisioner "remote-exec" {
    inline = ["chmod +x /home/ubuntu/apps/java-app/mvnw"]
  }
}

resource "null_resource" "upload_python_app" {
  triggers = {
    src_hash    = sha256(join(",", [for f in sort(fileset("${path.module}/../apps/python-app", "**")) : filesha256("${path.module}/../apps/python-app/${f}")]))
    instance_id = aws_instance.python.id
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.ec2.private_key_pem
    host        = aws_instance.python.private_ip
    timeout     = "10m"

    bastion_host        = aws_instance.java.public_ip
    bastion_user        = "ubuntu"
    bastion_private_key = tls_private_key.ec2.private_key_pem
  }

  provisioner "remote-exec" {
    inline = ["mkdir -p /home/ubuntu/apps"]
  }

  provisioner "file" {
    source      = "${path.module}/../apps/python-app"
    destination = "/home/ubuntu/apps"
  }
}
