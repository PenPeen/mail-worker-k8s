## T-06: Argo CD設定とGitOps環境構築
## 目的: Argo CD GUI/CLI学習とGitOpsワークフローの実践
## 前提: minikubeがインストール済み、kubectlが利用可能

# プロジェクト専用のminikubeプロファイル名
MINIKUBE_PROFILE = mail-app

.PHONY: setup setup-repo sync register-app clean help start stop restart status

help: ## Show help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

setup: ## Setup minikube cluster and Argo CD for GitOps learning
	## 目的: T-06 Argo CD設定とGitOps環境構築のためのローカル環境セットアップ
	## 実行内容:
	##   1. minikubeクラスターの起動確認・起動
	##   2. kubectlコンテキストをminikubeに切り替え
	##   3. argocd namespace作成
	##   4. Argo CDの公式マニフェストをインストール
	##   5. Argo CD Serverの起動待機
	##   6. 初期管理者パスワードを取得・表示
	## 結果: Argo CD GUIに https://localhost:8080 でアクセス可能になる
	@echo "=== minikube クラスター起動 ==="
	@if ! minikube -p $(MINIKUBE_PROFILE) status 2>&1 | grep -q "Running"; then \
		echo "minikubeを起動中..."; \
		minikube start -p $(MINIKUBE_PROFILE); \
	fi
	@kubectl config use-context $(MINIKUBE_PROFILE)
	@echo "=== Argo CD セットアップ開始 ==="
	kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
	kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
	@echo "=== パスワードを 'password' に変更中 ==="
	kubectl -n argocd delete secret argocd-initial-admin-secret --ignore-not-found=true
	kubectl -n argocd patch secret argocd-secret -p '{"stringData": {"admin.password": "$$2a$$10$$vFH0TVRnZ7UbM.ibdcruvOjlqE0YObaNZUAGi2bUfChddZtxUZwxS", "admin.passwordMtime": "'$$(date +%FT%T%Z)'"}}'
	kubectl -n argocd rollout restart deployment argocd-server
	kubectl -n argocd rollout status deployment argocd-server --timeout=120s
	@echo "Username: admin"
	@echo "Password: password"
	@echo "GUI: kubectl port-forward svc/argocd-server -n argocd 8443:443"
	@echo "=== Argo Rollouts セットアップ開始 ==="
	kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
	kubectl wait --for=condition=available --timeout=300s deployment/argo-rollouts -n argo-rollouts
	@echo "=== Argo Rollouts セットアップ完了 ==="

setup-repo: ## Setup private repository credentials for Argo CD
	@echo "=== プライベートリポジトリ設定 ==="
	@read -p "GitHubユーザー名: " GITHUB_USERNAME; \
	read -s -p "GitHub PAT: " GITHUB_PAT; \
	echo; \
	GITHUB_USERNAME=$$GITHUB_USERNAME GITHUB_PAT=$$GITHUB_PAT envsubst < argocd/repo-secret.yaml | kubectl apply -f -
	@kubectl apply -f argocd/applications/mail-app.yaml
	@echo "リポジトリ認証情報が設定されました"

sync: ## Manually sync Argo CD application
	@echo "=== 手動同期実行 ==="
	kubectl create namespace mail-app --dry-run=client -o yaml | kubectl apply -f -
	kubectl patch application mail-app -n argocd --type merge -p '{"operation":{"sync":{"syncStrategy":{"apply":{"force":true}}}}}'
	@echo "同期が開始されました"

register-app: ## Register mail-app to Argo CD for GitOps deployment
	## 目的: GitOpsワークフローの学習のためにArgo CDにアプリケーションを登録
	## 実行内容:
	##   1. Railsアプリケーションのdockerイメージをビルド
	##   2. minikubeクラスターにイメージをロード（ローカルイメージを使用可能に）
	##   3. argocd/application.yamlを適用してArgo CD Applicationリソースを作成
	## 注意: 現在のapplication.yamlのrepoURLがプレースホルダーのため、Git同期は失敗する
	## 結果: Argo CD GUIでmail-appアプリケーションが表示される（OutOfSync状態）
	@echo "=== Argo CDアプリケーション登録開始 ==="
	@eval $$(minikube -p $(MINIKUBE_PROFILE) docker-env) && docker build -t mail-app:latest .
	@if command -v minikube >/dev/null 2>&1 && minikube -p $(MINIKUBE_PROFILE) status >/dev/null 2>&1; then \
		echo "minikubeにイメージをロード中..."; \
		minikube -p $(MINIKUBE_PROFILE) image load mail-app:latest; \
	fi
	kubectl apply -f argocd/applications/mail-app.yaml
	@echo "=== アプリケーション登録完了 ==="

