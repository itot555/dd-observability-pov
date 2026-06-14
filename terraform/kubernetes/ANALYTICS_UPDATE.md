# Analytics エンドポイント追加 — 稼働中環境への反映手順（kubernetes）

`terraform/kubernetes/` で構築済みの EKS 環境が稼働中の状態に対して、Analytics エンドポイントを追加する手順です。

---

## 変更ファイル

| ファイル | 変更内容 |
|---------|---------|
| `apps/kubernetes/python-app/app.py` | `init_analytics_db()` + `/api/analytics` + `/api/analytics/summary` 追加 |
| `apps/kubernetes/java-app/src/.../AnalyticsController.java` | 新規作成（`/analytics` `/analytics/summary`） |
| `apps/kubernetes/java-app/src/main/resources/static/index.html` | エンドポイント選択肢 + Analytics 負荷生成ボタン追加 |

---

## 前提確認

```bash
# EKS クラスターへの接続確認
kubectl get nodes
kubectl get pods -n <name_prefix>
```

---

## Step 1: Docker イメージの再ビルドと ECR プッシュ

`terraform/kubernetes/` ディレクトリから変数を取得して実行します。

```bash
cd terraform/kubernetes

JAVA_IMAGE=$(terraform output -raw ecr_java_app_uri)
PYTHON_IMAGE=$(terraform output -raw ecr_python_app_uri)
REGION=$(terraform output -raw eks_cluster_name | xargs -I{} aws eks describe-cluster --name {} --query 'cluster.arn' --output text 2>/dev/null | cut -d: -f4 || echo "ap-northeast-1")
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

# ECR ログイン
aws ecr get-login-password --region ap-northeast-1 | \
  podman login --username AWS --password-stdin \
    $ACCOUNT.dkr.ecr.ap-northeast-1.amazonaws.com

# Python イメージ再ビルド（app.py の変更を反映）
cd ../../apps/kubernetes/python-app
podman build --platform linux/amd64 -t $PYTHON_IMAGE:latest .
podman push $PYTHON_IMAGE:latest

# Java イメージ再ビルド（AnalyticsController.java の追加を反映）
cd ../java-app
podman build --platform linux/amd64 -t $JAVA_IMAGE:latest .
podman push $JAVA_IMAGE:latest
```

---

## Step 2: Deployment の再適用

`terraform/kubernetes/` ディレクトリから実行します。

```bash
cd ../../terraform/kubernetes

NAMESPACE=<name_prefix>
NAME_PREFIX=<name_prefix>
JAVA_IMAGE=$(terraform output -raw ecr_java_app_uri):latest
PYTHON_IMAGE=$(terraform output -raw ecr_python_app_uri):latest

# Python Deployment 更新
sed "s|\${NAMESPACE}|${NAMESPACE}|g; s|\${NAME_PREFIX}|${NAME_PREFIX}|g; s|\${PYTHON_IMAGE}|${PYTHON_IMAGE}|g" \
  manifests/python-app-deployment.yaml | kubectl apply -f -

# Java Deployment 更新
sed "s|\${NAMESPACE}|${NAMESPACE}|g; s|\${NAME_PREFIX}|${NAME_PREFIX}|g; s|\${JAVA_IMAGE}|${JAVA_IMAGE}|g" \
  manifests/java-app-deployment.yaml | kubectl apply -f -

# ロールアウト完了を待機
kubectl rollout status deployment/python-app deployment/java-app -n ${NAMESPACE}
```

> **注意:** `kubectl apply` による Deployment 更新で Pod が再作成されます。
> SSI 導入済みの場合、Admission Controller が APM ライブラリを自動注入します（`rollout restart` は不要）。

---

## Step 3: init_analytics_db の実行確認

Python Pod が再起動時に `init_analytics_db()` を自動実行して `order_monthly_stats` テーブルを作成・シードします。

```bash
# Python Pod のログで init 完了を確認
kubectl logs -l app=python-app -n ${NAMESPACE} --tail=20

# 期待されるログ（SSI なし）:
# {"message": "init_analytics_db: seeding curr=2026-06 prev=2026-05", ...}
# {"message": "init_analytics_db: seed complete", ...}
```

---

## Step 4: 動作確認

別ターミナルでポートフォワードを起動してから確認します。

```bash
kubectl port-forward svc/java-app 8080:8080 -n ${NAMESPACE} &

# 基本確認
curl http://localhost:8080/analytics
curl http://localhost:8080/analytics/summary

# エラー率確認（10 回中 ~1〜2 回が 500 になることを確認）
for i in {1..10}; do
  curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/analytics
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
# → ZeroDivisionError → Flask 500 → Java がリトライ（500ms 待機）→ 再度 500
```

APM 上では Java の `/analytics` span 内に Python への HTTP 呼び出しが **2 回**（リトライ含む）観測されます。