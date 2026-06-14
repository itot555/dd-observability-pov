# terraform/kubernetes/

Datadog Observability サンプル環境（Java front-end + Python back-end + PostgreSQL）を **EKS on EC2** で構築する構成です。
`terraform apply` のみで VPC・EKS クラスター・ECR リポジトリ・RDS・Datadog Operator が立ち上がります。

> **他の構成との比較**
> | 項目 | `terraform/`（2 台 EC2） | `terraform/single-host/`（1 台 EC2） | `terraform/kubernetes/`（本ディレクトリ） |
> |------|------------------------|--------------------------------------|----------------------------------------|
> | コンピュート | EC2 × 2 | EC2 × 1 | **EKS Managed Node Group** |
> | OS | Ubuntu 22.04 | Amazon Linux 2023 | **EKS 最適化 Amazon Linux 2** |
> | コンテナ | なし | なし | **あり（ECR + podman）** |
> | アプリ管理 | Bash スクリプト | Bash スクリプト | **Kubernetes マニフェスト** |
> | Datadog 計装 | EC2 SSI（ホストレベル） | EC2 SSI（ホストレベル） | **Datadog Operator + SSI（Admission Controller）** |
> | アクセス方法 | curl / ブラウザ（直接） | curl / ブラウザ（直接） | **kubectl port-forward** |
> | NAT Gateway | あり | なし | **あり** |

---

## アーキテクチャ

```
Local Machine
    │  kubectl port-forward :8080
    ▼
┌──────────────────────────────────────────────────────────┐
│  VPC (10.0.0.0/16)                                       │
│                                                          │
│  PUBLIC SUBNETS                                          │
│  ┌─────────────┐                                         │
│  │  NAT Gateway│ ← EKS ノードの Outbound（ECR / API）    │
│  └─────────────┘                                         │
│                                                          │
│  PRIVATE SUBNETS                                         │
│  ┌───────────────────────────────────────────────────┐   │
│  │  EKS Worker Node (t3.medium)                      │   │
│  │  ┌──────────────┐  ┌──────────────┐               │   │
│  │  │ java-app Pod │─▶│python-app Pod│               │   │
│  │  │  :8080       │  │  :8000       │               │   │
│  │  └──────────────┘  └──────────────┘               │   │
│  │  ┌─────────────────────────────┐                  │   │
│  │  │  Datadog Agent (DaemonSet)  │                  │   │
│  │  │  SSI Admission Controller   │                  │   │
│  │  └─────────────────────────────┘                  │   │
│  └───────────────────────────────────────────────────┘   │
│                                                          │
│  ┌─────────────────────────────┐                         │
│  │  RDS PostgreSQL (Private)   │                         │
│  │  db.t4g.micro / gp3 20GB    │                         │
│  └─────────────────────────────┘                         │
└──────────────────────────────────────────────────────────┘
                           ┌──────────────────┐
                           │  ECR (aws.io)    │
                           │  java-app        │
                           │  python-app      │
                           └──────────────────┘
```

---

## 前提条件

- Terraform `~> 1.10`
- AWS クレデンシャルが設定済みであること（`ap-northeast-1` で動作確認）
- 以下のローカルツールがインストール済みであること
  - `kubectl`
  - `helm`
  - `podman`（コンテナイメージのビルド & プッシュ）
- Datadog アカウントと API Key

---

## セットアップ

### 1. locals.tf の準備

```bash
cd terraform/kubernetes
cp locals.tf.example locals.tf
# Owner / Email 等を編集
```

### 2. terraform.tfvars の準備（任意）

```bash
cp terraform.tfvars.example terraform.tfvars
# name_prefix / allowed_ip 等を必要に応じて編集
```

`name_prefix`（デフォルト: `pov`）は、全リソース名・タグ・Datadog の `service` / `env` の先頭に付与されます。

### 3. Terraform 実行

```bash
terraform init
terraform plan
terraform apply
```

apply 完了後、以下が実施されます。

- AWS リソース（VPC / EKS / ECR / RDS）の作成
- `~/.kube/config` の自動更新（`aws eks update-kubeconfig` を `null_resource` で実行）
- Datadog Operator の Helm インストール（`datadog` namespace に作成）

apply 完了後の主な出力値:

```
eks_cluster_name    = "pov"
ecr_java_app_uri    = "<account>.dkr.ecr.ap-northeast-1.amazonaws.com/pov-java-app"
ecr_python_app_uri  = "<account>.dkr.ecr.ap-northeast-1.amazonaws.com/pov-python-app"
rds_endpoint        = "pov-postgres.xxxx.ap-northeast-1.rds.amazonaws.com"
```

