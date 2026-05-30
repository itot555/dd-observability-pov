# dd-observability-pov

Datadog の **SSI（Single Step Instrumentation）** を使い、**アプリケーションコードを一行も変更せずに** APM 計装が完了するサンプルアプリです。
Terraform で AWS 上に必要なリソース（VPC・EC2・RDS）を作成し、Java front-end + Python back-end + PostgreSQL の構成で「Before（可観測性ゼロ）→ After（APM + Log 相関）」を確認いただけます

## ハンズオンの流れ

| フェーズ | 状態 |
|---------|------|
| **Before** | Java/Spring Boot と Python/Flask が連携して動作。Datadog Agent 未インストール。可観測性ゼロ。 |
| **After**  | SSI で Datadog Agent をインストールしてアプリを再起動するだけで、トレース・ログ・メトリクスの収集が自動開始。**コード変更なし。** |

ステップ:

1. **Terraform でリソース作成** — `terraform apply` のみで VPC〜EC2〜RDS まで構築
2. **アプリ起動** — Before 状態（Datadog なし）で動作確認
3. **Datadog Agent インストール（SSI）** — 1 コマンドで Agent + APM ライブラリ導入
4. **Log 機能有効化** — `logs_enabled: true` とログファイル指定
5. **SSI を用いた APM 利用** — アプリを再起動するだけで自動計装
6. **APM ↔ Log の相関確認** — `dd.trace_id` / `dd.span_id` でトレースとログを紐付け

---

## アーキテクチャ

```
Internet
    │
    ▼  :8080
┌─────────────────────────────┐
│  <name_prefix>-bastion      │
│  (Public) Ubuntu 22.04      │
│  Java 21 + Maven            │
│  Spring Boot                │
└─────────────────────────────┘
    │ :8000 (VPC 内通信)
    ▼
┌─────────────────────────────┐
│  <name_prefix>-py (Private) │
│  Ubuntu 22.04               │
│  Python 3 + Flask           │
└─────────────────────────────┘
    │ :5432
    ▼
┌─────────────────────────────┐
│  RDS PostgreSQL (Private)   │
│  db.t4g.micro / gp3 20GB    │
└─────────────────────────────┘
```

ネットワーク（VPC・サブネット・IGW・NAT・ルートテーブル）、IAM ロール、セキュリティグループはすべて本リポジトリの `terraform/base.tf` で作成します。
外部 tfstate への依存はありません。

### エンドポイント

| エンドポイント | 動作 |
|-------------|------|
| `GET /hello` | Python の `/api/data` を呼び出し、レスポンスをそのまま返す |
| `GET /timeout` | Python の `/api/timeout` を呼び出す。30% の確率で Python が 10 秒遅延し、Java 側が 5 秒タイムアウトで 504 を返す |
| `GET /error` | Python の `/api/error` を呼び出す。20% の確率で Python が 500 を返し、Java 側も同じステータスコードを伝搬する |

### Web UI

`http://<java-public-ip>:8080/` をブラウザで開くと、エンドポイントを選択して送信できる UI が表示されます。

---

## Terraform 構成

このリポジトリには用途に応じた 2 つの Terraform 構成が含まれています。

| 構成 | ディレクトリ | EC2 | OS | 特徴 |
|------|------------|-----|----|------|
| **標準（2 台）** | [`terraform/`](terraform/README.md) | 2 台（Public + Private） | Ubuntu 22.04 | Java と Python を別ホストに分離。ネットワーク構成の可視化に適している |
| **single-host** | [`terraform/single-host/`](terraform/single-host/README.md) | 1 台（Public のみ） | Amazon Linux 2023 | Java + Python を同一インスタンスに集約。|

> **どちらを使うか**: POV・デモ用途でコストを抑えたい場合は `terraform/single-host/` を使用してください。

---

## 前提条件

- Terraform `~> 1.10`
- AWS クレデンシャルが設定済みであること（`ap-northeast-1` で動作確認）
- Datadog アカウントと API Key

---

## セットアップ

### 1. locals.tf の準備

```bash
cd terraform
cp locals.tf.example locals.tf
# locals.tf を編集してください
```

### 2. terraform.tfvars の準備（任意）

デフォルト値のままで動作しますが、`name_prefix` / `allowed_ip` / インスタンスタイプ等を変更したい場合は `terraform.tfvars` を作成してください。

```bash
cp terraform.tfvars.example terraform.tfvars
# 必要箇所のコメントを外して編集してください
```

