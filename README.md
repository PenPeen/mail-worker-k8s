# README

## 概要
Argo CDとGitOpsワークフローの学習環境（Rails + Sidekiq + Kubernetes + Argo Rollouts）

## アーキテクチャ
- **App of Apps パターン**: Argo CD Application を Git で管理し、完全自動化
- **Argo Rollouts**: Canary デプロイメント対応
- **GitOps**: Git push のみで全てのリソースが自動デプロイ

## 前提条件
- minikube
- kubectl

## 起動方法

```bash
# 1. Argo CD + Argo Rollouts 環境セットアップ
make setup

# 2. Root Application 登録（最初の1回のみ）
kubectl apply -f argocd/root-app.yaml

# 3. アプリケーション登録
make register-app

# 4. 開発環境起動（イメージビルド + ポートフォワード）
make start
```

## GitOps ワークフロー

変更を Git に push するだけで、全てのリソースが自動的にデプロイされます：

```bash
# 1. マニフェストを変更
vim k8s/rollouts/web-rollout.yaml

# 2. Git に push
git add .
git commit -m "Update web-rollout replicas"
git push

# 3. Argo CD が自動的に sync（数秒〜数分）
kubectl get applications -n argocd -w
```

## アクセスURL
- Rails: http://localhost:8000
- Sidekiq: http://localhost:8000/sidekiq
- Unleash: http://localhost:8242 (admin/unleash4all)
- MailCatcher: http://localhost:8080
- Argo CD: https://localhost:8443 (admin/password)

## その他のコマンド
```bash
make status   # サービス状況確認
make stop     # ポートフォワード停止
make restart  # 再起動
make clean    # 環境クリーンアップ
make help     # コマンド一覧表示
```
