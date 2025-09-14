# mail-worker-k8s 実装タスク計画

## 概要
- 目的: Argo CD、Sidekiq、Kubernetes（HPA）、Unleashの学習を目的とした最小限のメール送信システムの構築
- 成功基準: Sidekiq管理画面でのキュー操作、HPA動作確認、Argo CD GUI/CLI操作、Unleashフィーチャーフラグ操作が全て実行可能
- スコープ: Rails基本機能、Docker環境、K8S基盤、Argo CD設定、Unleash連携の実装
- 非スコープ: 本格的なメール配信機能、複雑な認証機能、本番運用設定

## タスク一覧

- T-01: Docker環境とRails基本セットアップ
  - 概要: Docker環境構築とRails 7アプリケーションの基本構造とSidekiq設定を作成
  - 理由: コンテナ化により環境の一貫性を保ち、学習用メール送信システムの基盤を構築
  - 受け入れ条件: docker-compose up で全サービス起動、Rails起動、Sidekiq管理画面アクセス
  - 依存関係: なし
  - ブランチ: feature/docker-rails-setup
  - 実装内容（詳細に、コピペするだけで作業が完了する粒度）
    
    - Dockerfileを新規作成:
      ```dockerfile
      FROM ruby:3.2-alpine

      RUN apk add --no-cache build-base sqlite-dev tzdata
      WORKDIR /app
      COPY Gemfile Gemfile.lock ./
      RUN bundle install
      COPY . .
      EXPOSE 3000
      CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
      ```
    
    - docker-compose.ymlを新規作成:
      ```yaml
      version: '3.8'
      services:
        redis:
          image: redis:7-alpine
          ports: ["6379:6379"]
        mailcatcher:
          image: schickling/mailcatcher
          ports: ["1080:1080", "1025:1025"]
        web:
          build: .
          ports: ["3000:3000"]
          environment:
            - REDIS_URL=redis://redis:6379/0
            - SMTP_HOST=mailcatcher
            - SMTP_PORT=1025
          depends_on: [redis, mailcatcher]
          volumes: [".:/app"]
        sidekiq:
          build: .
          command: bundle exec sidekiq
          environment:
            - REDIS_URL=redis://redis:6379/0
            - SMTP_HOST=mailcatcher
            - SMTP_PORT=1025
          depends_on: [redis, mailcatcher]
          volumes: [".:/app"]
      ```
    
    - Gemfileを新規作成:
      ```ruby
      source 'https://rubygems.org'
      git_source(:github) { |repo| "https://github.com/#{repo}.git" }

      ruby '3.2.0'

      gem 'rails', '~> 7.0.0'
      gem 'sidekiq'
      gem 'redis'
      gem 'sqlite3', '~> 1.4'
      gem 'puma', '~> 5.0'
      gem 'bootsnap', '>= 1.4.4', require: false
      gem 'unleash', '~> 4.0'

      group :development, :test do
        gem 'byebug', platforms: [:mri, :mingw, :x64_mingw]
      end

      group :development do
        gem 'web-console', '>= 4.1.0'
        gem 'listen', '~> 3.3'
        gem 'spring'
      end
      ```
    
    - config/application.rbを修正:
      ```ruby
      require_relative "boot"

      require "rails/all"

      Bundler.require(*Rails.groups)

      module MailWorkerK8s
        class Application < Rails::Application
          config.load_defaults 7.0
          config.active_job.queue_adapter = :sidekiq
        end
      end
      ```
    
    - config/routes.rbを修正:
      ```ruby
      Rails.application.routes.draw do
        require 'sidekiq/web'
        mount Sidekiq::Web => '/sidekiq'
        
        root 'emails#index'
        resources :emails, only: [:index, :create, :destroy] do
          collection do
            post :bulk_send
            post :import_csv
          end
        end
      end
      ```
    
    - config/initializers/sidekiq.rbを新規作成:
      ```ruby
      Sidekiq.configure_server do |config|
        config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0') }
      end

      Sidekiq.configure_client do |config|
        config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0') }
      end
      ```

- T-02: データモデルとマイグレーション作成
  - 概要: Email、MailJobモデルとデータベーステーブルを作成
  - 理由: メールアドレス管理と送信履歴追跡のためのデータ構造が必要
  - 受け入れ条件: マイグレーション実行成功、モデルのバリデーション動作確認
  - 依存関係: T-01
  - ブランチ: feature/data-models
  - 実装内容（詳細に、コピペするだけで作業が完了する粒度）
    
    - app/models/email.rbを新規作成:
      ```ruby
      class Email < ApplicationRecord
        validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
        validates :name, presence: true

        scope :random_sample, ->(count) { order('RANDOM()').limit(count) }
      end
      ```
    
    - app/models/mail_job.rbを新規作成:
      ```ruby
      class MailJob < ApplicationRecord
        enum status: { pending: 0, processing: 1, completed: 2, failed: 3 }

        validates :total_count, presence: true, numericality: { greater_than: 0 }
        validates :sent_count, :failed_count, numericality: { greater_than_or_equal_to: 0 }

        def progress_percentage
          return 0 if total_count.zero?
          ((sent_count + failed_count).to_f / total_count * 100).round(1)
        end

        def remaining_count
          total_count - sent_count - failed_count
        end
      end
      ```
    
    - db/migrate/001_create_emails.rbを新規作成:
      ```ruby
      class CreateEmails < ActiveRecord::Migration[7.0]
        def change
          create_table :emails do |t|
            t.string :email, null: false
            t.string :name, null: false
            t.timestamps
          end
          
          add_index :emails, :email, unique: true
        end
      end
      ```
    
    - db/migrate/002_create_mail_jobs.rbを新規作成:
      ```ruby
      class CreateMailJobs < ActiveRecord::Migration[7.0]
        def change
          create_table :mail_jobs do |t|
            t.string :job_id
            t.integer :total_count, null: false
            t.integer :sent_count, default: 0
            t.integer :failed_count, default: 0
            t.integer :status, default: 0
            t.timestamps
          end
          
          add_index :mail_jobs, :job_id
          add_index :mail_jobs, :status
        end
      end
      ```

