class HealthController < ApplicationController
  def check
    render json: {
      status: "healthy",
      timestamp: Time.current.iso8601,
      version: "TMCP v1.2.0",
      rails_version: Rails.version,
      ruby_version: RUBY_VERSION
    }
  end
end
