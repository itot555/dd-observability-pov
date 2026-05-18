# terraform/

Datadog Observability サンプル環境（Java front-end + Python back-end + PostgreSQL）を**単独で `terraform apply` だけで**構築できるスタンドアロン構成です。ネットワーク・IAM・セキュリティグループも含めて本ディレクトリ内で完結します。

## 前提条件

- Terraform `~> 1.10`
- AWS クレデンシャル設定済み（`ap-northeast-1` で動作確認済）
- Datadog アカウントと API Key（後段の Agent インストール手順で使用）

## セットアップ

### 1. locals.tf の準備

`locals.tf` は `.gitignore` 対象です。テンプレートからコピーして編集してください。

```bash
cp locals.tf.example locals.tf
```

### 2. terraform.tfvars の準備（任意）

デフォルト値のままで動作しますが、`name_prefix` や `allowed_ip` を変更したい場合は `terraform.tfvars` を作成してください。

```bash
cp terraform.tfvars.example terraform.tfvars
# 必要箇所を編集
```

### 3. 実行

```bash
terraform init
terraform plan
terraform apply
```

## ファイル構成

| ファイル | 役割 |
|---------|------|
| `main.tf` | Terraform バージョン・プロバイダーバージョン制約 |
| `provider.tf` | AWS / TLS / local / null / random プロバイダー設定 |
| `variables.tf` | 入力変数定義（`name_prefix` / ネットワーク CIDR / インスタンスタイプ等） |
| `locals.tf` | 共通タグ・`name_prefix` エイリアス（**gitignore 対象**） |
| `locals.tf.example` | `locals.tf` のテンプレート |
| `base.tf` | スタンドアロン化のための基盤 — VPC / Subnet / IGW / NAT / RT / bastion-sg / bastion IAM |
| `data.tf` | Ubuntu 22.04 AMI 取得 |
| `keypair.tf` | TLS RSA 4096bit キーペア生成・ローカル書き出し・AWS 登録 |
| `ec2.tf` | EC2 インスタンス（Java front-end + Python back-end） |
| `sg.tf` | Python SG（:8000）・RDS SG（PostgreSQL:5432） |
| `rds.tf` | RDS PostgreSQL（ハンズオン用に最小構成） |
| `upload.tf` | `../apps/` を EC2 に転送する null_resource |
| `outputs.tf` | SSH コマンド・Spring Boot URL・デモ手順 |
| `terraform.tfvars.example` | `terraform.tfvars` のテンプレート |
| `scripts/java_userdata.sh` | Java EC2 用 user_data |
| `scripts/python_userdata.sh` | Python EC2 用 user_data |
| `keys/` | 生成済み SSH キー（**gitignore 対象**） |

## セキュリティ設計

| 項目 | 対応 |
|-----|------|
| SSH キー | TLS プロバイダーで動的生成。`keys/` は `.gitignore` 対象 |
| IMDSv2 | 全 EC2 で `http_tokens = "required"` を強制 |
| EBS 暗号化 | 全ボリュームで `encrypted = true` |
| RDS 暗号化 | `storage_encrypted = true` |
| インバウンド制限 | SSH / 8080 は `allowed_ip` で許可元 CIDR を制限可能 |
| インスタンスプロファイル | `AmazonSSMManagedInstanceCore` のみ付与（最小権限） |
| State ファイル | ローカルバックエンド。`terraform.tfstate` は `.gitignore` 対象 |

## gitignore 対象ファイル

```
terraform.tfstate      # AWS リソース情報・秘密鍵が含まれる
terraform.tfstate.*
.terraform/
.terraform.lock.hcl
terraform.tfvars       # 環境固有値
locals.tf              # 個人情報（氏名・メールアドレス）
keys/                  # SSH 秘密鍵・公開鍵
```

## 主要変数

