#------------------------------------------------------------------------------
# Cluster / ECR / RDS 基本情報
#------------------------------------------------------------------------------

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.this.name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster API server endpoint"
  value       = aws_eks_cluster.this.endpoint
}

output "ecr_java_app_uri" {
  description = "ECR repository URI for java-app"
  value       = aws_ecr_repository.java_app.repository_url
}

output "ecr_python_app_uri" {
  description = "ECR repository URI for python-app"
  value       = aws_ecr_repository.python_app.repository_url
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = aws_db_instance.postgres.address
}

output "rds_db_password" {
  description = "RDS PostgreSQL master password (sensitive)"
  value       = random_password.db.result
  sensitive   = true
}

#------------------------------------------------------------------------------
# Demo 手順 — Step 1: Before（Datadog なし）
#------------------------------------------------------------------------------

output "demo_step1_before" {
  description = "Step 1: Build & push images, deploy apps (Before state — no Datadog)"
  value       = <<-EOT

    ===== STEP 1: Before 状態（Datadog なし）=====

    ## ECR へのログイン
    aws ecr get-login-password --region ${var.region} | \
      podman login --username AWS --password-stdin \
        ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com

    ## Java アプリのビルド & ECR プッシュ（リポジトリルートから実行）
    cd apps/kubernetes/java-app
    podman build --platform linux/amd64 -t ${aws_ecr_repository.java_app.repository_url}:latest .
    podman push ${aws_ecr_repository.java_app.repository_url}:latest

    ## Python アプリのビルド & ECR プッシュ
    cd apps/kubernetes/python-app
    podman build --platform linux/amd64 -t ${aws_ecr_repository.python_app.repository_url}:latest .
    podman push ${aws_ecr_repository.python_app.repository_url}:latest

    ## マニフェストの適用（terraform/kubernetes/ から実行）

    # Namespace 作成
    sed "s|\$${NAMESPACE}|${local.name_prefix}|g" \
      manifests/namespace.yaml | kubectl apply -f -

    # DB シークレット作成（パスワードは一時ファイル経由で zsh の特殊文字展開を回避）
    terraform output -raw rds_db_password > /tmp/rds_pw.txt
    kubectl create secret generic db-secret \
      --from-literal=host=${aws_db_instance.postgres.address} \
      --from-literal=dbname=appdb \
      --from-literal=username=postgres \
      --from-file=password=/tmp/rds_pw.txt \
      --namespace=${local.name_prefix} \
      --dry-run=client -o yaml | kubectl apply -f -
    rm /tmp/rds_pw.txt

    # Python アプリ
    sed "s|\$${NAMESPACE}|${local.name_prefix}|g; s|\$${NAME_PREFIX}|${local.name_prefix}|g; s|\$${PYTHON_IMAGE}|${aws_ecr_repository.python_app.repository_url}:latest|g" \
      manifests/python-app-deployment.yaml | kubectl apply -f -
    sed "s|\$${NAMESPACE}|${local.name_prefix}|g" \
      manifests/python-app-service.yaml | kubectl apply -f -

    # Java アプリ
    sed "s|\$${NAMESPACE}|${local.name_prefix}|g; s|\$${NAME_PREFIX}|${local.name_prefix}|g; s|\$${JAVA_IMAGE}|${aws_ecr_repository.java_app.repository_url}:latest|g" \
      manifests/java-app-deployment.yaml | kubectl apply -f -
    sed "s|\$${NAMESPACE}|${local.name_prefix}|g" \
      manifests/java-app-service.yaml | kubectl apply -f -

    ## アクセス確認（別ターミナルでポートフォワード）
    kubectl rollout status deployment/python-app deployment/java-app -n ${local.name_prefix}
    kubectl port-forward svc/java-app 8080:8080 -n ${local.name_prefix}
    # → http://localhost:8080

  EOT
}

