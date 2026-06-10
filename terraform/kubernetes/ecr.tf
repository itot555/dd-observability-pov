#------------------------------------------------------------------------------
# ECR Repositories
#
# force_delete = true により、terraform destroy 時にイメージが残っていても
# リポジトリごと削除できる（POV 用途での後片付けを容易にする）。
#------------------------------------------------------------------------------

resource "aws_ecr_repository" "java_app" {
  name                 = "${local.name_prefix}-java-app"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-java-app"
  })
}

resource "aws_ecr_repository" "python_app" {
  name                 = "${local.name_prefix}-python-app"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-python-app"
  })
}