start: ## Start GitOps development environment
	## 目的: GitOpsワークフローでの開発環境起動
	## 実行内容:
	##   1. minikubeクラスター確認・起動
	##   2. アプリケーションイメージビルド
	##   3. Argo CDで手動同期待機
	##   4. ポートフォワード設定
	@echo "=== 開発環境起動開始 ==="
	@if ! minikube -p $(MINIKUBE_PROFILE) status 2>&1 | grep -q "Running"; then \
		echo "minikubeを起動中..."; \
		minikube start -p $(MINIKUBE_PROFILE); \
	fi
	@kubectl config use-context $(MINIKUBE_PROFILE)
	@echo "=== アプリケーションビルド ==="
	@eval $$(minikube -p $(MINIKUBE_PROFILE) docker-env) && docker build -t mail-app:latest .
	@echo "=== ポートフォワード設定 ==="
	@pkill -f "kubectl port-forward" || true
	@sleep 2
	@echo "Starting port forwards..."
	@kubectl port-forward svc/mail-web -n mail-app 8000:80 > /dev/null 2>&1 & echo "Mail-web port-forward started (PID: $$!)"
	@kubectl port-forward svc/unleash -n mail-app 8242:4242 > /dev/null 2>&1 & echo "Unleash port-forward started (PID: $$!)"
	@kubectl port-forward svc/mailcatcher -n mail-app 8080:1080 > /dev/null 2>&1 & echo "MailCatcher port-forward started (PID: $$!)"
	@kubectl port-forward svc/argocd-server -n argocd 8443:443 > /dev/null 2>&1 & echo "Argo CD port-forward started (PID: $$!)"
	@sleep 3
	@echo "=== サービス確認 ==="
	@ps aux | grep "kubectl port-forward" | grep -v grep || echo "Warning: Some port-forwards may not be running"
	@echo "Rails: http://localhost:8000"
	@echo "Sidekiq: http://localhost:8000/sidekiq"
	@echo "Unleash: http://localhost:8242 (admin/unleash4all)"
	@echo "MailCatcher: http://localhost:8080"
	@echo "Argo CD: https://localhost:8443 (admin/password)"

stop: ## Stop port forwarding processes
	@echo "=== ポートフォワード停止 ==="
	@pkill -f "kubectl port-forward" || true
	@echo "ポートフォワードを停止しました"

restart: ## Restart development environment (stop + start)
	@$(MAKE) stop
	@$(MAKE) start

status: ## Show service status and URLs
	@echo "=== サービス状況 ==="
	kubectl get pods -n mail-app
	@echo ""
	@echo "=== アクセスURL ==="
	@echo "Rails: http://localhost:8000"
	@echo "Sidekiq: http://localhost:8000/sidekiq"
	@echo "Unleash: http://localhost:8242 (admin/unleash4all)"
	@echo "MailCatcher: http://localhost:8080"
	@echo "Argo CD: https://localhost:8443 (admin/password)"

clean: ## Clean up Argo CD application and related resources
	## 目的: テスト環境のクリーンアップ
	## 実行内容:
	##   1. Argo CDからmail-appアプリケーションを削除
	##   2. mail-app namespaceを削除（アプリケーションがデプロイしたリソースを含む）
	## 注意: Argo CD自体は削除されない（argocd namespaceは残る）
	@pkill -f "kubectl port-forward" || true
	kubectl delete application mail-app -n argocd --ignore-not-found=true
	kubectl delete namespace mail-app --ignore-not-found=true
