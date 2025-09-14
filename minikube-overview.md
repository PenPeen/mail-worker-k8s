# Minikube とは

Minikubeは、ローカル環境でKubernetesクラスターを簡単に構築・実行できるツールです。開発・学習・テスト用途に最適化されています。

## 特徴

- **軽量**: 単一ノードのKubernetesクラスター
- **簡単セットアップ**: 数分でローカルクラスターを起動
- **クロスプラットフォーム**: Windows、macOS、Linux対応
- **複数ドライバー対応**: Docker、VirtualBox、VMware等

## 基本コマンド

```bash
# クラスター起動
minikube start

# 状態確認
minikube status

# ダッシュボード起動
minikube dashboard

# クラスター停止
minikube stop

# クラスター削除
minikube delete
```

## kubectl設定確認

### 主な確認項目

**クラスター情報**
- 接続先Kubernetesクラスターのエンドポイント
- 証明書情報（certificate-authority-data）

**ユーザー認証情報**
- 認証方式（token、certificate、exec等）
- ユーザー名とクライアント証明書情報

**コンテキスト設定**
- 現在のコンテキスト（current-context）
- 利用可能なコンテキスト一覧
- クラスターとユーザーの組み合わせ

**名前空間**
- デフォルト名前空間の設定

### 実行例

```bash
kubectl config view
# または機密情報も表示
kubectl config view --raw
```

### 注意点

- デフォルトでは機密情報（トークン等）は隠される
- オプションで完全な設定を表示
- 複数クラスター管理時の設定確認に有用

現在どのクラスターに接続しているか、認証設定が正しいかを確認する際に使用します。