#------------------------------------------------------------------------------
# EKS Cluster
#------------------------------------------------------------------------------

resource "aws_eks_cluster" "this" {
  name     = local.name_prefix
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.eks_cluster_version

  vpc_config {
    subnet_ids              = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.allowed_ip
  }

  # API + ConfigMap 両方でアクセス管理。bootstrap により terraform 実行者が admin 権限を取得
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  # SCP 必須: Extended Support（追加課金）を防ぐため Standard Support を明示
  upgrade_policy {
    support_type = "STANDARD"
  }

  # 最低限の監査ログを有効化
  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_internet_gateway.this,
  ]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cluster"
  })
}

#------------------------------------------------------------------------------
# Launch Template
#
# IMDSv2 強制（SCP 要件対応）、EBS 暗号化、タグのみ設定。
# AMI / インスタンスタイプは Managed Node Group 側で指定するため省略する。
# http_put_response_hop_limit = 2 はコンテナから IMDS にアクセスするために必要。
#------------------------------------------------------------------------------

resource "aws_launch_template" "node" {
  name_prefix = "${local.name_prefix}-node-"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.node_volume_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-node"
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

#------------------------------------------------------------------------------
# Managed Node Group
#
# ノードはプライベートサブネットに配置。NAT GW 経由で ECR や EKS API に到達する。
#------------------------------------------------------------------------------

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.name_prefix}-ng"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = aws_subnet.private[*].id
  instance_types  = [var.node_instance_type]

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  launch_template {
    id      = aws_launch_template.node.id
    version = "$Latest"
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_policy,
    aws_nat_gateway.this,
    aws_route_table_association.private,
  ]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ng"
  })
}

#------------------------------------------------------------------------------
# kubeconfig 更新
#
# terraform apply 後にローカルの kubeconfig を自動更新する。
# kubectl / helm コマンドがすぐに使えるようになる。
#------------------------------------------------------------------------------

resource "null_resource" "kubeconfig" {
  depends_on = [aws_eks_node_group.this]

  triggers = {
    cluster_name = aws_eks_cluster.this.name
    region       = var.region
  }

  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name ${aws_eks_cluster.this.name} --region ${var.region}"
  }
}
