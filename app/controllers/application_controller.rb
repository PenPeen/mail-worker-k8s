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
