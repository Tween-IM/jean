# frozen_string_literal: true

require "test_helper"

class CircuitBreakerServiceTest < ActiveSupport::TestCase
  class FakeClientError < StandardError; end
  class FakeServerError < StandardError; end

  setup do
    @breaker = CircuitBreakerService.new("transfers:test")
    @breaker.client_error_class = FakeClientError
  end

  test "client errors do not open the circuit" do
    5.times do
      assert_raises(FakeClientError) do
        @breaker.call { raise FakeClientError, "missing scope" }
      end
    end

    # Circuit should still be closed: a subsequent call runs normally.
    result = @breaker.call { :ok }
    assert_equal :ok, result
  end

  test "server errors open the circuit after the threshold" do
    5.times do
      assert_raises(FakeServerError) do
        @breaker.call { raise FakeServerError, "boom" }
      end
    end

    # Now the circuit is open and rejects calls.
    assert_raises(CircuitBreakerService::CircuitBreakerError) do
      @breaker.call { :ok }
    end
  end
end
