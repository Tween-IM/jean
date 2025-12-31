class CircuitBreakerService
  # TMCP Protocol Section 7.7: Circuit Breaker Pattern

  STATES = { closed: "CLOSED", open: "OPEN", half_open: "HALF_OPEN" }.freeze

  def initialize(service_name, failure_threshold: 5, recovery_timeout: 60, monitoring_window: 10)
    @service_name = service_name
    @failure_threshold = failure_threshold
    @recovery_timeout = recovery_timeout
    @monitoring_window = monitoring_window
    @state = STATES[:closed]
    @failures = 0
    @last_failure_time = nil
    @success_count = 0
  end

  def call(&block)
    case @state
    when STATES[:closed]
      execute_closed(&block)
    when STATES[:open]
      execute_open(&block)
    when STATES[:half_open]
      execute_half_open(&block)
    end
  end

  private

  def execute_closed(&block)
    begin
      result = block.call
      record_success
      result
    rescue => e
      record_failure
      raise e
    end
  end

  def execute_open(&block)
    if should_attempt_recovery?
      @state = STATES[:half_open]
      execute_half_open(&block)
    else
      raise CircuitBreakerError.new("Service #{@service_name} is currently unavailable", @state)
    end
  end

  def execute_half_open(&block)
    begin
      result = block.call
      @success_count += 1
      if @success_count >= 3 # Require 3 successes to close circuit
        @state = STATES[:closed]
        @failures = 0
        @success_count = 0
      end
      result
    rescue => e
      @state = STATES[:open]
      @last_failure_time = Time.current
      @success_count = 0
      raise e
    end
  end

  def record_success
    @failures = [ @failures - 1, 0 ].max
  end

  def record_failure
    @failures += 1
    @last_failure_time = Time.current
    if @failures >= @failure_threshold
      @state = STATES[:open]
    end
  end

  def should_attempt_recovery?
    return false unless @last_failure_time
    Time.current - @last_failure_time >= @recovery_timeout
  end

  def metrics
    {
      state: @state,
      failures_last_window: @failures,
      total_requests: @failures + @success_count,
      success_rate: calculate_success_rate,
      last_state_change: @last_failure_time&.iso8601
    }
  end

  def calculate_success_rate
    total = @failures + @success_count
    return 1.0 if total.zero?
    @success_count.to_f / total
  end

  class CircuitBreakerError < StandardError
    attr_reader :circuit_state

    def initialize(message, circuit_state)
      super(message)
      @circuit_state = circuit_state
    end
  end
end
