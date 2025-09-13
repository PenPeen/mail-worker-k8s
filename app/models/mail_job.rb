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