| 変数名 | デフォルト | 説明 |
|-------|----------|------|
| `region` | `ap-northeast-1` | AWS リージョン |
| `name_prefix` | `pov` | リソース名・サービス名のプレフィックス |
| `vpc_cidr` | `10.0.0.0/16` | VPC CIDR |
| `public_subnet_cidrs` | `["10.0.101.0/24", "10.0.102.0/24"]` | パブリックサブネット CIDR |
| `private_subnet_cidrs` | `["10.0.1.0/24", "10.0.2.0/24"]` | プライベートサブネット CIDR |
| `allowed_ip` | `["0.0.0.0/0"]` | SSH/8080 を許可する送信元 CIDR |
| `java_ec2_instance_type` | `t3.medium` | Java EC2 インスタンスタイプ |
| `python_ec2_instance_type` | `t3.small` | Python EC2 インスタンスタイプ |
| `java_ec2_volume_size` | `30` | Java EC2 ルートボリューム (GB) |
| `python_ec2_volume_size` | `20` | Python EC2 ルートボリューム (GB) |
| `db_instance_class` | `db.t4g.micro` | RDS インスタンスクラス |
| `db_engine_version` | `17.10` | PostgreSQL エンジンバージョン |
| `db_allocated_storage` | `20` | RDS 割当ストレージ (GB) |

## 主要出力値