各ステップのコピペ用コマンドは output から取得できます。

```bash
terraform output demo_step1_before       # Before 状態（イメージビルド・デプロイ）
terraform output demo_step2_install_agent  # Datadog Agent + SSI 有効化
terraform output demo_step3_after        # After 状態（APM 自動計装済み）
```

---

## Before / After デモフロー

### Step 1: Before 状態（Datadog なし）

```bash
# ECR ログイン
aws ecr get-login-password --region ap-northeast-1 | \
  podman login --username AWS --password-stdin \
    <account>.dkr.ecr.ap-northeast-1.amazonaws.com

# Java アプリのビルド & プッシュ（リポジトリルートから実行）
cd apps/kubernetes/java-app
podman build --platform linux/amd64 -t <ecr_java_uri>:latest .
podman push <ecr_java_uri>:latest

# Python アプリのビルド & プッシュ
cd apps/kubernetes/python-app
podman build --platform linux/amd64 -t <ecr_python_uri>:latest .
podman push <ecr_python_uri>:latest

# マニフェストの適用（terraform/kubernetes/ から実行）
sed "s|\${NAMESPACE}|pov|g" manifests/namespace.yaml | kubectl apply -f -

DB_PASSWORD=$(terraform output -raw rds_db_password)
kubectl create secret generic db-secret \
  --from-literal=host=<rds_endpoint> \
  --from-literal=dbname=appdb \
  --from-literal=username=postgres \
  --from-literal=password="$DB_PASSWORD" \
  --namespace=pov --dry-run=client -o yaml | kubectl apply -f -

sed "s|\${NAMESPACE}|pov|g; s|\${NAME_PREFIX}|pov|g; s|\${PYTHON_IMAGE}|<ecr_python_uri>:latest|g" \
  manifests/python-app-deployment.yaml | kubectl apply -f -
sed "s|\${NAMESPACE}|pov|g" manifests/python-app-service.yaml | kubectl apply -f -

sed "s|\${NAMESPACE}|pov|g; s|\${NAME_PREFIX}|pov|g; s|\${JAVA_IMAGE}|<ecr_java_uri>:latest|g" \
  manifests/java-app-deployment.yaml | kubectl apply -f -
sed "s|\${NAMESPACE}|pov|g" manifests/java-app-service.yaml | kubectl apply -f -

# ポートフォワードでアクセス
kubectl port-forward svc/java-app 8080:8080 -n pov
# → http://localhost:8080
```

### Step 2: Datadog Agent インストール（SSI）

```bash
# Datadog API Key シークレット作成
kubectl create secret generic datadog-secret \
  --from-literal=api-key=<DD_API_KEY> \
  --namespace=datadog

# DatadogAgent CRD の適用（アプリ namespace にのみ SSI を有効化）
sed "s|\${NAMESPACE}|pov|g; s|\${CLUSTER_NAME}|pov|g" manifests/datadog-agent.yaml | kubectl apply -f -

# Agent DaemonSet の起動確認
kubectl rollout status daemonset -n datadog
kubectl get pods -n datadog
```

### Step 3: After 状態（APM 自動計装済み）

Admission Controller が Pod 再起動を検知し、APM ライブラリ（init container）を **コード変更なしで自動注入** します。

```bash
kubectl rollout restart deployment/python-app deployment/java-app -n pov
kubectl rollout status deployment/python-app deployment/java-app -n pov

# ポートフォワードでアクセス
kubectl port-forward svc/java-app 8080:8080 -n pov
# → http://localhost:8080
# → Datadog APM でトレースを確認
# → ログ ↔ トレース相関を確認
# → /analytics（~14% エラー）・/analytics/summary でエラー分析シナリオを確認
```

---

## ファイル構成

| ファイル | 役割 |
|---------|------|
| `main.tf` / `provider.tf` | Terraform バージョン・プロバイダー設定（aws のみ） |
| `variables.tf` | 入力変数（region / name_prefix / network / EKS / RDS） |
| `locals.tf` / `locals.tf.example` | common_tags + name_prefix（`locals.tf` は `.gitignore` 対象） |
| `terraform.tfvars.example` | `terraform.tfvars` のテンプレート |
| `base.tf` | VPC / Subnet / IGW / NAT GW / EKS クラスター IAM ロール / ノード IAM ロール |
| `data.tf` | AZ データソース / AWS アカウント ID |
| `ecr.tf` | ECR リポジトリ × 2（`force_delete=true` で destroy 時に一括削除） |
| `eks.tf` | EKS クラスター / Launch Template / Managed Node Group / kubeconfig 更新 |
| `sg.tf` | RDS SG（VPC CIDR からの 5432 許可） |
| `rds.tf` | RDS PostgreSQL / random_password |
| `helm.tf` | Datadog Operator インストール（`null_resource + helm CLI`） |
| `outputs.tf` | ECR URI / RDS endpoint / demo_step1〜3 コピペ手順 |
| `manifests/namespace.yaml` | アプリ用 Namespace |
| `manifests/java-app-deployment.yaml` | Java アプリ Deployment（`${JAVA_IMAGE}` プレースホルダー） |
| `manifests/java-app-service.yaml` | Java アプリ Service（ClusterIP） |
| `manifests/python-app-deployment.yaml` | Python アプリ Deployment（`${PYTHON_IMAGE}` プレースホルダー） |
| `manifests/python-app-service.yaml` | Python アプリ Service（ClusterIP） |
| `manifests/datadog-agent.yaml` | DatadogAgent CRD（SSI + ログ収集、`${NAMESPACE}` のみ有効化） |

