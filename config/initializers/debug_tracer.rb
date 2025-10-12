# frozen_string_literal: true

require 'debug_tracer'

DebugTracer.configure do |config|
  # Enable debug tracing in development environment only
  config.enabled = Rails.env.development?

  # Output destination: :stdout or :file
  config.output_target = :file

  # File path for file output
  config.output_file_path = Rails.root.join('log', 'debug_trace.log')

  # Display options
  config.display_file_path = true
  config.display_line_number = true
  config.display_method_name = true
end