#------------------------------------------------------------------------------
# Demo 手順 — Step 2: Datadog Agent インストール（SSI）
#------------------------------------------------------------------------------

output "demo_step2_install_agent" {
  description = "Step 2: Install Datadog Agent via DatadogAgent CRD with SSI"
  value       = <<-EOT

    ===== STEP 2: Datadog Agent インストール（SSI）=====
    DD_API_KEY: Datadog UI > Organization Settings > API Keys からコピー

    ## Datadog API Key シークレット作成（datadog namespace）
    kubectl create secret generic datadog-secret \
      --from-literal=api-key=<DD_API_KEY> \
      --namespace=datadog

    ## DatadogAgent CRD の適用（アプリ namespace にのみ SSI を有効化）
    sed "s|\$${NAMESPACE}|${local.name_prefix}|g" \
      manifests/datadog-agent.yaml | kubectl apply -f -

    ## Agent DaemonSet と Admission Controller Webhook の起動確認（1〜2 分）
    kubectl rollout status daemonset -n datadog
    kubectl get pods -n datadog

  EOT
}

#------------------------------------------------------------------------------
# Demo 手順 — Step 3: After（APM 計装済み）
#------------------------------------------------------------------------------

output "demo_step3_after" {
  description = "Step 3: Restart pods to apply SSI APM auto-instrumentation (After state)"
  value       = <<-EOT

    ===== STEP 3: After 状態（APM 自動計装済み）=====

    ## アプリ Pod の再起動（Admission Controller が APM ライブラリを自動注入）
    kubectl rollout restart deployment/python-app deployment/java-app -n ${local.name_prefix}
    kubectl rollout status deployment/python-app deployment/java-app -n ${local.name_prefix}

    ## 注入されたライブラリの確認
    kubectl describe pod -l app=java-app -n ${local.name_prefix} | grep -A5 "Init Containers"
    kubectl describe pod -l app=python-app -n ${local.name_prefix} | grep -A5 "Init Containers"

    ## ポートフォワードでアクセス
    kubectl port-forward svc/java-app 8080:8080 -n ${local.name_prefix}
    # → http://localhost:8080
    # → Datadog APM でトレースを確認
    # → Datadog Log Management でトレース相関ログを確認

  EOT
}

#------------------------------------------------------------------------------
# Demo 手順 — Destroy（完全クリーンアップ）
#------------------------------------------------------------------------------

output "demo_destroy" {
  description = "Complete cleanup: delete kubectl resources then terraform destroy"
  value       = <<-EOT

    ===== DESTROY: 完全クリーンアップ =====

    ## Step 1: アプリ namespace の削除（kubectl 管理リソースを先にクリーンアップ）
    kubectl delete namespace ${local.name_prefix} --ignore-not-found
    # → Deployment / Service / Secret / ConfigMap が一括削除される

    ## Step 2: Terraform による全 AWS リソース削除
    ## ※ terraform/kubernetes/ ディレクトリから実行
    terraform destroy
    # 自動クリーンアップ内容:
    #   helm_release → helm uninstall datadog-operator（datadog namespace も削除）
    #   ECR リポジトリ  → force_delete=true でイメージごと削除
    #   RDS             → skip_final_snapshot / deletion_protection=false で即時削除
    #   EKS クラスター  → ノードグループ → クラスター の順に削除
    #   VPC / NAT GW / Subnet / IGW → 依存関係順に自動削除
    # 所要時間: 約 15〜20 分

    ## 削除確認（terraform destroy 完了後）
    aws eks list-clusters --region ${var.region} \
      --query "clusters[?contains(@,'${local.name_prefix}')]"
    aws ecr describe-repositories --region ${var.region} \
      --query "repositories[?contains(repositoryName,'${local.name_prefix}')].[repositoryName]"
    aws rds describe-db-instances --region ${var.region} \
      --query "DBInstances[?contains(DBInstanceIdentifier,'${local.name_prefix}')].[DBInstanceIdentifier]"

  EOT
}
