# mail-worker-k8s

Argo CD、Sidekiq、Kubernetes（HPA）、Unleashの学習を目的とした最小限のメール送信システム

## 🎯 学習目標

- **Argo CD**: GUI/CLI操作、GitOps、ロールバック
- **Sidekiq**: キュー管理、ジョブ再試行、管理画面操作
- **Kubernetes**: HPA動作、Pod自動スケーリング
- **Unleash**: フィーチャーフラグ管理、A/Bテスト、段階的リリース

## 🏗️ システム構成

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

## 🚀 クイックスタート

### 前提条件
- Docker Desktop
- kubectl
- minikube または kind
- Git

### 環境構築

```bash
# 1. プロジェクトクローン
git clone <repository-url>
cd mail-worker-k8s

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

## 🌐 アクセス情報

| サービス | URL | 説明 |
|---------|-----|------|
| Rails App | http://localhost:3000 | メイン画面 |
| Sidekiq | http://localhost:3000/sidekiq | キュー管理画面 |
| MailCatcher | http://localhost:1080 | メール確認画面 |
| Unleash | http://localhost:4242 | フィーチャーフラグ管理 |
| Argo CD | https://localhost:8080 | GitOps管理画面 |

## 📚 学習シナリオ

### 1. Sidekiq学習
```bash
# 管理画面アクセス
kubectl port-forward svc/mail-web -n mail-app 3000:80

# 学習内容
# - 1000件送信ボタンでキュー確認
# - エラーシミュレーションで失敗ジョブ確認
# - デッドキューからの復活操作
```

### 2. HPA学習
```bash
# Pod数とCPU使用率監視
kubectl get pods -n mail-app -l app=mail-sidekiq
kubectl top pods -n mail-app -l app=mail-sidekiq --watch
kubectl get hpa -n mail-app -w

# 学習内容
# - 10000件送信でCPU負荷上昇
# - Pod自動増加の観察
# - 処理完了後の自動減少
```

### 3. Argo CD学習
```bash
# GUI操作
kubectl port-forward svc/argocd-server -n argocd 8080:443

# CLI操作
argocd login localhost:8080
argocd app list
argocd app sync mail-app
argocd app get mail-app

# 学習内容
# - HPA設定変更をGitにコミット
# - 自動同期の確認
# - 問題発生時のロールバック
```

### 4. Unleash学習
```bash
# 管理画面アクセス
kubectl port-forward svc/unleash -n mail-app 4242:4242

# 学習内容
# - フィーチャーフラグ作成: bulk_send_feature
# - バリアント作成: send_strategy (default/priority)
# - RailsアプリでフラグON/OFF動作確認
```

## 🛠️ 学習用スクリプト

```bash
# 各学習シナリオの実行
./scripts/learning-scenarios.sh sidekiq   # Sidekiq学習
./scripts/learning-scenarios.sh hpa       # HPA学習
./scripts/learning-scenarios.sh argocd    # Argo CD学習
./scripts/learning-scenarios.sh unleash   # Unleash学習
```

## 📋 機能一覧

### コア機能
- メールアドレス管理（一覧表示、追加・削除、CSV一括登録）
- 一括メール送信機能
- 送信状況確認
- 負荷テスト機能（1000件/5000件/10000件送信）
- 意図的エラー発生機能

### フィーチャーフラグ機能
- Unleashによる機能ON/OFF切り替え
- A/Bテスト用の段階的機能リリース

## 🔧 トラブルシューティング

### よくある問題

1. **Sidekiqジョブが処理されない**
   ```bash
   kubectl logs deployment/mail-sidekiq -n mail-app
   ```

2. **HPA が動作しない**
   ```bash
   kubectl top nodes
   kubectl describe pod -n mail-app
   ```

3. **Argo CD同期エラー**
   ```bash
   argocd app get mail-app
   kubectl logs -n argocd deployment/argocd-application-controller
   ```

## 📁 プロジェクト構造

```
mail-worker-k8s/
├── app/                    # Rails アプリケーション
├── k8s/                    # Kubernetes マニフェスト
│   ├── base/              # 基本設定
│   └── overlays/          # 環境別設定
├── argocd/                # Argo CD 設定
├── scripts/               # 学習用スクリプト
├── docker-compose.yml     # 開発環境
└── Dockerfile            # コンテナイメージ
```

## 🎓 実装タスク

詳細な実装手順は [tasks.md](tasks.md) を参照してください。

1. **T-01**: Rails基本アプリケーション作成
2. **T-02**: データモデルとマイグレーション作成
3. **T-03**: Sidekiqジョブとメーラー実装
4. **T-04**: コントローラーとビュー実装
5. **T-05**: Docker環境構築
6. **T-06**: Kubernetes基盤構築
7. **T-07**: Argo CD設定とGitOps環境構築
8. **T-08**: Unleashフィーチャーフラグ統合

## 📖 設計詳細

システムの詳細設計は [DESIGN.md](DESIGN.md) を参照してください。

## 🚀 拡張案

学習が進んだ後の拡張機能：
- PostgreSQL導入
- 複数環境（dev/staging/prod）
- Prometheus監視
- Grafana ダッシュボード
- Helm Chart化

---

このプロジェクトを通じて、現代的なクラウドネイティブアプリケーションの開発・運用に必要な技術を実践的に学習できます。