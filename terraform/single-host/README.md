# terraform/single-host/

Datadog Observability サンプル環境（Java front-end + Python back-end + PostgreSQL）を **1 台の EC2（Amazon Linux 2023）** に集約したコスト最適化構成です。
`terraform apply` のみで VPC・EC2・RDS が立ち上がります。

> **terraform/ との違い**
> | 項目 | `terraform/`（2 台構成） | `terraform/single-host/`（本ディレクトリ） |
> |------|------------------------|--------------------------------------|
> | EC2 台数 | 2 台（Public + Private） | **1 台（Public のみ）** |
> | OS | Ubuntu 22.04 | **Amazon Linux 2023** |
> | デフォルトユーザー | `ubuntu` | **`ec2-user`** |
> | NAT Gateway | あり | **なし（コスト削減）** |
> | アプリ間通信 | `http://<private_ip>:8000` | **`http://localhost:8000`** |

---

## アーキテクチャ

```
Internet
    │
    ▼  :8080
┌───────────────────────────────────────────┐
│  <name_prefix>-app  (Public Subnet)       │
│  Amazon Linux 2023 / t3.medium            │
│  ┌────────────────┐   ┌────────────────┐  │
│  │  Spring Boot   │──▶│  Flask         │  │
│  │  Java 21       │   │  Python 3      │  │
│  │  :8080         │   │  :8000 (local) │  │
│  └────────────────┘   └────────────────┘  │
└───────────────────────────────────────────┘
    │ :5432
    ▼
┌─────────────────────────────┐
│  RDS PostgreSQL (Private)   │
│  db.t4g.micro / gp3 20GB    │
└─────────────────────────────┘
```

Private Subnet は RDS DB Subnet Group の要件（2 AZ 必須）を満たすためだけに存在し、NAT Gateway は持ちません。

---

## 前提条件

- Terraform `~> 1.10`
- AWS クレデンシャルが設定済みであること（`ap-northeast-1` で動作確認）
- Datadog アカウントと API Key

---

## セットアップ

### 1. locals.tf の準備

```bash
cd terraform/single-host
cp locals.tf.example locals.tf
# Owner / Email 等を編集
```

### 2. terraform.tfvars の準備（任意）

デフォルト値のままで動作しますが、`name_prefix` / `allowed_ip` / インスタンスタイプ等を変更したい場合は `terraform.tfvars` を作成してください。

```bash
cp terraform.tfvars.example terraform.tfvars
# 必要箇所のコメントを外して編集
```

`name_prefix`（デフォルト: `pov`）は、全リソース名・タグ・Datadog の `service` / `env` の先頭に付与されます。

### 3. Terraform 実行

```bash
terraform init
terraform plan
terraform apply
```

apply 完了後に以下のような値が出力されます。

```
ec2_public_ip      = "x.x.x.x"
ec2_ssh_command    = "ssh -i keys/<prefix>-ssh-key ec2-user@x.x.x.x"
ec2_spring_boot_url = "http://x.x.x.x:8080"
```

各ステップのコピペ用コマンドは output から取得できます。

```bash
terraform output demo_step1_before          # Before 状態でアプリ起動
terraform output demo_step2_install_agent   # Datadog Agent インストール（SSI）
terraform output demo_step3_configure_logs  # ログ収集設定
terraform output demo_step4_after           # After 状態でアプリ再起動（APM 計装済）
```

### 4. アプリの起動（Before 状態）

```bash
# EC2 に SSH 接続
ssh -i keys/<prefix>-ssh-key ec2-user@<ec2_public_ip>

# user_data 完了確認（"Bootstrapping complete." が末尾に表示されれば OK）
tail /var/log/user-data.log

# Python アプリ起動
cd ~/apps/python-app
python3 -m venv venv
source venv/bin/activate
pip install -q -r requirements.txt
set -a; source /home/ec2-user/.env; set +a
LOG_DIR=/var/log/<prefix> nohup python3 app.py > /var/log/<prefix>/python-app.log 2>&1 &

# Java アプリのビルドと起動
cd ~/apps/java-app
./mvnw -q package -DskipTests
PYTHON_API_URL=http://localhost:8000 \
LOGGING_FILE_NAME=/var/log/<prefix>/java-app.log \
nohup java -jar target/*.jar > /var/log/<prefix>/java-app.log 2>&1 &
```

### 5. 動作確認

```bash
curl http://<ec2_public_ip>:8080/hello
curl http://<ec2_public_ip>:8080/db/normal
curl http://<ec2_public_ip>:8080/db/n1
curl http://<ec2_public_ip>:8080/db/long-run
```

ブラウザで `http://<ec2_public_ip>:8080/` を開くと Web UI から各エンドポイントを操作できます。

