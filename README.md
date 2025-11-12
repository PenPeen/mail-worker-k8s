# README

## 概要
Argo CDとGitOpsワークフローの学習環境（Rails + Sidekiq + Kubernetes）

## 前提条件
- minikube
- kubectl

## 起動方法

```bash
# 1. Argo CD環境セットアップ
make setup

# 2. アプリケーション登録
make register-app

# 3. 開発環境起動（イメージビルド + ポートフォワード）
make start
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
