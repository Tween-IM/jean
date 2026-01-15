ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"
require "minitest"

class ActiveSupport::TestCase
  # Run tests in parallel with specified workers
  # parallelize(workers: :number_of_processors)

  # Enable sessions for integration tests
  include ActionDispatch::TestProcess # Disabled for compatibility

  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  # fixtures :all

  # Add more helper methods to be used by all tests here...

  teardown do
    # Clean up environment variables that might affect other tests
    %w[MATRIX_ACCESS_TOKEN MATRIX_API_URL TMCP_PRIVATE_KEY MAS_CLIENT_ID MAS_CLIENT_SECRET].each do |key|
      ENV.delete(key)
    end
  end
end
