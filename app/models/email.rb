class Email < ApplicationRecord
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true

  scope :random_sample, ->(count) { order('RANDOM()').limit(count) }
end