# dd-observability-pov

Datadog の **SSI（Single Step Instrumentation）** を使い、**アプリケーションコードを一行も変更せずに** APM 計装が完了するサンプルアプリです。
Java front-end + Python back-end + PostgreSQL の構成で「Before（可観測性ゼロ）→ After（APM + Log 相関）」を確認いただけます。

## ハンズオンの流れ

| フェーズ | 状態 |
|---------|------|
| **Before** | Java/Spring Boot と Python/Flask が連携して動作。Datadog Agent 未インストール。可観測性ゼロ。 |
| **After**  | SSI で Datadog Agent をインストールしてアプリを再起動するだけで、トレース・ログ・メトリクスの収集が自動開始。**コード変更なし。** |

---

## Terraform 構成

目的・環境に応じて 3 つの構成を用意しています。

| 構成 | ディレクトリ | コンピュート | OS | 特徴 |
|------|------------|-------------|----|------|
| **標準（2 台 EC2）** | [`terraform/`](terraform/README.md) | EC2 × 2 (Public + Private) | Ubuntu 22.04 | Java と Python を別ホストに分離。ネットワーク構成の可視化に適している |
| **single-host** | [`terraform/single-host/`](terraform/single-host/README.md) | EC2 × 1 (Public) | Amazon Linux 2023 | Java + Python を同一インスタンスに集約。最小コスト |
| **kubernetes** | [`terraform/kubernetes/`](terraform/kubernetes/README.md) | EKS Managed Node Group | EKS 最適化 AL2 | コンテナ環境。Datadog Operator + SSI（Admission Controller）で APM 自動注入 |

> **どちらを使うか**
> - コンテナ環境でのデモなら `terraform/kubernetes/`
> - コスト優先・シンプルなら `terraform/single-host/`

---

## エンドポイント

全構成共通のエンドポイントです。

| エンドポイント | 動作 |
|-------------|------|
| `GET /hello` | Python の `/api/data` を呼び出し、レスポンスをそのまま返す |
| `GET /timeout` | 30% の確率で Python が 10 秒遅延し、Java 側が 504 を返す |
| `GET /error` | 20% の確率で Python が 500 を返し、Java 側も同じステータスコードを伝搬する |
| `GET /db/normal` | users JOIN orders を 1 クエリで取得（1 DB span） |
| `GET /db/n1` | users 20 件 → 各 user の orders を個別取得（N+1 問題、21 DB spans） |
| `GET /db/long-run` | `SELECT pg_sleep(35)` — 35 秒幅の DB span を生成 |
| `GET /analytics` | ランダムなユーザーの前月比成長率を計算（~14% の確率で ZeroDivisionError → 500）。Java 側は 500 時に 500ms 待機して 1 回リトライ |
| `GET /analytics/summary` | ランダムなコホート（7〜8 名）の成長率を一括計算。cohort=0（新規ユーザー 7 名）で必ず 500 |

---

## 前提条件

**全構成共通:**
- Terraform `~> 1.10`
- AWS クレデンシャルが設定済みであること（`ap-northeast-1` で動作確認）
- Datadog アカウントと API Key

**kubernetes 構成のみ追加で必要:**
- `kubectl`
- `helm`
- `podman`（コンテナイメージのビルド & プッシュ）

---

## 構成別セットアップ

### terraform/single-host（推奨スタート）

```bash
cd terraform/single-host
cp locals.tf.example locals.tf   # Owner / Email 等を編集
terraform init && terraform apply

# 各ステップのコピペコマンドを表示
terraform output demo_step1_before
terraform output demo_step2_install_agent
terraform output demo_step3_configure_logs
terraform output demo_step4_after
```

### terraform/kubernetes（EKS / コンテナ環境）

```bash
cd terraform/kubernetes
cp locals.tf.example locals.tf   # Owner / Email 等を編集
terraform init && terraform apply
# → EKS クラスター、ECR リポジトリ、RDS、Datadog Operator が一括作成される

# 各ステップのコピペコマンドを表示
terraform output demo_step1_before       # イメージビルド・デプロイ
terraform output demo_step2_install_agent  # DatadogAgent CRD + SSI 有効化
terraform output demo_step3_after        # rollout restart → APM 自動計装
```

