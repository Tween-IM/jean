# frozen_string_literal: true

module Api::RateLimitable
  extend ActiveSupport::Concern

  DEFAULT_LIMIT = 60
  DEFAULT_WINDOW = 60 # seconds

  class_methods do
    def rate_limit(action:, limit: DEFAULT_LIMIT, window: DEFAULT_WINDOW, key: nil)
      before_action if: -> { action_name == action.to_s } do
        limit_key = rate_limit_key(key, action)
        current = rate_limit_count(limit_key, window)

        if current >= limit
          render json: {
            error: "rate_limit_exceeded",
            message: "Too many requests. Please try again in #{window} seconds.",
            retry_after: window
          }, status: :too_many_requests
          return false
        end

        increment_rate_limit(limit_key, window)
      end
    end
  end

  private

  def rate_limit_key(key_template, action)
    base = key_template || "#{controller_name}:#{action}:#{request.remote_ip}"
    base.gsub(":user_id", @current_user&.matrix_user_id || "anonymous")
        .gsub(":ip", request.remote_ip)
  end

  def rate_limit_count(key, window)
    Redis.current.get("rate_limit:#{key}").to_i
  rescue Redis::CannotConnectError
    0
  end

  def increment_rate_limit(key, window)
    Redis.current.multi do |pipeline|
      pipeline.incr("rate_limit:#{key}")
      pipeline.expire("rate_limit:#{key}", window)
    end
  rescue Redis::CannotConnectError
    # Fail open if Redis is unavailable
  end
end
