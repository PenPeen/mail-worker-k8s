# メール送信システム設計書

## 1. プロジェクト概要

### 目的
Argo CD、Sidekiq、Kubernetes（HPA）の学習を目的とした最小限のメール送信システム

### 学習目標
- Argo CD: GUI/CLI操作、GitOps、ロールバック
- Sidekiq: キュー管理、ジョブ再試行、管理画面操作
- Kubernetes: HPA動作、Pod自動スケーリング
- Unleash: フィーチャーフラグ管理、A/Bテスト、段階的リリース

## 2. システム構成

### アーキテクチャ
```
[Rails Web] ←→ [Redis] ←→ [Sidekiq Worker]
     ↓              ↓
[MailCatcher]    [Unleash]
```

### 技術スタック
- **Backend**: Ruby on Rails 7.x
- **Job Queue**: Sidekiq + Redis
- **Database**: SQLite（簡素化）
- **Mail**: MailCatcher（テスト用SMTP）
- **Feature Flags**: Unleash
- **Container**: Docker
- **Orchestration**: Kubernetes
- **CD**: Argo CD

## 3. 機能仕様

### 3.1 コア機能
1. **メールアドレス管理**
   - 一覧表示
   - 追加・削除（CSV一括登録対応）

2. **メール送信**
   - 一括送信機能
   - 送信状況確認

3. **負荷テスト機能**
   - 1000件/5000件/10000件送信ボタン
   - 意図的エラー発生機能

4. **フィーチャーフラグ機能**
   - Unleashによる機能ON/OFF切り替え
   - A/Bテスト用の段階的機能リリース

### 3.2 学習用機能
- Sidekiq管理画面アクセス（`/sidekiq`）
- リアルタイム送信状況表示
- CPU使用率表示（HPA学習用）
- Unleash管理画面アクセス（フィーチャーフラグ管理）

## 4. データベース設計

### テーブル構成
```sql
-- emails テーブル
CREATE TABLE emails (
  id INTEGER PRIMARY KEY,
  email VARCHAR(255) NOT NULL,
  name VARCHAR(255),
  created_at DATETIME,
  updated_at DATETIME
);

-- mail_jobs テーブル（送信履歴）
CREATE TABLE mail_jobs (
  id INTEGER PRIMARY KEY,
  job_id VARCHAR(255),
  total_count INTEGER,
  sent_count INTEGER DEFAULT 0,
  failed_count INTEGER DEFAULT 0,
  status VARCHAR(50) DEFAULT 'pending',
  created_at DATETIME,
  updated_at DATETIME
);
```

## 5. Rails実装詳細

### 5.1 Gemfile
```ruby
gem 'rails', '~> 7.0'
gem 'sidekiq'
gem 'redis'
gem 'sqlite3'
gem 'bootsnap'
gem 'puma'
gem 'unleash', '~> 4.0'
```

### 5.2 モデル
```ruby
# app/models/email.rb
class Email < ApplicationRecord
  validates :email, presence: true, uniqueness: true
end

# app/models/mail_job.rb
class MailJob < ApplicationRecord
  enum status: { pending: 0, processing: 1, completed: 2, failed: 3 }
end
```

### 5.3 Sidekiqジョブ
```ruby
# app/jobs/mail_sender_job.rb
class MailSenderJob
  include Sidekiq::Job
  sidekiq_options queue: 'default', retry: 3

  def perform(email_id, mail_job_id, simulate_error = false)
    # エラーシミュレーション
    raise "Simulated error" if simulate_error && rand < 0.3
    
    # メール送信処理
    email = Email.find(email_id)
    TestMailer.notification(email.email).deliver_now
    
    # 送信カウント更新
    mail_job = MailJob.find(mail_job_id)
    mail_job.increment!(:sent_count)
  end
end
```