| 出力名 | 内容 |
|-------|------|
| `java_ec2_public_ip` | Java front-end のパブリック IP |
| `java_ec2_ssh_command` | Java EC2 への SSH コマンド |
| `java_ec2_spring_boot_url` | Spring Boot アクセス URL |
| `python_ec2_private_ip` | Python back-end のプライベート IP |
| `python_ec2_ssh_command` | Python EC2 への ProxyJump SSH コマンド |
| `rds_endpoint` / `rds_port` / `rds_db_name` / `rds_username` | RDS PostgreSQL の接続情報 |
| `demo_step1_before` … `demo_step4_after` | ハンズオン手順（Before → Agent → ログ → After）コピペ用 |

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
| [aws_eip.nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_iam_instance_profile.bastion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.bastion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.bastion_ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_instance.java](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_instance.python](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_key_pair.ec2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/key_pair) | resource |
| [aws_nat_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway) | resource |
| [aws_route_table.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_security_group.bastion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.python](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.rds](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [local_file.public_key](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_sensitive_file.private_key](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/sensitive_file) | resource |
| [null_resource.deploy_env](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.upload_java_app](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.upload_python_app](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [random_password.db](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [tls_private_key.ec2](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [aws_ami.ubuntu](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_allowed_ip"></a> [allowed\_ip](#input\_allowed\_ip) | SSH (22) および Spring Boot (8080) へのインバウンドを許可する送信元 CIDR 一覧。<br/>デフォルトは 0.0.0.0/0（全公開）ですが、本番検証時はオフィス IP 等に絞ってください。 | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_db_allocated_storage"></a> [db\_allocated\_storage](#input\_db\_allocated\_storage) | Allocated storage in GB for RDS (gp3, minimum 20) | `number` | `20` | no |
| <a name="input_db_engine_version"></a> [db\_engine\_version](#input\_db\_engine\_version) | PostgreSQL engine version on RDS (latest available 17.x minor) | `string` | `"17.10"` | no |
| <a name="input_db_instance_class"></a> [db\_instance\_class](#input\_db\_instance\_class) | RDS instance class (Graviton t4g.micro for minimum cost) | `string` | `"db.t4g.micro"` | no |
| <a name="input_java_ec2_instance_type"></a> [java\_ec2\_instance\_type](#input\_java\_ec2\_instance\_type) | EC2 instance type for Java/Spring Boot server | `string` | `"t3.medium"` | no |
| <a name="input_java_ec2_volume_size"></a> [java\_ec2\_volume\_size](#input\_java\_ec2\_volume\_size) | Root volume size in GB for Java EC2 | `number` | `30` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | すべてのリソース名・タグの先頭に付与する識別子。<br/>パートナー様ごとに一意な名前（例: acme-poc）に変更してご利用ください。<br/>なお EC2 内のログディレクトリやサービス名にも反映されます。 | `string` | `"pov"` | no |
| <a name="input_private_subnet_cidrs"></a> [private\_subnet\_cidrs](#input\_private\_subnet\_cidrs) | Private subnet CIDR blocks (2 つ以上必須 — RDS DB Subnet Group の要件) | `list(string)` | <pre>[<br/>  "10.0.1.0/24",<br/>  "10.0.2.0/24"<br/>]</pre> | no |
| <a name="input_public_subnet_cidrs"></a> [public\_subnet\_cidrs](#input\_public\_subnet\_cidrs) | Public subnet CIDR blocks (2 つ以上必須) | `list(string)` | <pre>[<br/>  "10.0.101.0/24",<br/>  "10.0.102.0/24"<br/>]</pre> | no |
| <a name="input_python_ec2_instance_type"></a> [python\_ec2\_instance\_type](#input\_python\_ec2\_instance\_type) | EC2 instance type for Python server | `string` | `"t3.small"` | no |
| <a name="input_python_ec2_volume_size"></a> [python\_ec2\_volume\_size](#input\_python\_ec2\_volume\_size) | Root volume size in GB for Python EC2 | `number` | `20` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region | `string` | `"ap-northeast-1"` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | VPC CIDR block | `string` | `"10.0.0.0/16"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_demo_step1_before"></a> [demo\_step1\_before](#output\_demo\_step1\_before) | Step 1: Start apps in Before state (no Datadog) |
| <a name="output_demo_step2_install_agent"></a> [demo\_step2\_install\_agent](#output\_demo\_step2\_install\_agent) | Step 2: Install Datadog Agent with SSI on both EC2 instances |
| <a name="output_demo_step3_configure_logs"></a> [demo\_step3\_configure\_logs](#output\_demo\_step3\_configure\_logs) | Step 3: Configure log collection on both EC2 instances |
| <a name="output_demo_step4_after"></a> [demo\_step4\_after](#output\_demo\_step4\_after) | Step 4: Restart apps in After state (APM auto-instrumented via SSI) |
| <a name="output_java_ec2_instance_id"></a> [java\_ec2\_instance\_id](#output\_java\_ec2\_instance\_id) | Java front-end EC2 instance ID |
| <a name="output_java_ec2_public_ip"></a> [java\_ec2\_public\_ip](#output\_java\_ec2\_public\_ip) | Java front-end EC2 public IP address |
| <a name="output_java_ec2_spring_boot_url"></a> [java\_ec2\_spring\_boot\_url](#output\_java\_ec2\_spring\_boot\_url) | URL to access the Spring Boot application |
| <a name="output_java_ec2_ssh_command"></a> [java\_ec2\_ssh\_command](#output\_java\_ec2\_ssh\_command) | SSH command to connect to the Java front-end EC2 |
| <a name="output_python_ec2_instance_id"></a> [python\_ec2\_instance\_id](#output\_python\_ec2\_instance\_id) | Python back-end EC2 instance ID |
| <a name="output_python_ec2_private_ip"></a> [python\_ec2\_private\_ip](#output\_python\_ec2\_private\_ip) | Python back-end EC2 private IP address |
| <a name="output_python_ec2_ssh_command"></a> [python\_ec2\_ssh\_command](#output\_python\_ec2\_ssh\_command) | SSH command to connect to the Python back-end EC2 via the bastion EC2 as a jump host |
| <a name="output_rds_db_name"></a> [rds\_db\_name](#output\_rds\_db\_name) | RDS PostgreSQL initial database name |
| <a name="output_rds_endpoint"></a> [rds\_endpoint](#output\_rds\_endpoint) | RDS PostgreSQL endpoint (hostname) |
| <a name="output_rds_port"></a> [rds\_port](#output\_rds\_port) | RDS PostgreSQL port |
| <a name="output_rds_username"></a> [rds\_username](#output\_rds\_username) | RDS PostgreSQL master username |
<!-- END_TF_DOCS -->