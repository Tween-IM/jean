# frozen_string_literal: true

require "test_helper"

class WalletServiceTest < ActiveSupport::TestCase
  setup do
    # Clear circuit breakers before each test
    WalletService::CIRCUIT_BREAKERS.clear
    WalletService::CIRCUIT_BREAKER_ACCESS_TIMES.clear
  end

  teardown do
    # Clean up after tests
    WalletService::CIRCUIT_BREAKERS.clear
    WalletService::CIRCUIT_BREAKER_ACCESS_TIMES.clear
  end

  # ============================================================================
  # Circuit Breaker Tests
  # ============================================================================

  test "get_circuit_breaker returns a circuit breaker for user and operation" do
    cb = WalletService.get_circuit_breaker("user_123", :balance)
    assert_instance_of CircuitBreakerService, cb
    # Circuit breaker should be stored with the correct key
    assert WalletService::CIRCUIT_BREAKERS.key?("user_123:balance")
  end

  test "get_circuit_breaker returns same instance for same user and operation" do
    cb1 = WalletService.get_circuit_breaker("user_123", :balance)
    cb2 = WalletService.get_circuit_breaker("user_123", :balance)
    assert_equal cb1.object_id, cb2.object_id
  end

  test "get_circuit_breaker returns different instances for different users" do
    cb1 = WalletService.get_circuit_breaker("user_123", :balance)
    cb2 = WalletService.get_circuit_breaker("user_456", :balance)
    assert_not_equal cb1.object_id, cb2.object_id
  end

  test "get_circuit_breaker returns different instances for different operations" do
    cb1 = WalletService.get_circuit_breaker("user_123", :balance)
    cb2 = WalletService.get_circuit_breaker("user_123", :transfers)
    assert_not_equal cb1.object_id, cb2.object_id
  end

  test "get_circuit_breaker is thread-safe" do
    threads = []
    circuit_breakers = []
    mutex = Mutex.new

    10.times do
      threads << Thread.new do
        cb = WalletService.get_circuit_breaker("thread_test_user", :balance)
        mutex.synchronize { circuit_breakers << cb.object_id }
      end
    end

    threads.each(&:join)

    # All threads should have gotten the same circuit breaker instance
    assert_equal 1, circuit_breakers.uniq.size
  end

  test "get_circuit_breaker updates access time" do
    key = "user_123:balance"

    # Get initial access time (nil if not set)
    initial_time = WalletService::CIRCUIT_BREAKER_ACCESS_TIMES[key]
    assert_nil initial_time

    # Get circuit breaker
    WalletService.get_circuit_breaker("user_123", :balance)

    # Access time should be set
    access_time = WalletService::CIRCUIT_BREAKER_ACCESS_TIMES[key]
    assert_not_nil access_time
    assert_in_delta Time.current.to_f, access_time, 1.0
  end

  test "reset_circuit_breakers_for_user removes all circuit breakers for user" do
    # Create circuit breakers for different operations
    WalletService.get_circuit_breaker("user_123", :balance)
    WalletService.get_circuit_breaker("user_123", :transfers)
    WalletService.get_circuit_breaker("user_123", :payments)

    # Verify they exist
    assert_equal 3, WalletService::CIRCUIT_BREAKERS.size

    # Reset for user
    WalletService.reset_circuit_breakers_for_user("user_123")

    # Verify they're gone
    assert_equal 0, WalletService::CIRCUIT_BREAKERS.size
  end

  test "reset_circuit_breakers_for_user does not affect other users" do
    # Create circuit breakers for multiple users
    WalletService.get_circuit_breaker("user_123", :balance)
    WalletService.get_circuit_breaker("user_456", :balance)

    assert_equal 2, WalletService::CIRCUIT_BREAKERS.size

    # Reset only user_123
    WalletService.reset_circuit_breakers_for_user("user_123")

    # user_456's circuit breaker should still exist
    assert_equal 1, WalletService::CIRCUIT_BREAKERS.size
    assert WalletService::CIRCUIT_BREAKERS.key?("user_456:balance")
  end

  test "circuit_breaker_stats returns correct statistics" do
    # Create some circuit breakers
    WalletService.get_circuit_breaker("user_1", :balance)
    WalletService.get_circuit_breaker("user_2", :balance)
    WalletService.get_circuit_breaker("user_3", :transfers)

    stats = WalletService.circuit_breaker_stats

    assert_equal 3, stats[:total_circuit_breakers]
    assert_equal 10_000, stats[:max_allowed]
    assert_equal({ "balance" => 2, "transfers" => 1 }, stats[:operations])
  end

  # ============================================================================
  # extract_user_id_from_tep Tests
  # ============================================================================

  test "extract_user_id_from_tep returns anonymous for blank token" do
    assert_equal "anonymous", WalletService.extract_user_id_from_tep(nil)
    assert_equal "anonymous", WalletService.extract_user_id_from_tep("")
    assert_equal "anonymous", WalletService.extract_user_id_from_tep("   ")
  end

  test "extract_user_id_from_tep returns consistent hash for same token" do
    token = "test_token_123"
    id1 = WalletService.extract_user_id_from_tep(token)
    id2 = WalletService.extract_user_id_from_tep(token)

    assert_equal id1, id2
    assert_equal 32, id1.length
  end

  test "extract_user_id_from_tep returns different hashes for different tokens" do
    id1 = WalletService.extract_user_id_from_tep("token_1")
    id2 = WalletService.extract_user_id_from_tep("token_2")

    assert_not_equal id1, id2
  end
end