`name_prefix`（デフォルト: `pov`）は、全リソース名・タグ・Datadog の `service` / `env` の先頭に付与されます。
環境に合わせて一意な値に変更してご利用ください（例: `acme-poc`）。

### 3. Terraform 実行

```bash
terraform init
terraform plan
terraform apply
```

apply 完了後、以下のような値が出力されます（`<prefix>` は `name_prefix` の値）。

```
java_ec2_public_ip     = "x.x.x.x"
java_ec2_ssh_command   = "ssh -i keys/<prefix>-ssh-key ubuntu@x.x.x.x"
python_ec2_private_ip  = "10.0.x.x"
python_ec2_ssh_command = "ssh -i keys/<prefix>-ssh-key -J ubuntu@<java_ip> ubuntu@<python_ip>"
```

各ステップのコピペ用コマンドは output から取得できます。

```bash
terraform output demo_step1_before          # Before 状態でアプリ起動
terraform output demo_step2_install_agent   # Datadog Agent インストール（SSI）
terraform output demo_step3_configure_logs  # ログ収集設定
terraform output demo_step4_after           # After 状態でアプリ再起動（APM 計装済）
```

### 4. Python アプリの起動

```bash
# Python EC2 に SSH 接続（Bastion EC2 を踏み台に）
ssh -i terraform/keys/<prefix>-ssh-key \
  -J ubuntu@<java_public_ip> ubuntu@<python_private_ip>

# user_data 完了確認（"Bootstrapping complete." が末尾に表示されれば OK）
tail /var/log/user-data.log

# Python アプリ起動
cd ~/apps/python-app
python3 -m venv venv
source venv/bin/activate
pip3 install -r requirements.txt
set -a; source /home/ubuntu/.env; set +a
nohup python3 app.py > /var/log/<prefix>/python-app.log 2>&1 &
```

### 5. Java アプリのビルド・起動

```bash
# Bastion EC2 に SSH 接続
ssh -i terraform/keys/<prefix>-ssh-key ubuntu@<java_public_ip>

# user_data 完了確認
tail /var/log/user-data.log

# Java アプリのビルドと起動
cd ~/apps/java-app
./mvnw -q package -DskipTests
PYTHON_API_URL=http://<python_private_ip>:8000 \
  nohup java -jar target/*.jar > /var/log/<prefix>/java-app.log 2>&1 &
```

### 6. 動作確認

```bash
# /hello エンドポイント（正常系）
curl http://<java_public_ip>:8080/hello
# → {"message":"Hello from Python","timestamp":"..."}

# /timeout エンドポイント（30% 確率で 504）
for i in $(seq 1 10); do
  curl -s -o /dev/null -w "%{http_code}\n" http://<java_public_ip>:8080/timeout
done

# /error エンドポイント（20% 確率で 500）
for i in $(seq 1 10); do
  curl -s -o /dev/null -w "%{http_code}\n" http://<java_public_ip>:8080/error
done
```

ブラウザで `http://<java_public_ip>:8080/` を開くと Web UI からも各エンドポイントを操作できます。

---

## After フェーズ: SSI による Datadog 計装

各ステップのコピペコマンドは `terraform output demo_step2_install_agent` 〜 `demo_step4_after` で取得できます。以下は概要です。

### Step 2: Datadog Agent インストール（SSI）

Datadog UI > Organization Settings > API Keys からキーをコピーしてから実行してください。

```bash
# [Bastion EC2] EC2 内で実行
export DD_API_KEY="<DD_API_KEY>"
export DD_SITE="datadoghq.com"
export DD_ENV="<prefix>"
export DD_APM_INSTRUMENTATION_ENABLED=host
export DD_APM_INSTRUMENTATION_LIBRARIES=java:1
bash -c "$(curl -L https://install.datadoghq.com/scripts/install_script_agent7.sh)"
```

```bash
# [Python EC2] EC2 内で実行
export DD_API_KEY="<DD_API_KEY>"
export DD_SITE="datadoghq.com"
export DD_ENV="<prefix>"
export DD_APM_INSTRUMENTATION_ENABLED=host
export DD_APM_INSTRUMENTATION_LIBRARIES=python:3
bash -c "$(curl -L https://install.datadoghq.com/scripts/install_script_agent7.sh)"
```

### Step 3: ログ収集設定

各 EC2 で Agent 設定ファイル（`/etc/datadog-agent/conf.d/<lang>.d/conf.yaml`）にログファイル定義を追加し、`logs_enabled: true` を有効化します（`demo_step3_configure_logs` 参照）。