---

## After フェーズ: SSI による Datadog 計装

### Step 2: Datadog Agent インストール（SSI）

Java と Python の SSI を **1 コマンドで同時に有効化** できます。

```bash
export DD_API_KEY="<DD_API_KEY>"
export DD_SITE="datadoghq.com"
export DD_ENV="<prefix>"
export DD_APM_INSTRUMENTATION_ENABLED=host
export DD_APM_INSTRUMENTATION_LIBRARIES="java:1,python:3"
bash -c "$(curl -L https://install.datadoghq.com/scripts/install_script_agent7.sh)"
```

### Step 3: ログ収集設定

`logs_enabled: true` を有効化し、Java / Python それぞれのログファイル定義を追加します（`demo_step3_configure_logs` 参照）。

### Step 4: After 状態でアプリ再起動

```bash
# Java（SSI が JAVA_TOOL_OPTIONS 経由で -javaagent を自動注入）
pkill -f 'java.*jar' || true
sleep 2
cd ~/apps/java-app
PYTHON_API_URL=http://localhost:8000 \
LOGGING_FILE_NAME=/var/log/<prefix>/java-app.log \
DD_SERVICE=<prefix>-java-front DD_ENV=<prefix> DD_LOGS_INJECTION=true \
nohup java -jar target/*.jar > /var/log/<prefix>/java-app.log 2>&1 &

# Python（venv 利用のため ddtrace-run 経由で計装）
pkill -f 'python3 app.py' || true
sleep 2
cd ~/apps/python-app
source venv/bin/activate
set -a; source /home/ec2-user/.env; set +a
LOG_DIR=/var/log/<prefix> DD_SERVICE=<prefix>-py-back DD_ENV=<prefix> DD_LOGS_INJECTION=true \
nohup ddtrace-run python3 app.py > /var/log/<prefix>/python-app.log 2>&1 &
```

---

## ファイル構成

| ファイル | 役割 |
|---------|------|
| `main.tf` / `provider.tf` | Terraform バージョン・プロバイダー設定 |
| `variables.tf` | 入力変数（`ec2_instance_type` / `ec2_volume_size` に統合済み） |
| `locals.tf` / `locals.tf.example` | 共通タグ（`locals.tf` は `.gitignore` 対象） |
| `base.tf` | VPC / Subnet / IGW / Public Route Table / app-sg / IAM |
| `data.tf` | Amazon Linux 2023 AMI 参照 |
| `keypair.tf` | TLS RSA 4096bit キーペア（`keys/` に保存、gitignore 対象） |
| `ec2.tf` | `<name_prefix>-app`（Public Subnet 単一インスタンス） |
| `sg.tf` | `<name_prefix>-rds-sg` のみ |
| `rds.tf` | RDS PostgreSQL / `.env` を直接 SSH で配布 |
| `upload.tf` | java-app / python-app を同一 EC2 に転送 |
| `outputs.tf` | SSH コマンド / Spring Boot URL / demo_step1〜4 |
| `terraform.tfvars.example` | `terraform.tfvars` のテンプレート |
| `scripts/userdata.sh` | dnf ベース（Corretto 21 + Python 3） |

## セキュリティ設計

| 項目 | 対応 |
|-----|------|
| SSH キー | TLS プロバイダーで動的生成。`keys/` は `.gitignore` 対象 |
| IMDSv2 | `http_tokens = "required"` を強制 |
| EBS 暗号化 | `encrypted = true` |
| RDS 暗号化 | `storage_encrypted = true` |
| インバウンド制限 | SSH / 8080 は `allowed_ip` で許可元 CIDR を制限可能 |
| Python API (8000) | 外部非公開。Java から `localhost` 経由でのみアクセス |
| インスタンスプロファイル | `AmazonSSMManagedInstanceCore` のみ付与（最小権限） |

## gitignore 対象ファイル

