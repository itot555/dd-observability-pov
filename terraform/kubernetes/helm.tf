#------------------------------------------------------------------------------
# Datadog Operator のインストール（Helm Provider）
#
# helm provider が EKS クラスターの endpoint / CA / token を参照するため、
# helm_release は aws_eks_node_group.this の作成完了後に実行される。
# destroy 時は Terraform が自動的に helm uninstall を実行する。
#------------------------------------------------------------------------------

resource "helm_release" "datadog_operator" {
  name             = "datadog-operator"
  repository       = "https://helm.datadoghq.com"
  chart            = "datadog-operator"
  namespace        = "datadog"
  create_namespace = true
  wait             = true
  timeout          = 600

  depends_on = [aws_eks_node_group.this]
}
