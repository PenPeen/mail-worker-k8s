## T-06: Argo CD設定とGitOps環境構築
## 目的: Argo CD GUI/CLI学習とGitOpsワークフローの実践
## 前提: minikubeがインストール済み、kubectlが利用可能

.PHONY: setup setup-repo register-app clean help

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
	@if ! minikube status >/dev/null 2>&1; then \
		minikube start; \
	fi
	@kubectl config use-context minikube
	@echo "=== Argo CD セットアップ開始 ==="
	kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
	kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
	@echo "Username: admin"
	@echo -n "Password: "
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
	@echo ""
	@echo "GUI: kubectl port-forward svc/argocd-server -n argocd 8080:443"

setup-repo: ## Setup private repository credentials for Argo CD
	@echo "=== プライベートリポジトリ設定 ==="
	@read -p "GitHubユーザー名: " GITHUB_USERNAME; \
	read -s -p "GitHub PAT: " GITHUB_PAT; \
	echo; \
	GITHUB_USERNAME=$$GITHUB_USERNAME GITHUB_PAT=$$GITHUB_PAT envsubst < argocd/repo-secret.yaml | kubectl apply -f -
	@kubectl apply -f argocd/application.yaml
	@echo "リポジトリ認証情報が設定されました"

register-app: ## Register mail-app to Argo CD for GitOps deployment
	## 目的: GitOpsワークフローの学習のためにArgo CDにアプリケーションを登録
	## 実行内容:
	##   1. Railsアプリケーションのdockerイメージをビルド
	##   2. minikubeクラスターにイメージをロード（ローカルイメージを使用可能に）
	##   3. argocd/application.yamlを適用してArgo CD Applicationリソースを作成
	## 注意: 現在のapplication.yamlのrepoURLがプレースホルダーのため、Git同期は失敗する
	## 結果: Argo CD GUIでmail-appアプリケーションが表示される（OutOfSync状態）
	@echo "=== Argo CDアプリケーション登録開始 ==="
	docker build -t mail-app:latest .
	@if command -v minikube >/dev/null 2>&1 && minikube status >/dev/null 2>&1; then \
		echo "minikubeにイメージをロード中..."; \
		minikube image load mail-app:latest; \
	fi
	kubectl apply -f argocd/application.yaml
	@echo "=== アプリケーション登録完了 ==="

clean: ## Clean up Argo CD application and related resources
	## 目的: テスト環境のクリーンアップ
	## 実行内容:
	##   1. Argo CDからmail-appアプリケーションを削除
	##   2. mail-app namespaceを削除（アプリケーションがデプロイしたリソースを含む）
	## 注意: Argo CD自体は削除されない（argocd namespaceは残る）
	kubectl delete application mail-app -n argocd --ignore-not-found=true
	kubectl delete namespace mail-app --ignore-not-found=true
