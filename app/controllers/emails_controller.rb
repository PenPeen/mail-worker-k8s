require 'csv'

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
    email_ids = Email.order('RANDOM()').limit(count).pluck(:id)
    email_ids.each do |email_id|
      MailSenderJob.perform_async(email_id, mail_job.id, simulate_error)
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
    errors = []

    begin
      CSV.foreach(file.path, headers: true, encoding: 'UTF-8') do |row|
        next if row['name'].blank? || row['email'].blank?

        email = Email.new(
          name: row['name'].strip,
          email: row['email'].strip.downcase
        )

        if email.save
          count += 1
        else
          errors << "#{row['email']}: #{email.errors.full_messages.join(', ')}"
        end
      end
    rescue CSV::MalformedCSVError => e
      redirect_to emails_path, alert: 'CSVファイルの形式が不正です'
      return
    rescue => e
      redirect_to emails_path, alert: "ファイル処理エラー: #{e.message}"
      return
    end

    message = "#{count}件のメールアドレスを登録しました"
    message += ". エラー: #{errors.size}件" if errors.any?

    redirect_to emails_path, notice: message
  end

  private

  def email_params
    params.require(:email).permit(:name, :email)
  end
end