---

## セキュリティ設計

| 項目 | 対応 |
|-----|------|
| IMDSv2 | `http_tokens = "required"` / `http_put_response_hop_limit = 2`（コンテナからのアクセスに必要）|
| EBS 暗号化 | ノード起動テンプレートで `encrypted = true` |
| RDS 暗号化 | `storage_encrypted = true` |
| ノードのパブリック IP | プライベートサブネット配置でパブリック IP なし |
| ECR | プライベートリポジトリ（`AmazonEC2ContainerRegistryReadOnly` ポリシーでノードが pull）|
| EKS パブリックエンドポイント | `public_access_cidrs = var.allowed_ip` で許可元 CIDR を制限可能 |
| DB パスワード | Terraform で生成、`kubectl create secret` で Kubernetes Secret に格納 |
| IAM | ノードロールは最小権限（WorkerNode / CNI / ECR / SSM のみ）|

## クリーンアップ（Destroy）

```bash
# Step 1: アプリ namespace を先に削除（kubectl 管理リソースをクリーンアップ）
kubectl delete namespace <name_prefix> --ignore-not-found
# → Deployment / Service / Secret が一括削除される

# Step 2: Terraform で全 AWS リソースを削除
terraform destroy
```

以下は `terraform destroy` が自動クリーンアップします。

| リソース | クリーンアップ方法 |
|---------|-----------------|
| Datadog Operator | `helm_release` → Terraform が `helm uninstall` を自動実行 |
| ECR リポジトリ | `force_delete = true` でイメージが残っていても削除可 |
| RDS | `skip_final_snapshot / deletion_protection=false` で即時削除 |
| EKS クラスター | ノードグループ → クラスターの順に自動削除 |
| VPC / NAT GW / Subnet | 依存関係順に自動削除 |

所要時間: 約 15〜20 分。コピペ手順は `terraform output demo_destroy` で確認できます。

---

---

## トラブルシューティング

> **事前準備: namespace 変数のセット**
> 以下のコマンドを最初に実行しておくと、以降のコマンドをそのままコピペできます。
> `kubectl get ns` で実際の namespace を確認してください。
>
> ```bash
> NS=dryrun-pov   # 自分の name_prefix に変更
> ```

---

### トレースが Datadog に表示されない

**1. DatadogAgent CRD の状態確認**

```bash
kubectl get datadogagent -n datadog
# AGENT / CLUSTER-AGENT が "Running (N/N/N)" であることを確認

kubectl describe datadogagent datadog -n datadog | grep -A 10 "Conditions"
# Type: ActiveDatadogMetrics, Status: True であれば正常
```

**2. Cluster Agent のリーダー選出確認**

DatadogAgent CRD を apply / 変更した後は、Cluster Agent のリーダー選出が完了してから Pod を再起動してください。
完了前に rollout restart すると、Admission Controller の設定が未完成のまま Pod が作成され init container が注入されません。

```bash
# Cluster Agent Pod が Running (1/1) であることを確認
kubectl get pods -n datadog -l agent.datadoghq.com/component=cluster-agent

# リーダー選出が完了しているか確認（"Started leading" が出力されていれば OK）
kubectl logs -n datadog -l agent.datadoghq.com/component=cluster-agent --tail=100 | grep -i "leader"
```

**3. Admission Controller Webhook の確認**

```bash
# MutatingWebhookConfiguration が存在するか確認
kubectl get mutatingwebhookconfigurations | grep datadog
# → "datadog-webhook" が 4 件表示されれば OK
```

**4. SSI init container の注入確認**

```bash
kubectl describe pod -l app=java-app -n $NS \
  | grep "^\s*datadog-lib\|^\s*datadog-init\|State:\|Reason:"
kubectl describe pod -l app=python-app -n $NS \
  | grep "^\s*datadog-lib\|^\s*datadog-init\|State:\|Reason:"
```

