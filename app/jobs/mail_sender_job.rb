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