class ApplicationController < ActionController::Base
  def health
    render json: {
      status: 'ok',
      version: ENV.fetch('DEPLOYMENT_VERSION', 'unknown'),
      timestamp: Time.current.iso8601
    }
  end
end
