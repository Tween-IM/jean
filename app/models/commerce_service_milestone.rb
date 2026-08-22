# frozen_string_literal: true

# A separately reviewable and releasable portion of a service order.
#
# Each milestone carries its own amount; releasing it posts a partial release
# to Tween Pay (amount-scoped) so `released + refunded + remaining = funded`
# is preserved on the protected payment.
class CommerceServiceMilestone < ApplicationRecord
  STATUSES = %w[pending in_progress submitted accepted released failed].freeze
  TRANSITIONS = {
    "pending" => %w[in_progress submitted failed],
    "in_progress" => %w[submitted failed],
    "submitted" => %w[accepted released failed],
    "accepted" => %w[released],
    "released" => [],
    "failed" => []
  }.freeze

  belongs_to :commerce_order

  before_validation :assign_milestone_id

  validates :milestone_id, :title, presence: true
  validates :milestone_id, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  before_update :validate_status_transition

  def released?
    status == "released"
  end

  private

  def assign_milestone_id
    return if milestone_id.present?

    self.milestone_id = "mil_#{SecureRandom.alphanumeric(12).downcase}"
  end

  def validate_status_transition
    return unless status_changed?
    return if TRANSITIONS.fetch(status_was, []).include?(status)

    errors.add(:status, "cannot transition from #{status_was} to #{status}")
    throw :abort
  end
end