- T-03: Sidekiqジョブとメーラー実装
  - 概要: メール送信用のSidekiqジョブとActionMailerを実装
  - 理由: 非同期メール送信処理とエラーハンドリング学習のため
  - 受け入れ条件: Sidekiqジョブが正常実行、エラーシミュレーション動作、リトライ機能確認
  - 依存関係: T-02
  - ブランチ: feature/sidekiq-jobs
  - 実装内容（詳細に、コピペするだけで作業が完了する粒度）
    
    - app/jobs/mail_sender_job.rbを新規作成:
      ```ruby
      class MailSenderJob
        include Sidekiq::Job
        sidekiq_options queue: 'default', retry: 3

        def perform(email_id, mail_job_id, simulate_error = false)
          # エラーシミュレーション（30%の確率で失敗）
          if simulate_error && rand < 0.3
            raise StandardError, "Simulated error for testing"
          end
          
          email = Email.find(email_id)
          mail_job = MailJob.find(mail_job_id)
          
          # メール送信
          TestMailer.notification(email.email, email.name).deliver_now
          
          # 成功カウント更新
          mail_job.increment!(:sent_count)
          
          # 完了チェック
          if mail_job.sent_count + mail_job.failed_count >= mail_job.total_count
            mail_job.update!(status: :completed)
          end
          
        rescue StandardError => e
          # 失敗カウント更新
          mail_job = MailJob.find(mail_job_id)
          mail_job.increment!(:failed_count)
          
          # 完了チェック
          if mail_job.sent_count + mail_job.failed_count >= mail_job.total_count
            mail_job.update!(status: :failed)
          end
          
          raise e
        end
      end
      ```
    
    - app/mailers/test_mailer.rbを新規作成:
      ```ruby
      class TestMailer < ApplicationMailer
        default from: 'test@example.com'

        def notification(email, name)
          @name = name
          @email = email
          @timestamp = Time.current
          
          mail(
            to: email,
            subject: 'テスト送信メール'
          )
        end
      end
      ```
    
    - app/views/test_mailer/notification.html.erbを新規作成:
      ```erb
      <!DOCTYPE html>
      <html>
        <head>
          <meta charset="utf-8">
          <style>
            body { font-family: Arial, sans-serif; margin: 20px; }
            .header { background-color: #f0f0f0; padding: 10px; }
            .content { margin: 20px 0; }
          </style>
        </head>
        <body>
          <div class="header">
            <h2>テスト送信メール</h2>
          </div>
          <div class="content">
            <p>こんにちは、<%= @name %>さん</p>
            <p>これはK8S + Sidekiq学習用のテストメールです。</p>
            <p>送信時刻: <%= @timestamp.strftime('%Y-%m-%d %H:%M:%S') %></p>
          </div>
        </body>
      </html>
      ```
    
    - config/environments/development.rbに追加:
      ```ruby
      # メール設定
      config.action_mailer.delivery_method = :smtp
      config.action_mailer.smtp_settings = {
        address: ENV.fetch('SMTP_HOST', 'localhost'),
        port: ENV.fetch('SMTP_PORT', 1025),
        domain: 'localhost'
      }
      ```