### 5.4 コントローラー
```ruby
# app/controllers/emails_controller.rb
class EmailsController < ApplicationController
  def index
    @emails = Email.all
    @mail_jobs = MailJob.order(created_at: :desc).limit(10)
  end

  def bulk_send
    count = params[:count].to_i
    simulate_error = params[:simulate_error] == 'true'
    
    mail_job = MailJob.create!(
      total_count: count,
      status: 'processing'
    )
    
    count.times do |i|
      email = Email.offset(rand(Email.count)).first
      MailSenderJob.perform_async(email.id, mail_job.id, simulate_error)
    end
    
    redirect_to emails_path, notice: "#{count}件の送信ジョブを作成しました"
  end
end
```

## 6. Docker設定

### 6.1 Dockerfile
```dockerfile
FROM ruby:3.2-alpine

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

EXPOSE 3000

CMD ["rails", "server", "-b", "0.0.0.0"]
```

### 6.2 docker-compose.yml（開発用）
```yaml
version: '3.8'
services:
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

  mailcatcher:
    image: schickling/mailcatcher
    ports:
      - "1080:1080"
      - "1025:1025"

  unleash:
    image: unleashorg/unleash-server:latest
    ports:
      - "4242:4242"
    environment:
      - DATABASE_URL=sqlite:///unleash.db
      - DATABASE_SSL=false
    volumes:
      - unleash_data:/data

  web:
    build: .
    ports:
      - "3000:3000"
    environment:
      - REDIS_URL=redis://redis:6379/0
      - SMTP_HOST=mailcatcher
      - SMTP_PORT=1025
    depends_on:
      - redis
      - mailcatcher

  sidekiq:
    build: .
    command: bundle exec sidekiq
    environment:
      - REDIS_URL=redis://redis:6379/0
      - SMTP_HOST=mailcatcher
      - SMTP_PORT=1025
    depends_on:
      - redis
      - mailcatcher
```

## 7. Kubernetes設定

### 7.1 ディレクトリ構成
```
k8s/
├── base/
│   ├── redis-deployment.yaml
│   ├── mailcatcher-deployment.yaml
│   ├── web-deployment.yaml
│   ├── sidekiq-deployment.yaml
│   ├── hpa.yaml
│   └── services.yaml
└── overlays/
    ├── dev/
    └── prod/
```

### 7.2 Redis Deployment
```yaml
# k8s/base/redis-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
---
apiVersion: v1
kind: Service
metadata:
  name: redis
spec:
  selector:
    app: redis
  ports:
  - port: 6379
    targetPort: 6379
```

### 7.3 Web Deployment
```yaml
# k8s/base/web-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mail-web
spec:
  replicas: 2
  selector:
    matchLabels:
      app: mail-web
  template:
    metadata:
      labels:
        app: mail-web
    spec:
      containers:
      - name: web
        image: mail-app:latest
        ports:
        - containerPort: 3000
        env:
        - name: REDIS_URL
          value: "redis://redis:6379/0"
        - name: SMTP_HOST
          value: "mailcatcher"
        - name: SMTP_PORT
          value: "1025"
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
---
apiVersion: v1
kind: Service
metadata:
  name: mail-web
spec:
  selector:
    app: mail-web
  ports:
  - port: 80
    targetPort: 3000
  type: LoadBalancer
```

### 7.4 Sidekiq Deployment
```yaml
# k8s/base/sidekiq-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mail-sidekiq
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mail-sidekiq
  template:
    metadata:
      labels:
        app: mail-sidekiq
    spec:
      containers:
      - name: sidekiq
        image: mail-app:latest
        command: ["bundle", "exec", "sidekiq"]
        env:
        - name: REDIS_URL
          value: "redis://redis:6379/0"
        - name: SMTP_HOST
          value: "mailcatcher"
        - name: SMTP_PORT
          value: "1025"
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 1000m
            memory: 512Mi
```

### 7.5 HPA設定
```yaml
# k8s/base/hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: mail-sidekiq-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: mail-sidekiq
  minReplicas: 1
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
      - type: Percent
        value: 100
        periodSeconds: 15
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
```

## 8. Argo CD設定

### 8.1 Application定義
```yaml
# argocd/application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: mail-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-repo/mail-app
    targetRevision: HEAD
    path: k8s/overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: mail-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

### 8.2 Argo CD CLI設定
```bash
# argocd-setup.sh
#!/bin/bash