詳細は [`terraform/kubernetes/README.md`](terraform/kubernetes/README.md) を参照してください。

---

## アーキテクチャ概略

### terraform/single-host

```
Browser / curl
    │  HTTP :8080
    ▼
┌────────────────────────────┐
│  pov-app（Public EC2）      │
│  Amazon Linux 2023         │
│  Spring Boot :8080         │
│  Flask :8000 (localhost)   │
└────────────────────────────┘
    │ :5432
    ▼
RDS PostgreSQL（Private）
```

### terraform/kubernetes

```
kubectl port-forward :8080
    │
    ▼
┌──────────────────────────────────────────┐
│  VPC — Private Subnets                   │
│  ┌──────────────────────────────────┐    │
│  │  EKS Worker Node (t3.medium)     │    │
│  │  java-app Pod  → python-app Pod  │    │
│  │  Datadog Agent DaemonSet (SSI)   │    │
│  └──────────────────────────────────┘    │
│  RDS PostgreSQL（Private）               │
└──────────────────────────────────────────┘
       ECR（java-app / python-app）
```

---

## Datadog 計装の仕組み

### EC2 構成（SSI ホストレベル）

Datadog Agent の SSI スクリプト 1 コマンドで Agent + APM ライブラリを同時インストール。アプリ再起動のみで計装完了。

```bash
DD_APM_INSTRUMENTATION_LIBRARIES="java:1,python:3" \
  bash -c "$(curl -L https://install.datadoghq.com/scripts/install_script_agent7.sh)"
```

### kubernetes 構成（Datadog Operator + Admission Controller）

1. `terraform apply` で Datadog Operator を Helm インストール（`datadog` namespace）
2. `kubectl apply -f manifests/datadog-agent.yaml` で DatadogAgent CRD を作成
3. Admission Controller が **対象 namespace の Pod 作成を検知** → init container（`dd-lib-java-init` / `dd-lib-python-init`）を自動挿入
4. `kubectl rollout restart` → アプリ再起動だけで APM ライブラリが注入される

**ポイント:** Python アプリの `requirements.txt` に `ddtrace` を含めないこと。SSI が init container 経由で注入するため、`requirements.txt` に入れると**バージョン競合で ddtrace が無効化**される。

---

## ログ設計

### Java（JSON 形式）

`logstash-logback-encoder` によりJSON 形式で stdout 出力（kubernetes）またはファイル出力（EC2）。
SSI 導入後は `dd.trace_id` / `dd.span_id` が自動注入され、トレースとログが相関付けられます。

```json
{"@timestamp":"...","level":"INFO","message":"...","dd.trace_id":"123","dd.span_id":"456"}
```

### Python（JSON 形式）

kubernetes 構成では JSON formatter で stdout 出力。`dd.trace_id` がプロパティとして直接出力されるため Datadog がグロクパーサーなしで確実にパースできます。

```json
{"timestamp":"...","status":"INFO","message":"...","dd.trace_id":"123","dd.span_id":"456","dd.service":"pov-py-back"}
```

EC2 構成では Datadog 推奨フォーマットのテキストでファイル出力（`source: python` パイプライン適用）。

---

## トラブルシューティング

