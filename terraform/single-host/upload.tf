#------------------------------------------------------------------------------
# Upload apps/ to the App EC2 via file provisioner (direct SSH, no bastion)
#------------------------------------------------------------------------------

resource "null_resource" "upload_apps" {
  triggers = {
    java_src_hash   = sha256(join(",", [for f in sort(fileset("${path.module}/../../apps/java-app", "**")) : filesha256("${path.module}/../../apps/java-app/${f}")]))
    python_src_hash = sha256(join(",", [for f in sort(fileset("${path.module}/../../apps/python-app", "**")) : filesha256("${path.module}/../../apps/python-app/${f}")]))
    instance_id     = aws_instance.app.id
  }

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = tls_private_key.ec2.private_key_pem
    host        = aws_instance.app.public_ip
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = ["mkdir -p /home/ec2-user/apps"]
  }

  provisioner "file" {
    source      = "${path.module}/../../apps/java-app"
    destination = "/home/ec2-user/apps"
  }

  provisioner "file" {
    source      = "${path.module}/../../apps/python-app"
    destination = "/home/ec2-user/apps"
  }

  provisioner "remote-exec" {
    inline = ["chmod +x /home/ec2-user/apps/java-app/mvnw"]
  }
}
