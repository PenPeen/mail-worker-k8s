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