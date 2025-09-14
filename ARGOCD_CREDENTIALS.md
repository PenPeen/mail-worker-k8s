# Argo CD 認証情報

## 管理者アカウント
- **Username**: `admin`
- **Password**: `21QYDWDgt02XD7jO`
- **GUI URL**: https://localhost:8080

## アクセス方法
```bash
# ポートフォワード開始
kubectl port-forward svc/argocd-server -n argocd 8080:443

# パスワード再取得（必要時）
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## 注意
- パスワードはArgo CD初回セットアップ時に自動生成される
- minikubeクラスターを削除・再作成すると変更される
- 本番環境では初期パスワードを変更することを推奨