```
terraform.tfstate      # AWS リソース情報・秘密鍵が含まれる
terraform.tfstate.*
.terraform/
terraform.tfvars       # 環境固有値（IP アドレス等）
locals.tf              # 個人情報（氏名・メールアドレス等）
keys/                  # SSH 秘密鍵・公開鍵
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.10 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.42.0 |
| <a name="requirement_local"></a> [local](#requirement\_local) | ~> 2.5 |
| <a name="requirement_null"></a> [null](#requirement\_null) | ~> 3.2 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | ~> 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.42.0 |
| <a name="provider_local"></a> [local](#provider\_local) | 2.9.0 |
| <a name="provider_null"></a> [null](#provider\_null) | 3.3.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.9.0 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | 4.3.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_db_instance.postgres](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance) | resource |
| [aws_db_subnet_group.postgres](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group) | resource |
| [aws_iam_instance_profile.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.app_ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_instance.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_key_pair.ec2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/key_pair) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_security_group.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.rds](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [local_file.public_key](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_sensitive_file.private_key](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/sensitive_file) | resource |
| [null_resource.deploy_env](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.upload_apps](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [random_password.db](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [tls_private_key.ec2](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [aws_ami.al2023](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_allowed_ip"></a> [allowed\_ip](#input\_allowed\_ip) | SSH (22) および Spring Boot (8080) へのインバウンドを許可する送信元 CIDR 一覧。<br/>デフォルトは 0.0.0.0/0（全公開）ですが、環境に応じて IP を絞ってください。 | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_db_allocated_storage"></a> [db\_allocated\_storage](#input\_db\_allocated\_storage) | Allocated storage in GB for RDS (gp3, minimum 20) | `number` | `20` | no |
| <a name="input_db_engine_version"></a> [db\_engine\_version](#input\_db\_engine\_version) | PostgreSQL engine version on RDS (latest available 17.x minor) | `string` | `"17.10"` | no |
| <a name="input_db_instance_class"></a> [db\_instance\_class](#input\_db\_instance\_class) | RDS instance class (Graviton t4g.micro for minimum cost) | `string` | `"db.t4g.micro"` | no |
| <a name="input_ec2_instance_type"></a> [ec2\_instance\_type](#input\_ec2\_instance\_type) | EC2 instance type (Java + Python を同居させるため t3.medium 以上を推奨) | `string` | `"t3.medium"` | no |
| <a name="input_ec2_volume_size"></a> [ec2\_volume\_size](#input\_ec2\_volume\_size) | Root volume size in GB | `number` | `30` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | すべてのリソース名・タグの先頭に付与する識別子。<br/>パートナー様ごとに一意な名前（例: acme-poc）に変更してご利用ください。<br/>なお EC2 内のログディレクトリやサービス名にも反映されます。 | `string` | `"pov"` | no |
| <a name="input_private_subnet_cidrs"></a> [private\_subnet\_cidrs](#input\_private\_subnet\_cidrs) | Private subnet CIDR blocks (2 つ以上必須 — RDS DB Subnet Group の要件) | `list(string)` | <pre>[<br/>  "10.0.1.0/24",<br/>  "10.0.2.0/24"<br/>]</pre> | no |
| <a name="input_public_subnet_cidrs"></a> [public\_subnet\_cidrs](#input\_public\_subnet\_cidrs) | Public subnet CIDR blocks (2 つ以上必須) | `list(string)` | <pre>[<br/>  "10.0.101.0/24",<br/>  "10.0.102.0/24"<br/>]</pre> | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region | `string` | `"ap-northeast-1"` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | VPC CIDR block | `string` | `"10.0.0.0/16"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_demo_step1_before"></a> [demo\_step1\_before](#output\_demo\_step1\_before) | Step 1: Start apps in Before state (no Datadog) |
| <a name="output_demo_step2_install_agent"></a> [demo\_step2\_install\_agent](#output\_demo\_step2\_install\_agent) | Step 2: Install Datadog Agent with SSI on the App EC2 |
| <a name="output_demo_step3_configure_logs"></a> [demo\_step3\_configure\_logs](#output\_demo\_step3\_configure\_logs) | Step 3: Configure log collection on the App EC2 |
| <a name="output_demo_step4_after"></a> [demo\_step4\_after](#output\_demo\_step4\_after) | Step 4: Restart apps in After state (APM auto-instrumented via SSI) |
| <a name="output_ec2_instance_id"></a> [ec2\_instance\_id](#output\_ec2\_instance\_id) | App EC2 instance ID |
| <a name="output_ec2_public_ip"></a> [ec2\_public\_ip](#output\_ec2\_public\_ip) | App EC2 public IP address |
| <a name="output_ec2_spring_boot_url"></a> [ec2\_spring\_boot\_url](#output\_ec2\_spring\_boot\_url) | URL to access the Spring Boot application |
| <a name="output_ec2_ssh_command"></a> [ec2\_ssh\_command](#output\_ec2\_ssh\_command) | SSH command to connect to the App EC2 |
| <a name="output_rds_db_name"></a> [rds\_db\_name](#output\_rds\_db\_name) | RDS PostgreSQL initial database name |
| <a name="output_rds_endpoint"></a> [rds\_endpoint](#output\_rds\_endpoint) | RDS PostgreSQL endpoint (hostname) |
| <a name="output_rds_port"></a> [rds\_port](#output\_rds\_port) | RDS PostgreSQL port |
| <a name="output_rds_username"></a> [rds\_username](#output\_rds\_username) | RDS PostgreSQL master username |
<!-- END_TF_DOCS -->