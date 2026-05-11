# frozen_string_literal: true

module Api
  class BaseController < ApplicationController
    # API endpoints are stateless and authenticated via tokens (TEP, OAuth2, etc.)
    # CSRF protection is not applicable for programmatic API clients.
    skip_before_action :verify_authenticity_token

    # Prevent session cookies from being set for API requests
    before_action :set_request_format

    private

    def set_request_format
      request.format = :json unless request.format.html?
    end
  end
end