### Step 4: After 状態でアプリ再起動

SSI が自動計装するため、アプリの再起動だけで APM 計装が完了します。**コード変更は不要です。**

```bash
# [Bastion EC2] SSI が JAVA_TOOL_OPTIONS 経由で -javaagent を自動注入
pkill -f 'java.*jar' || true
sleep 2
cd ~/apps/java-app
PYTHON_API_URL=http://<python_private_ip>:8000 \
DD_SERVICE=<prefix>-java-front DD_ENV=<prefix> DD_LOGS_INJECTION=true \
  nohup java -jar target/*.jar > /var/log/<prefix>/java-app.log 2>&1 &
```

```bash
# [Python EC2] venv 利用のため ddtrace-run 経由で計装
pkill -f 'python3 app.py' || true
sleep 2
cd ~/apps/python-app
source venv/bin/activate
set -a; source /home/ubuntu/.env; set +a
DD_SERVICE=<prefix>-py-back DD_ENV=<prefix> DD_LOGS_INJECTION=true \
  nohup ddtrace-run python3 app.py > /var/log/<prefix>/python-app.log 2>&1 &
```

---

## ディレクトリ構成

```
dd-observability-pov/
├── README.md                         # このファイル
├── apps/
│   ├── java-app/                     # Spring Boot アプリ
│   │   ├── pom.xml
│   │   ├── mvnw
│   │   └── src/
│   └── python-app/                   # Flask アプリ
│       ├── app.py
│       └── requirements.txt
├── terraform/                        # 標準構成（Ubuntu 22.04 / 2 台）
│   ├── README.md
│   ├── main.tf
│   ├── base.tf                       # VPC / Subnet / IGW / NAT / IAM / SG
│   ├── data.tf                       # Ubuntu AMI 取得
│   ├── ec2.tf                        # Java EC2 (Public) + Python EC2 (Private)
│   ├── sg.tf / rds.tf / upload.tf / outputs.tf
│   ├── keypair.tf / variables.tf / locals.tf.example
│   ├── terraform.tfvars.example
│   ├── keys/                         # 生成済み SSH キー（gitignore 対象）
│   └── scripts/
│       ├── java_userdata.sh
│       └── python_userdata.sh
└── terraform/single-host/            # single-host 構成（Amazon Linux 2023 / 1 台）
    ├── README.md
    ├── main.tf
    ├── base.tf                       # VPC / Subnet / IGW（NAT なし）/ IAM / SG
    ├── data.tf                       # Amazon Linux 2023 AMI 取得
    ├── ec2.tf                        # App EC2 (Public, Java + Python 同居)
    ├── sg.tf / rds.tf / upload.tf / outputs.tf
    ├── keypair.tf / variables.tf / locals.tf.example
    ├── terraform.tfvars.example
    ├── keys/                         # 生成済み SSH キー（gitignore 対象）
    └── scripts/
        └── userdata.sh               # dnf ベース（Corretto 21 + Python 3）
```

---

## ログ設計

### Java（JSON 形式）

`logstash-logback-encoder` により JSON 形式でファイル出力。
SSI で Agent インストール後、dd-java-agent が `dd.trace_id` / `dd.span_id` を自動注入します。

```json
{"@timestamp":"...","level":"INFO","logger_name":"...","message":"...","dd.trace_id":"...","dd.span_id":"..."}
```

Agent 設定（`source: java` で Java ログパイプラインが自動適用）:

```yaml
logs:
  - type: file
    path: /var/log/<prefix>/java-app.log
    service: <prefix>-java-front
    source: java
    sourcecategory: sourcecode
```

### Python（テキスト形式）

Datadog 公式推奨フォーマットでファイル出力。
SSI 未導入（Before 状態）では `dd.trace_id` 等に `0` が入り、SSI 導入後（After 状態）は `ddtrace-run` が本物の trace_id / span_id を自動注入します。

```
2026-04-25 10:00:00,000 INFO app [app.py:42] [dd.service=<prefix>-py-back dd.env=<prefix> dd.version= dd.trace_id=123 dd.span_id=456] - GET /api/data called
```

Agent 設定（`source: python` で Python ログパイプラインが自動適用）:

```yaml
logs:
  - type: file
    path: /var/log/<prefix>/python-app.log
    service: <prefix>-py-back
    source: python
    sourcecategory: sourcecode
```