# Argo CD CLI インストール
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd

# ログイン設定
argocd login localhost:8080 --username admin --password $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# アプリケーション作成
argocd app create mail-app \
  --repo https://github.com/your-repo/mail-app \
  --path k8s/overlays/dev \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace mail-app \
  --sync-policy automated \
  --auto-prune \
  --self-heal
```

## 9. 学習シナリオ

### 9.1 Sidekiq学習
1. **基本操作**
   ```bash
   # Sidekiq管理画面アクセス
   kubectl port-forward svc/mail-web 3000:80
   # http://localhost:3000/sidekiq
   ```

2. **キュー操作**
   - 1000件送信ボタンクリック
   - 管理画面でキュー状況確認
   - 失敗ジョブの再試行
   - デッドキューからの復活

3. **エラーハンドリング**
   - エラーシミュレーション有効で送信
   - 失敗ジョブの確認・再試行

### 9.2 HPA学習
1. **負荷テスト**
   ```bash
   # CPU使用率監視
   kubectl top pods -l app=mail-sidekiq
   
   # HPA状況確認
   kubectl get hpa mail-sidekiq-hpa -w
   ```

2. **スケーリング確認**
   - 10000件送信でCPU負荷上昇
   - Pod自動増加の観察
   - 処理完了後の自動減少

### 9.3 Argo CD学習
1. **GUI操作**
   ```bash
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   # https://localhost:8080
   ```

2. **CLI操作**
   ```bash
   # アプリケーション状況確認
   argocd app list
   argocd app get mail-app
   
   # 同期操作
   argocd app sync mail-app
   argocd app wait mail-app
   
   # ロールバック
   argocd app rollback mail-app
   ```

3. **GitOps実践**
   - HPA設定変更をGitにコミット
   - 自動同期の確認
   - 問題発生時のロールバック

## 10. セットアップ手順

### 10.1 前提条件
- Docker Desktop
- kubectl
- minikube または kind
- Git

### 10.2 環境構築
```bash
# 1. プロジェクトクローン
git clone <repository-url>
cd mail-app

# 2. ローカル開発環境
docker-compose up -d

# 3. Kubernetes環境
minikube start
kubectl apply -f k8s/base/

# 4. Argo CD インストール
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 5. Argo CD設定
kubectl apply -f argocd/application.yaml
```

### 10.3 アクセス情報
- **Rails App**: http://localhost:3000
- **Sidekiq**: http://localhost:3000/sidekiq
- **MailCatcher**: http://localhost:1080
- **Unleash**: http://localhost:4242
- **Argo CD**: https://localhost:8080

## 11. トラブルシューティング

### よくある問題と解決方法

1. **Sidekiqジョブが処理されない**
   - Redis接続確認: `kubectl logs deployment/mail-sidekiq`
   - キュー状況確認: Sidekiq管理画面

2. **HPA が動作しない**
   - Metrics Server確認: `kubectl top nodes`
   - リソース制限確認: `kubectl describe pod`

3. **Argo CD同期エラー**
   - アプリケーション状況: `argocd app get mail-app`
   - ログ確認: `kubectl logs -n argocd deployment/argocd-application-controller`

## 12. Unleash学習シナリオ

### 12.1 フィーチャーフラグ基本操作
1. **管理画面アクセス**
   ```bash
   kubectl port-forward svc/unleash 4242:4242
   # http://localhost:4242
   ```

2. **フラグ作成・管理**
   - 新機能のON/OFF切り替え
   - ユーザーセグメント別の段階的リリース
   - A/Bテスト設定

3. **Rails連携**
   - フィーチャーフラグによる機能制御
   - 動的な機能切り替え確認

## 13. 拡張案

学習が進んだ後の拡張機能：
- PostgreSQL導入
- 複数環境（dev/staging/prod）
- Prometheus監視
- Grafana ダッシュボード
- Helm Chart化

---

この設計書に基づいて実装を進めることで、Argo CD、Sidekiq、Kubernetesの実践的な学習が可能です。