- T-04: コントローラーとビュー実装
  - 概要: メール管理画面とバルク送信機能のWebインターフェースを実装
  - 理由: Sidekiq学習用の負荷生成とジョブ監視のためのUI が必要
  - 受け入れ条件: メール一覧表示、CSV登録、バルク送信ボタン動作、送信状況表示
  - 依存関係: T-03
  - ブランチ: feature/web-interface
  - 実装内容（詳細に、コピペするだけで作業が完了する粒度）
    
    - app/controllers/emails_controller.rbを新規作成:
      ```ruby
      class EmailsController < ApplicationController
        def index
          @emails = Email.order(:name).limit(100)
          @mail_jobs = MailJob.order(created_at: :desc).limit(10)
          @total_emails = Email.count
        end

        def create
          @email = Email.new(email_params)
          
          if @email.save
            redirect_to emails_path, notice: 'メールアドレスを追加しました'
          else
            redirect_to emails_path, alert: @email.errors.full_messages.join(', ')
          end
        end

        def destroy
          @email = Email.find(params[:id])
          @email.destroy
          redirect_to emails_path, notice: 'メールアドレスを削除しました'
        end

        def bulk_send
          count = params[:count].to_i
          simulate_error = params[:simulate_error] == 'true'
          
          if Email.count < count
            redirect_to emails_path, alert: "送信対象が不足しています（現在#{Email.count}件）"
            return
          end
          
          mail_job = MailJob.create!(
            total_count: count,
            status: :processing
          )
          
          # ランダムにメールアドレスを選択してジョブ作成
          Email.order('RANDOM()').limit(count).each do |email|
            MailSenderJob.perform_async(email.id, mail_job.id, simulate_error)
          end
          
          redirect_to emails_path, notice: "#{count}件の送信ジョブを作成しました"
        end

        def import_csv
          file = params[:csv_file]
          
          if file.blank?
            redirect_to emails_path, alert: 'CSVファイルを選択してください'
            return
          end
          
          count = 0
          CSV.foreach(file.path, headers: true) do |row|
            Email.create(
              name: row['name'],
              email: row['email']
            )
            count += 1
          rescue => e
            # エラーは無視して続行
          end
          
          redirect_to emails_path, notice: "#{count}件のメールアドレスを登録しました"
        end

        private

        def email_params
          params.require(:email).permit(:name, :email)
        end
      end
      ```
    
    - app/views/layouts/application.html.erbを新規作成:
      ```erb
      <!DOCTYPE html>
      <html>
        <head>
          <title>Mail Worker K8S</title>
          <meta name="viewport" content="width=device-width,initial-scale=1">
          <%= csrf_meta_tags %>
          <%= csp_meta_tag %>
          
          <style>
            body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5; }
            .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; }
            .header { border-bottom: 2px solid #007bff; margin-bottom: 20px; padding-bottom: 10px; }
            .btn { padding: 8px 16px; margin: 4px; border: none; border-radius: 4px; cursor: pointer; text-decoration: none; display: inline-block; }
            .btn-primary { background-color: #007bff; color: white; }
            .btn-danger { background-color: #dc3545; color: white; }
            .btn-success { background-color: #28a745; color: white; }
            .btn-warning { background-color: #ffc107; color: black; }
            .table { width: 100%; border-collapse: collapse; margin: 20px 0; }
            .table th, .table td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
            .table th { background-color: #f8f9fa; }
            .form-group { margin: 10px 0; }
            .form-control { padding: 8px; border: 1px solid #ddd; border-radius: 4px; width: 200px; }
            .alert { padding: 10px; margin: 10px 0; border-radius: 4px; }
            .alert-success { background-color: #d4edda; color: #155724; }
            .alert-danger { background-color: #f8d7da; color: #721c24; }
            .progress { background-color: #e9ecef; border-radius: 4px; height: 20px; }
            .progress-bar { background-color: #007bff; height: 100%; border-radius: 4px; transition: width 0.3s; }
          </style>
        </head>

        <body>
          <div class="container">
            <div class="header">
              <h1>Mail Worker K8S - 学習用メール送信システム</h1>
              <p>Sidekiq + Kubernetes + Argo CD 学習環境</p>
            </div>
            
            <% if notice %>
              <div class="alert alert-success"><%= notice %></div>
            <% end %>
            
            <% if alert %>
              <div class="alert alert-danger"><%= alert %></div>
            <% end %>
            
            <%= yield %>
          </div>
        </body>
      </html>
      ```
    
    - app/views/emails/index.html.erbを新規作成:
      ```erb
      <div style="display: flex; gap: 20px;">
        <!-- 左側: メール管理 -->
        <div style="flex: 1;">
          <h2>メールアドレス管理</h2>
          
          <!-- 新規追加フォーム -->
          <%= form_with model: Email.new, url: emails_path, local: true do |f| %>
            <div class="form-group">
              <%= f.text_field :name, placeholder: "名前", class: "form-control" %>
              <%= f.email_field :email, placeholder: "メールアドレス", class: "form-control" %>
              <%= f.submit "追加", class: "btn btn-primary" %>
            </div>
          <% end %>
          
          <!-- CSV一括登録 -->
          <%= form_with url: import_csv_emails_path, multipart: true, local: true do |f| %>
            <div class="form-group">
              <%= f.file_field :csv_file, accept: ".csv", class: "form-control" %>
              <%= f.submit "CSV一括登録", class: "btn btn-success" %>
            </div>
          <% end %>
          
          <p>登録済み: <strong><%= @total_emails %>件</strong></p>
          
          <!-- メール一覧 -->
          <table class="table">
            <thead>
              <tr>
                <th>名前</th>
                <th>メールアドレス</th>
                <th>操作</th>
              </tr>
            </thead>
            <tbody>
              <% @emails.each do |email| %>
                <tr>
                  <td><%= email.name %></td>
                  <td><%= email.email %></td>
                  <td>
                    <%= link_to "削除", email_path(email), method: :delete, 
                        class: "btn btn-danger", 
                        confirm: "削除しますか？" %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
        
        <!-- 右側: バルク送信 -->
        <div style="flex: 1;">
          <h2>バルク送信テスト</h2>
          
          <!-- 負荷テストボタン -->
          <div class="form-group">
            <h3>Sidekiq学習用</h3>
            <%= link_to "1,000件送信", bulk_send_emails_path(count: 1000), 
                method: :post, class: "btn btn-primary" %>
            <%= link_to "5,000件送信", bulk_send_emails_path(count: 5000), 
                method: :post, class: "btn btn-warning" %>
            <%= link_to "10,000件送信", bulk_send_emails_path(count: 10000), 
                method: :post, class: "btn btn-danger" %>
          </div>
          
          <div class="form-group">
            <h3>エラーシミュレーション</h3>
            <%= link_to "1,000件送信（エラー30%）", bulk_send_emails_path(count: 1000, simulate_error: true), 
                method: :post, class: "btn btn-warning" %>
          </div>
          
          <!-- 管理画面リンク -->
          <div class="form-group">
            <h3>管理画面</h3>
            <%= link_to "Sidekiq管理画面", "/sidekiq", target: "_blank", class: "btn btn-success" %>
          </div>
          
          <!-- 送信履歴 -->
          <h3>送信履歴</h3>
          <table class="table">
            <thead>
              <tr>
                <th>作成日時</th>
                <th>総数</th>
                <th>成功</th>
                <th>失敗</th>
                <th>進捗</th>
                <th>状態</th>
              </tr>
            </thead>
            <tbody>
              <% @mail_jobs.each do |job| %>
                <tr>
                  <td><%= job.created_at.strftime('%m/%d %H:%M') %></td>
                  <td><%= job.total_count %></td>
                  <td><%= job.sent_count %></td>
                  <td><%= job.failed_count %></td>
                  <td>
                    <div class="progress">
                      <div class="progress-bar" style="width: <%= job.progress_percentage %>%">
                        <%= job.progress_percentage %>%
                      </div>
                    </div>
                  </td>
                  <td>
                    <span class="btn btn-<%= job.completed? ? 'success' : job.failed? ? 'danger' : 'warning' %>">
                      <%= job.status.humanize %>
                    </span>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
      ```

