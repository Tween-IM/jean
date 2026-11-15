class AdminAuditEvent < ApplicationRecord
  validates :actor_matrix_id, :action, :outcome, presence: true
  validates :outcome, inclusion: { in: %w[pending success failed unknown] }

  def self.safe_details(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, item), result|
        next if key.to_s.match?(/password|secret|token|pin|otp|credit_card|ssn|key|result|document/i)
        result[key.to_s] = safe_details(item)
      end
    when Array then value.map { |item| safe_details(item) }
    else value
    end
  end
end