`datadog-lib-java-init` / `datadog-lib-python-init` / `datadog-init-apm-inject` が `Reason: Completed` であれば注入済み。

**init container がない場合** — Cluster Agent のリーダー選出完了（Step 2）を確認してから再起動します。

```bash
kubectl rollout restart deployment/java-app deployment/python-app -n $NS
kubectl rollout status deployment/java-app deployment/python-app -n $NS
```

**5. Agent の APM 受信状態確認**

```bash
AGENT_POD=$(kubectl get pods -n datadog -l agent.datadoghq.com/component=agent -o name | head -1)
echo "Target pod: $AGENT_POD"   # 空なら上のラベルを確認
kubectl exec -n datadog $AGENT_POD -c agent -- agent status | grep -A 15 "APM Agent"
# "Receiver" セクションに受信スパン数が表示されれば Agent まで届いている
```

---

### ログが Datadog に表示されない

**1. Pod アノテーションの確認**

ログ収集は `containerCollectAll: false` のため、Pod アノテーションで収集対象を明示しています。

```bash
kubectl get pod -l app=java-app -n $NS \
  -o jsonpath='{.items[0].metadata.annotations}' | python3 -m json.tool
```

`ad.datadoghq.com/java-app.logs` に `"source":"java"` / `"service":"<NS>-java-front"` が設定されていることを確認。

**2. ログ収集設定の確認**

```bash
kubectl get datadogagent datadog -n datadog \
  -o jsonpath='{.spec.features.logCollection}' | python3 -m json.tool
# → "enabled": true であることを確認
# → "containerCollectAll": false は正常（Pod アノテーション方式）
```

**3. Agent のログ収集状態確認**

```bash
AGENT_POD=$(kubectl get pods -n datadog -l agent.datadoghq.com/component=agent -o name | head -1)
kubectl exec -n datadog $AGENT_POD -c agent -- agent status | grep -A 20 "Logs Agent"
# "Bytes sent" がカウントアップしていれば正常に送信中
```

**4. Agent Pod のエラーログ確認**

```bash
# node agent (DaemonSet)
kubectl logs -n datadog -l agent.datadoghq.com/component=agent --tail=50 | grep -iE "error|warn"

# Cluster Agent
kubectl logs -n datadog -l agent.datadoghq.com/component=cluster-agent --tail=50 | grep -iE "error|warn"
```

---

### トレースとログが相関付いていない

**1. DD_LOGS_INJECTION 環境変数の確認**

SSI による init container 注入後は `DD_LOGS_INJECTION=true` が自動設定されます。

```bash
kubectl exec -n $NS deployment/java-app -- env | grep DD_LOGS_INJECTION
kubectl exec -n $NS deployment/python-app -- env | grep DD_LOGS_INJECTION
# → DD_LOGS_INJECTION=true であること
```

表示されない場合は init container が注入されていません（上記「トレースが表示されない」を参照）。

**2. ログに trace_id が含まれているか確認**

```bash
# python3 -m json.tool は複数行 JSON 非対応のため --tail=1 で 1 行ずつ確認
kubectl logs -l app=python-app -n $NS --tail=1 | python3 -m json.tool | grep -E "trace_id|span_id"
kubectl logs -l app=java-app -n $NS --tail=1 | python3 -m json.tool | grep -E "trace_id|span_id"
```

`dd.trace_id` / `dd.span_id` が存在すれば相関設定は成功。
値が `"0"` の場合はリクエストが来ていないか APM がトレースを生成できていません。

**3. ログの source タグ確認**

Datadog のログパイプラインは `source: java` / `source: python` が起点です。
`source` が正しくないと `trace_id` の抽出・相関付けが行われません。

```bash
kubectl get pod -l app=python-app -n $NS \
  -o jsonpath='{.items[0].metadata.annotations}' | python3 -m json.tool | grep source
# → "source": "python" であること（Java は "java"）
```

**4. init container が Error の場合**

```bash
kubectl describe pod -l app=java-app -n $NS \
  | grep "^\s*datadog-lib\|^\s*datadog-init\|State:\|Reason:"
```

`Reason: Error` の場合は Pod を削除して Admission Controller に再注入させます。

```bash
kubectl delete pod -l app=java-app -n $NS
# Deployment が自動で新しい Pod を作成し、init container が再注入される
```

---

## gitignore 対象ファイル

```
terraform.tfstate      # AWS リソース情報・秘密鍵が含まれる
terraform.tfstate.*
.terraform/
terraform.tfvars       # 環境固有値
locals.tf              # 個人情報（氏名・メールアドレス等）
```