- T-05: Kubernetes基盤構築
  - 概要: K8S用のDeployment、Service、HPA設定ファイルを作成
  - 理由: HPA学習とArgo CD連携のためのK8S環境が必要
  - 受け入れ条件: 全Podが正常起動、HPA設定適用、サービス間通信確認
  - 依存関係: T-04
  - ブランチ: feature/kubernetes-manifests
  - 実装内容（詳細に、コピペするだけで作業が完了する粒度）
    
    - k8s/base/redis-deployment.yamlを新規作成:
      ```yaml
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: redis
        labels:
          app: redis
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
              resources:
                requests:
                  cpu: 50m
                  memory: 64Mi
                limits:
                  cpu: 200m
                  memory: 256Mi
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
        type: ClusterIP
      ```
    
    - k8s/base/mailcatcher-deployment.yamlを新規作成:
      ```yaml
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: mailcatcher
        labels:
          app: mailcatcher
      spec:
        replicas: 1
        selector:
          matchLabels:
            app: mailcatcher
        template:
          metadata:
            labels:
              app: mailcatcher
          spec:
            containers:
            - name: mailcatcher
              image: schickling/mailcatcher
              ports:
              - containerPort: 1080
              - containerPort: 1025
              resources:
                requests:
                  cpu: 50m
                  memory: 64Mi
                limits:
                  cpu: 100m
                  memory: 128Mi
      ---
      apiVersion: v1
      kind: Service
      metadata:
        name: mailcatcher
      spec:
        selector:
          app: mailcatcher
        ports:
        - name: web
          port: 1080
          targetPort: 1080
        - name: smtp
          port: 1025
          targetPort: 1025
        type: ClusterIP
      ```
    
    - k8s/base/web-deployment.yamlを新規作成:
      ```yaml
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: mail-web
        labels:
          app: mail-web
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
              - name: RAILS_ENV
                value: "production"
              resources:
                requests:
                  cpu: 100m
                  memory: 128Mi
                limits:
                  cpu: 500m
                  memory: 512Mi
              readinessProbe:
                httpGet:
                  path: /
                  port: 3000
                initialDelaySeconds: 30
                periodSeconds: 10
              livenessProbe:
                httpGet:
                  path: /
                  port: 3000
                initialDelaySeconds: 60
                periodSeconds: 30
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
    
    - k8s/base/sidekiq-deployment.yamlを新規作成:
      ```yaml
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: mail-sidekiq
        labels:
          app: mail-sidekiq
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
              - name: RAILS_ENV
                value: "production"
              resources:
                requests:
                  cpu: 100m
                  memory: 128Mi
                limits:
                  cpu: 1000m
                  memory: 512Mi
              livenessProbe:
                exec:
                  command:
                  - pgrep
                  - -f
                  - sidekiq
                initialDelaySeconds: 30
                periodSeconds: 30
      ```
    
    - k8s/base/hpa.yamlを新規作成:
      ```yaml
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
            - type: Pods
              value: 2
              periodSeconds: 60
          scaleDown:
            stabilizationWindowSeconds: 300
            policies:
            - type: Percent
              value: 50
              periodSeconds: 60
      ```
              - name: REDIS_URL
                value: "redis://redis:6379/0"
              - name: SMTP_HOST
                value: "mailcatcher"
              - name: SMTP_PORT
                value: "1025"
              - name: RAILS_ENV
                value: "production"
              resources:
                requests:
                  cpu: 100m
                  memory: 128Mi
                limits:
                  cpu: 1000m
                  memory: 512Mi
              livenessProbe:
                exec:
                  command:
                  - pgrep
                  - -f
                  - sidekiq
                initialDelaySeconds: 30
                periodSeconds: 30
      ```
    
    - k8s/base/hpa.yamlを新規作成:
      ```yaml
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
            - type: Pods
              value: 2
              periodSeconds: 60
          scaleDown:
            stabilizationWindowSeconds: 300
            policies:
            - type: Percent
              value: 50
              periodSeconds: 60
      ```

