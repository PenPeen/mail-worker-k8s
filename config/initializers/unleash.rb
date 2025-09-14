Unleash.configure do |config|
  config.url = ENV.fetch('UNLEASH_URL', 'http://localhost:8242/api')
  config.app_name = 'mail-worker-k8s'
  config.instance_id = Socket.gethostname
  config.refresh_interval = 15
  config.metrics_interval = 60
  config.disable_client = Rails.env.test?
  config.logger = Rails.logger
end