> 構成別の詳細コマンドは各 README のトラブルシューティングセクションを参照してください。
> - EC2: [`terraform/single-host/README.md`](terraform/single-host/README.md#トラブルシューティング)
> - Kubernetes: [`terraform/kubernetes/README.md`](terraform/kubernetes/README.md#トラブルシューティング)

### トレースが Datadog に表示されない

**EC2 構成（single-host / terraform）**

```bash
# Agent のステータスと APM 受付を確認
sudo datadog-agent status | grep -A 20 "APM Agent"

# APM ポートへの疎通確認
curl -s http://localhost:8126/info | python3 -m json.tool

# Python が ddtrace-run 経由で起動されているか確認
ps aux | grep ddtrace-run

# Java に -javaagent が注入されているか確認
ps -ef | grep java | grep javaagent
```

**Kubernetes 構成**

```bash
# SSI init container が正常に注入・完了しているか確認
kubectl describe pod -l app=java-app -n pov | grep -A 10 "Init Containers"

# DatadogAgent CRD の状態確認
kubectl get datadogagent -n datadog

# Admission Controller Webhook の存在確認
kubectl get mutatingwebhookconfigurations | grep datadog

# CRD apply 後に Pod を再起動（注入は再起動のタイミングで行われる）
kubectl rollout restart deployment/java-app deployment/python-app -n pov
```

---

### ログが Datadog に表示されない

**EC2 構成**

```bash
# ログ収集が有効か確認
grep "logs_enabled" /etc/datadog-agent/datadog.yaml
# → logs_enabled: true であること

# Agent のログ収集状態確認
sudo datadog-agent status | grep -A 20 "Log Agent"

# ログファイルを dd-agent ユーザーが読めるか確認
sudo -u dd-agent cat /var/log/<name_prefix>/python-app.log | tail -3
```

**Kubernetes 構成**

```bash
# containerCollectAll が true か確認
kubectl get datadogagent datadog -n datadog \
  -o jsonpath='{.spec.features.logCollection}' | python3 -m json.tool

# Pod アノテーションで source / service が設定されているか確認
kubectl get pod -l app=python-app -n pov \
  -o jsonpath='{.items[0].metadata.annotations}' | python3 -m json.tool
```

---

### トレースとログが相関付いていない

**共通確認事項**

1. **`DD_LOGS_INJECTION=true` の設定確認**
   - EC2: アプリ起動コマンドに環境変数が渡されているか
   - Kubernetes: Deployment の `env` セクションに定義されているか

2. **ログに `dd.trace_id` が含まれているか確認**

   ```bash
   # EC2
   tail -5 /var/log/<name_prefix>/python-app.log | python3 -m json.tool | grep trace_id

   # Kubernetes
   kubectl logs -l app=python-app -n pov --tail=5 | python3 -m json.tool | grep trace_id
   ```

3. **ログの `source` タグが正しいか確認**

   Datadog の自動ログパイプラインは `source: java` / `source: python` タグが起点。これが設定されていないと `dd.trace_id` の抽出・相関付けが行われない。
   - EC2: ログ設定ファイル（`/etc/datadog-agent/conf.d/<app>.d/conf.yaml`）の `source` を確認
   - Kubernetes: Pod アノテーション `ad.datadoghq.com/<container>.logs` の `"source"` を確認

4. **Datadog UI 側の確認**

   Datadog UI → Logs → Configuration → Pipelines で `source:java` / `source:python` のパイプラインが有効になっているか確認。

---

## ディレクトリ構成

```
dd-observability-pov/
├── README.md                              # このファイル
├── apps/
│   ├── java-app/                          # EC2 用 Spring Boot アプリ
│   │   ├── pom.xml / mvnw
│   │   └── src/
│   ├── python-app/                        # EC2 用 Flask アプリ
│   │   ├── app.py
│   │   └── requirements.txt
│   └── kubernetes/                        # コンテナ（EKS）用アプリ（EC2 版とは別管理）
│       ├── java-app/                      # JSON stdout ログ（LogstashEncoder）
│       │   ├── Dockerfile                 # Multi-stage build (JDK → JRE)
│       │   ├── pom.xml / mvnw
│       │   └── src/
│       └── python-app/                    # JSON stdout ログ / ddtrace は SSI 注入のみ
│           ├── Dockerfile
│           ├── app.py
│           └── requirements.txt           # ddtrace は含まない（SSI が注入）
├── terraform/                             # 標準構成（Ubuntu 22.04 / 2 台 EC2）
│   ├── README.md
│   └── *.tf / scripts/
├── terraform/single-host/                 # 1 台 EC2 構成（Amazon Linux 2023）
│   ├── README.md / architecture.html
│   └── *.tf / scripts/
└── terraform/kubernetes/                  # EKS 構成（コンテナ / Datadog Operator）
    ├── README.md / architecture.html
    ├── *.tf
    └── manifests/                         # kubectl apply 用 YAML（envsubst 不要・sed で適用）
        ├── namespace.yaml
        ├── java-app-deployment.yaml
        ├── java-app-service.yaml
        ├── python-app-deployment.yaml
        ├── python-app-service.yaml
        └── datadog-agent.yaml             # DatadogAgent CRD (SSI enabledNamespaces 指定)
```
