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