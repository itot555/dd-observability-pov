# Analytics エンドポイント追加 — 稼働中環境への反映手順（single-host）

`terraform/single-host/` で構築済みの EC2 が稼働中の状態に対して、Analytics エンドポイントを追加する手順です。

---

## 変更ファイル

| ファイル | 変更内容 |
|---------|---------|
| `apps/python-app/app.py` | `init_analytics_db()` + `/api/analytics` + `/api/analytics/summary` 追加 |
| `apps/java-app/src/.../AnalyticsController.java` | 新規作成（`/analytics` `/analytics/summary`） |
| `apps/java-app/src/main/resources/static/index.html` | エンドポイント選択肢 + Analytics 負荷生成ボタン追加 |

---

## Step 1: アプリファイルを EC2 に再アップロード

`terraform/single-host/` ディレクトリから実行します。

```bash
# Terraform で upload.tf の null_resource を再実行（AWS リソースは変更されません）
terraform apply -target=null_resource.upload_apps
```

または手動 SCP（`terraform apply` を使いたくない場合）:

```bash
KEY=keys/<name_prefix>-ssh-key
EC2=$(terraform output -raw ec2_public_ip)

# Python app
scp -i $KEY \
  ../../apps/python-app/app.py \
  ec2-user@$EC2:~/apps/python-app/app.py

# Java app — AnalyticsController（新規ファイル、ディレクトリが存在することを確認）
scp -i $KEY \
  ../../apps/java-app/src/main/java/com/example/javaapp/controller/AnalyticsController.java \
  ec2-user@$EC2:~/apps/java-app/src/main/java/com/example/javaapp/controller/AnalyticsController.java

# Web UI
scp -i $KEY \
  ../../apps/java-app/src/main/resources/static/index.html \
  ec2-user@$EC2:~/apps/java-app/src/main/resources/static/index.html
```

---

## Step 2: EC2 に SSH 接続

```bash
ssh -i keys/<name_prefix>-ssh-key ec2-user@$(terraform output -raw ec2_public_ip)
```

---

## Step 3: Python アプリの再起動

```bash
pkill -f 'python3 app.py' || true
sleep 2
cd ~/apps/python-app
source venv/bin/activate
set -a; source /home/ec2-user/.env; set +a
```

**Before 状態（Datadog Agent 未導入）:**

```bash
LOG_DIR=/var/log/<name_prefix> \
  nohup python3 app.py > /var/log/<name_prefix>/python-app.log 2>&1 &
```

**After 状態（SSI 導入済み）:**

```bash
LOG_DIR=/var/log/<name_prefix> \
  DD_SERVICE=<name_prefix>-py-back \
  DD_ENV=<name_prefix> \
  DD_LOGS_INJECTION=true \
  nohup ddtrace-run python3 app.py > /var/log/<name_prefix>/python-app.log 2>&1 &
```

---

## Step 4: Java アプリのリビルドと再起動

`AnalyticsController.java` を追加したため、Maven でリビルドが必要です。

```bash
pkill -f 'java.*jar' || true
sleep 2
cd ~/apps/java-app
./mvnw -q package -DskipTests
```

**Before 状態:**

```bash
PYTHON_API_URL=http://localhost:8000 \
  LOGGING_FILE_NAME=/var/log/<name_prefix>/java-app.log \
  nohup java -jar target/*.jar > /var/log/<name_prefix>/java-app.log 2>&1 &
```

**After 状態（SSI 導入済み）:**

```bash
PYTHON_API_URL=http://localhost:8000 \
  LOGGING_FILE_NAME=/var/log/<name_prefix>/java-app.log \
  DD_SERVICE=<name_prefix>-java-front \
  DD_ENV=<name_prefix> \
  DD_LOGS_INJECTION=true \
  nohup java -jar target/*.jar > /var/log/<name_prefix>/java-app.log 2>&1 &
```

---

## Step 5: 動作確認

```bash
EC2_IP=$(terraform output -raw ec2_public_ip)   # ローカルで実行

# 基本確認
curl http://$EC2_IP:8080/analytics
curl http://$EC2_IP:8080/analytics/summary

# エラー率確認（10 回中 ~1〜2 回が 500 になることを確認）
for i in {1..10}; do
  curl -s -o /dev/null -w "%{http_code}\n" http://$EC2_IP:8080/analytics
done
```

期待値:

| エンドポイント | 正常時 | エラー条件 | エラー率 |
|-------------|-------|-----------|---------|
| `GET /analytics` | `{"user_id":..., "growth_rate":...}` | `user_id % 7 == 0`（7 名）でゼロ除算 | ~14% |
| `GET /analytics/summary` | `{"cohort":..., "results":[...]}` | `cohort == 0`（1/7 の確率）で全員ゼロ除算 | ~14% |

---

## エラーの仕組み（APM デモ用）

`order_monthly_stats` テーブルで `user_id % 7 == 0` の 7 名（user_id: 7, 14, 21, 28, 35, 42, 49）は
先月データが存在しない設計になっています。

```python
prev_amount = 0  # 先月データなし → COALESCE が 0 を返す
growth_rate = (current_amount - prev_amount) / prev_amount * 100
# → ZeroDivisionError → Flask 500 → Java がリトライ → 再度 500
```

APM 上では Java の `/analytics` span 内に Python への HTTP 呼び出しが **2 回**（リトライ含む）観測されます。