- T-06: Argo CD設定とGitOps環境構築
  - 概要: Argo CDのApplication定義とGitOps環境を構築
  - 理由: Argo CD GUI/CLI学習とGitOpsワークフローの実践が必要
  - 受け入れ条件: Argo CDでアプリケーション同期成功、GUI/CLI操作確認、ロールバック動作確認
  - 依存関係: T-05
  - ブランチ: feature/argocd-setup
  - 実装内容（詳細に、コピペするだけで作業が完了する粒度）
    
    - argocd/application.yamlを新規作成:
      ```yaml
      apiVersion: argoproj.io/v1alpha1
      kind: Application
      metadata:
        name: mail-app
        namespace: argocd
        finalizers:
          - resources-finalizer.argocd.argoproj.io
      spec:
        project: default
        source:
          repoURL: https://github.com/your-username/mail-worker-k8s
          targetRevision: HEAD
          path: k8s/base
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
    
    - scripts/setup-argocd.shを新規作成:
      ```bash
      #!/bin/bash
      set -e

      echo "=== Argo CD セットアップ開始 ==="

      # Argo CD namespace作成
      kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

      # Argo CD インストール
      kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

      # Argo CD Serverの起動待機
      echo "Argo CD Serverの起動を待機中..."
      kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

      # 初期パスワード取得
      echo "=== Argo CD 初期設定情報 ==="
      echo "Username: admin"
      echo -n "Password: "
      kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
      echo ""

      # Port Forward用のコマンド表示
      echo ""
      echo "=== アクセス方法 ==="
      echo "GUI: kubectl port-forward svc/argocd-server -n argocd 8080:443"
      echo "URL: https://localhost:8080"
      echo ""

      # CLI インストール確認
      if ! command -v argocd &> /dev/null; then
          echo "=== Argo CD CLI インストール ==="
          curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
          sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
          rm argocd-linux-amd64
          echo "Argo CD CLI インストール完了"
      fi

      echo "=== セットアップ完了 ==="
      ```
    
    - scripts/deploy-app.shを新規作成:
      ```bash
      #!/bin/bash
      set -e

      echo "=== アプリケーションデプロイ開始 ==="

      # Dockerイメージビルド
      echo "Dockerイメージをビルド中..."
      docker build -t mail-app:latest .

      # minikubeの場合はイメージをロード
      if command -v minikube &> /dev/null && minikube status &> /dev/null; then
          echo "minikubeにイメージをロード中..."
          minikube image load mail-app:latest
      fi

      # Argo CD Application作成
      echo "Argo CD Applicationを作成中..."
      kubectl apply -f argocd/application.yaml

      # 同期待機
      echo "アプリケーションの同期を待機中..."
      sleep 10

      # 状態確認
      echo "=== デプロイ状況確認 ==="
      kubectl get pods -n mail-app
      kubectl get svc -n mail-app
      kubectl get hpa -n mail-app

      echo ""
      echo "=== アクセス情報 ==="
      echo "Web App: kubectl port-forward svc/mail-web -n mail-app 3000:80"
      echo "MailCatcher: kubectl port-forward svc/mailcatcher -n mail-app 1080:1080"
      echo "Sidekiq: http://localhost:3000/sidekiq"
      echo ""

      echo "=== デプロイ完了 ==="
      ```
    
    - scripts/learning-scenarios.shを新規作成:
      ```bash
      #!/bin/bash

      echo "=== 学習シナリオ実行スクリプト ==="
      echo ""

      case "$1" in
        "sidekiq")
          echo "=== Sidekiq学習シナリオ ==="
          echo "1. Web画面にアクセス: kubectl port-forward svc/mail-web -n mail-app 3000:80"
          echo "2. http://localhost:3000 でメール送信テスト"
          echo "3. http://localhost:3000/sidekiq でSidekiq管理画面確認"
          echo "4. 1000件送信ボタンでキュー確認"
          echo "5. エラーシミュレーションで失敗ジョブ確認"
          ;;
        "hpa")
          echo "=== HPA学習シナリオ ==="
          echo "1. 現在のPod数確認:"
          kubectl get pods -n mail-app -l app=mail-sidekiq
          echo ""
          echo "2. HPA状況確認:"
          kubectl get hpa -n mail-app
          echo ""
          echo "3. CPU使用率監視開始:"
          echo "   kubectl top pods -n mail-app -l app=mail-sidekiq --watch"
          echo ""
          echo "4. 負荷テスト実行後、Pod数の変化を確認"
          ;;
        "argocd")
          echo "=== Argo CD学習シナリオ ==="
          echo "GUI操作:"
          echo "1. kubectl port-forward svc/argocd-server -n argocd 8080:443"
          echo "2. https://localhost:8080 でGUI確認"
          echo ""
          echo "CLI操作:"
          echo "1. ログイン: argocd login localhost:8080"
          echo "2. アプリ一覧: argocd app list"
          echo "3. 同期実行: argocd app sync mail-app"
          echo "4. 状況確認: argocd app get mail-app"
          ;;
        *)
          echo "使用方法: $0 [sidekiq|hpa|argocd]"
          echo ""
          echo "利用可能なシナリオ:"
          echo "  sidekiq - Sidekiqキュー管理学習"
          echo "  hpa     - HPA自動スケーリング学習"
          echo "  argocd  - Argo CD GUI/CLI操作学習"
          ;;
      esac
      ```

    - テスト実装 spec/jobs/mail_sender_job_spec.rbを新規作成:
      ```ruby
      require 'rails_helper'

      RSpec.describe MailSenderJob, type: :job do
        let(:email) { create(:email) }
        let(:mail_job) { create(:mail_job, total_count: 1) }

        describe '#perform' do
          it 'メール送信が成功する' do
            expect {
              described_class.new.perform(email.id, mail_job.id, false)
            }.to change { mail_job.reload.sent_count }.by(1)
          end

          it 'エラーシミュレーションで例外が発生する' do
            allow(rand).to receive(:rand).and_return(0.1) # 30%未満でエラー
            
            expect {
              described_class.new.perform(email.id, mail_job.id, true)
            }.to raise_error(StandardError, "Simulated error for testing")
          end
        end
      end
      ```

- T-07: Unleashフィーチャーフラグ統合
  - 概要: UnleashフィーチャーフラグシステムとRailsアプリケーションの連携を実装
  - 理由: フィーチャーフラグによる機能制御とA/Bテストの学習が必要
  - 受け入れ条件: Unleash管理画面アクセス、フラグ作成・切り替え、Railsアプリでのフラグ参照動作確認
  - 依存関係: T-06
  - ブランチ: feature/unleash-integration
  - 実装内容（詳細に、コピペするだけで作業が完了する粒度）
    
    - config/initializers/unleash.rbを新規作成:
      ```ruby
      Unleash.configure do |config|
        config.url = ENV.fetch('UNLEASH_URL', 'http://localhost:4242/api')
        config.app_name = 'mail-worker-k8s'
        config.instance_id = Socket.gethostname
        config.refresh_interval = 15
        config.metrics_interval = 60
        config.disable_client = Rails.env.test?
        config.logger = Rails.logger
      end
      ```
    
    - app/services/feature_flag_service.rbを新規作成:
      ```ruby
      class FeatureFlagService
        def self.enabled?(flag_name, context = {})
          return false if Rails.env.test?
          
          Unleash.is_enabled?(flag_name, context)
        rescue => e
          Rails.logger.error "Feature flag error: #{e.message}"
          false
        end
        
        def self.variant(flag_name, context = {})
          return 'disabled' if Rails.env.test?
          
          Unleash.get_variant(flag_name, context)
        rescue => e
          Rails.logger.error "Feature flag variant error: #{e.message}"
          'disabled'
        end
      end
      ```
    
    - app/controllers/emails_controller.rbにフィーチャーフラグ連携を追加:
      ```ruby
      def bulk_send
        # フィーチャーフラグチェック
        unless FeatureFlagService.enabled?('bulk_send_feature')
          redirect_to emails_path, alert: 'バルク送信機能は現在無効です'
          return
        end
        
        count = params[:count].to_i
        simulate_error = params[:simulate_error] == 'true'
        
        # A/Bテスト用のバリアント取得
        variant = FeatureFlagService.variant('send_strategy')
        use_priority_queue = variant == 'priority'
        
        if Email.count < count
          redirect_to emails_path, alert: "送信対象が不足しています（現在#{Email.count}件）"
          return
        end
        
        mail_job = MailJob.create!(
          total_count: count,
          status: :processing
        )
        
        # フィーチャーフラグによるキュー切り替え
        queue_name = use_priority_queue ? 'high' : 'default'
        
        Email.order('RANDOM()').limit(count).each do |email|
          MailSenderJob.set(queue: queue_name).perform_async(email.id, mail_job.id, simulate_error)
        end
        
        redirect_to emails_path, notice: "#{count}件の送信ジョブを作成しました（キュー: #{queue_name}）"
      end
      ```
    
    - app/views/emails/index.html.erbにUnleash管理画面リンクを追加:
      ```erb
      <!-- 管理画面リンク -->
      <div class="form-group">
        <h3>管理画面</h3>
        <%= link_to "Sidekiq管理画面", "/sidekiq", target: "_blank", class: "btn btn-success" %>
        <%= link_to "Unleash管理画面", "http://localhost:4242", target: "_blank", class: "btn btn-primary" %>
      </div>
      ```
    
    - k8s/base/unleash-deployment.yamlを新規作成:
      ```yaml
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: unleash
        labels:
          app: unleash
      spec:
        replicas: 1
        selector:
          matchLabels:
            app: unleash
        template:
          metadata:
            labels:
              app: unleash
          spec:
            containers:
            - name: unleash
              image: unleashorg/unleash-server:latest
              ports:
              - containerPort: 4242
              env:
              - name: DATABASE_URL
                value: "sqlite:///unleash.db"
              - name: DATABASE_SSL
                value: "false"
              resources:
                requests:
                  cpu: 100m
                  memory: 256Mi
                limits:
                  cpu: 500m
                  memory: 512Mi
              volumeMounts:
              - name: unleash-data
                mountPath: /unleash
            volumes:
            - name: unleash-data
              emptyDir: {}
      ---
      apiVersion: v1
      kind: Service
      metadata:
        name: unleash
      spec:
        selector:
          app: unleash
        ports:
        - port: 4242
          targetPort: 4242
        type: ClusterIP
      ```
    
    - scripts/learning-scenarios.shにUnleashシナリオを追加:
      ```bash
        "unleash")
          echo "=== Unleash学習シナリオ ==="
          echo "1. 管理画面アクセス: kubectl port-forward svc/unleash -n mail-app 4242:4242"
          echo "2. http://localhost:4242 でUnleash管理画面確認"
          echo "3. フィーチャーフラグ作成: bulk_send_feature"
          echo "4. バリアント作成: send_strategy (default/priority)"
          echo "5. RailsアプリでフラグON/OFF動作確認"
          ;;
      ```
      
      使用方法に追加:
      ```bash
          echo "利用可能なシナリオ:"
          echo "  sidekiq - Sidekiqキュー管理学習"
          echo "  hpa     - HPA自動スケーリング学習"
          echo "  argocd  - Argo CD GUI/CLI操作学習"
          echo "  unleash - Unleashフィーチャーフラグ学習"
      ```

- T-08: Argo Rollouts統合
  - 概要: Argo Rolloutsによるカナリアデプロイメントとブルー/グリーンデプロイメント戦略を実装
  - 理由: 高度なデプロイメント戦略とプログレッシブデリバリーの学習が必要
  - 受け入れ条件: Rollout作成・実行、カナリア段階的デプロイ、自動ロールバック動作確認
  - 依存関係: T-07
  - ブランチ: feature/argo-rollouts
  - 実装内容（詳細に、コピペするだけで作業が完了する粒度）
    
    - k8s/rollouts/web-rollout.yamlを新規作成:
      ```yaml
      apiVersion: argoproj.io/v1alpha1
      kind: Rollout
      metadata:
        name: mail-web-rollout
        labels:
          app: mail-web
      spec:
        replicas: 3
        strategy:
          canary:
            steps:
            - setWeight: 20
            - pause: {duration: 30s}
            - setWeight: 50
            - pause: {duration: 30s}
            - setWeight: 80
            - pause: {duration: 30s}
            canaryService: mail-web-canary
            stableService: mail-web-stable
            trafficRouting:
              nginx:
                stableIngress: mail-web-ingress
            analysis:
              templates:
              - templateName: success-rate
              args:
              - name: service-name
                value: mail-web-canary
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
              - name: RAILS_ENV
                value: "production"
              - name: DEPLOYMENT_VERSION
                value: "v1.0.0"
              resources:
                requests:
                  cpu: 100m
                  memory: 128Mi
                limits:
                  cpu: 500m
                  memory: 512Mi
              readinessProbe:
                httpGet:
                  path: /health
                  port: 3000
                initialDelaySeconds: 10
                periodSeconds: 5
              livenessProbe:
                httpGet:
                  path: /health
                  port: 3000
                initialDelaySeconds: 30
                periodSeconds: 10
      ```
    
    - k8s/rollouts/services.yamlを新規作成:
      ```yaml
      apiVersion: v1
      kind: Service
      metadata:
        name: mail-web-stable
      spec:
        selector:
          app: mail-web
        ports:
        - port: 80
          targetPort: 3000
        type: ClusterIP
      ---
      apiVersion: v1
      kind: Service
      metadata:
        name: mail-web-canary
      spec:
        selector:
          app: mail-web
        ports:
        - port: 80
          targetPort: 3000
        type: ClusterIP
      ---
      apiVersion: networking.k8s.io/v1
      kind: Ingress
      metadata:
        name: mail-web-ingress
        annotations:
          nginx.ingress.kubernetes.io/rewrite-target: /
      spec:
        rules:
        - host: mail-app.local
          http:
            paths:
            - path: /
              pathType: Prefix
              backend:
                service:
                  name: mail-web-stable
                  port:
                    number: 80
      ```
    
    - k8s/rollouts/analysis-template.yamlを新規作成:
      ```yaml
      apiVersion: argoproj.io/v1alpha1
      kind: AnalysisTemplate
      metadata:
        name: success-rate
      spec:
        args:
        - name: service-name
        metrics:
        - name: success-rate
          interval: 30s
          count: 3
          successCondition: result[0] >= 0.95
          provider:
            prometheus:
              address: http://prometheus:9090
              query: |
                sum(rate(http_requests_total{service="{{args.service-name}}",status!~"5.."}[2m])) /
                sum(rate(http_requests_total{service="{{args.service-name}}"}[2m]))
        - name: avg-response-time
          interval: 30s
          count: 3
          successCondition: result[0] < 0.5
          provider:
            prometheus:
              address: http://prometheus:9090
              query: |
                histogram_quantile(0.95,
                  sum(rate(http_request_duration_seconds_bucket{service="{{args.service-name}}"}[2m])) by (le)
                )
      ```
    
    - app/controllers/application_controller.rbにヘルスチェック追加:
      ```ruby
      class ApplicationController < ActionController::Base
        def health
          render json: {
            status: 'ok',
            version: ENV.fetch('DEPLOYMENT_VERSION', 'unknown'),
            timestamp: Time.current.iso8601,
            checks: {
              database: database_check,
              redis: redis_check
            }
          }
        end

        private

        def database_check
          ActiveRecord::Base.connection.execute('SELECT 1')
          'ok'
        rescue => e
          'error'
        end

        def redis_check
          Sidekiq.redis { |conn| conn.ping }
          'ok'
        rescue => e
          'error'
        end
      end
      ```
    
    - config/routes.rbにヘルスチェックルート追加:
      ```ruby
      Rails.application.routes.draw do
        require 'sidekiq/web'
        mount Sidekiq::Web => '/sidekiq'
        
        get '/health', to: 'application#health'
        
        root 'emails#index'
        resources :emails, only: [:index, :create, :destroy] do
          collection do
            post :bulk_send
            post :import_csv
          end
        end
      end
      ```
    
    - scripts/setup-rollouts.shを新規作成:
      ```bash
      #!/bin/bash
      set -e

      echo "=== Argo Rollouts セットアップ開始 ==="

      # Argo Rollouts namespace作成
      kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -

      # Argo Rollouts インストール
      kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

      # Argo Rollouts Controllerの起動待機
      echo "Argo Rollouts Controllerの起動を待機中..."
      kubectl wait --for=condition=available --timeout=300s deployment/argo-rollouts-controller -n argo-rollouts

      # kubectl plugin インストール確認
      if ! kubectl argo rollouts version &> /dev/null; then
          echo "=== Argo Rollouts kubectl plugin インストール ==="
          curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
          chmod +x ./kubectl-argo-rollouts-linux-amd64
          sudo mv ./kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts
          echo "kubectl plugin インストール完了"
      fi

      echo "=== Rollouts Dashboard セットアップ ==="
      echo "Dashboard起動: kubectl argo rollouts dashboard"
      echo "URL: http://localhost:3100"
      echo ""

      echo "=== セットアップ完了 ==="
      ```
    
    - scripts/deploy-rollout.shを新規作成:
      ```bash
      #!/bin/bash
      set -e

      echo "=== Rollout デプロイ開始 ==="

      # 既存のDeploymentを削除（Rolloutと競合するため）
      kubectl delete deployment mail-web -n mail-app --ignore-not-found=true

      # Rollout関連リソースをデプロイ
      echo "Rolloutリソースを作成中..."
      kubectl apply -f k8s/rollouts/ -n mail-app

      # Rollout状況確認
      echo "=== Rollout状況確認 ==="
      kubectl argo rollouts get rollout mail-web-rollout -n mail-app

      echo ""
      echo "=== 管理コマンド ==="
      echo "状況確認: kubectl argo rollouts get rollout mail-web-rollout -n mail-app"
      echo "手動進行: kubectl argo rollouts promote mail-web-rollout -n mail-app"
      echo "ロールバック: kubectl argo rollouts undo mail-web-rollout -n mail-app"
      echo "Dashboard: kubectl argo rollouts dashboard"
      echo ""

      echo "=== デプロイ完了 ==="
      ```
    
    - scripts/rollout-scenarios.shを新規作成:
      ```bash
      #!/bin/bash

      echo "=== Rollout学習シナリオ実行スクリプト ==="
      echo ""

      case "$1" in
        "canary")
          echo "=== カナリアデプロイ学習シナリオ ==="
          echo "1. 新バージョンイメージ作成:"
          echo "   docker build -t mail-app:v2.0.0 --build-arg VERSION=v2.0.0 ."
          echo "   minikube image load mail-app:v2.0.0"
          echo ""
          echo "2. Rollout更新:"
          echo "   kubectl argo rollouts set image mail-web-rollout web=mail-app:v2.0.0 -n mail-app"
          echo ""
          echo "3. 段階的デプロイ監視:"
          echo "   kubectl argo rollouts get rollout mail-web-rollout -n mail-app --watch"
          echo ""
          echo "4. 手動進行（必要に応じて）:"
          echo "   kubectl argo rollouts promote mail-web-rollout -n mail-app"
          ;;
        "bluegreen")
          echo "=== ブルー/グリーンデプロイ学習シナリオ ==="
          echo "1. ブルー/グリーン戦略に変更:"
          echo "   # k8s/rollouts/web-rollout.yamlのstrategyをblueGreenに変更"
          echo ""
          echo "2. 新バージョンデプロイ:"
          echo "   kubectl argo rollouts set image mail-web-rollout web=mail-app:v3.0.0 -n mail-app"
          echo ""
          echo "3. プレビュー確認後、本番切り替え:"
          echo "   kubectl argo rollouts promote mail-web-rollout -n mail-app"
          ;;
        "rollback")
          echo "=== ロールバック学習シナリオ ==="
          echo "1. 現在のリビジョン確認:"
          kubectl argo rollouts history rollout mail-web-rollout -n mail-app
          echo ""
          echo "2. 前バージョンにロールバック:"
          echo "   kubectl argo rollouts undo mail-web-rollout -n mail-app"
          echo ""
          echo "3. 特定リビジョンにロールバック:"
          echo "   kubectl argo rollouts undo mail-web-rollout --to-revision=1 -n mail-app"
          ;;
        "analysis")
          echo "=== 自動分析学習シナリオ ==="
          echo "1. Prometheus設定（メトリクス収集用）"
          echo "2. AnalysisTemplateでメトリクス閾値設定"
          echo "3. 自動ロールバック動作確認"
          echo "4. 成功条件・失敗条件のテスト"
          ;;
        *)
          echo "使用方法: $0 [canary|bluegreen|rollback|analysis]"
          echo ""
          echo "利用可能なシナリオ:"
          echo "  canary    - カナリアデプロイメント学習"
          echo "  bluegreen - ブルー/グリーンデプロイメント学習"
          echo "  rollback  - ロールバック操作学習"
          echo "  analysis  - 自動分析・ロールバック学習"
          ;;
      esac
      ```
    
    - scripts/learning-scenarios.shにRolloutsシナリオを追加:
      ```bash
        "rollouts")
          echo "=== Argo Rollouts学習シナリオ ==="
          echo "1. Dashboard起動: kubectl argo rollouts dashboard"
          echo "2. http://localhost:3100 でRollouts管理画面確認"
          echo "3. カナリアデプロイ実行: ./scripts/rollout-scenarios.sh canary"
          echo "4. ロールバック操作: ./scripts/rollout-scenarios.sh rollback"
          echo "5. 詳細シナリオ: ./scripts/rollout-scenarios.sh [canary|bluegreen|rollback|analysis]"
          ;;
      ```
      
      使用方法に追加:
      ```bash
          echo "利用可能なシナリオ:"
          echo "  sidekiq  - Sidekiqキュー管理学習"
          echo "  hpa      - HPA自動スケーリング学習"
          echo "  argocd   - Argo CD GUI/CLI操作学習"
          echo "  unleash  - Unleashフィーチャーフラグ学習"
          echo "  rollouts - Argo Rolloutsデプロイ戦略学習"
      ```