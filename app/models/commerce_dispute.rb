# frozen_string_literal: true

# Buyer-protection dispute case metadata. The financial freeze and resolution
# money movement lives in Tween Pay; this record holds the case, evidence and
# resolution policy for the order.
class CommerceDispute < ApplicationRecord
  REASONS = %w[
    item_not_received
    materially_different
    damaged_or_counterfeit
    prohibited_item
    wrong_quantity
    service_not_started
    service_incomplete
    deficient_workmanship
    unapproved_charges
  ].freeze

  STATUSES = %w[open under_review resolved closed].freeze

  belongs_to :commerce_order
  has_many :evidence,
    class_name: "CommerceDisputeEvidence",
    foreign_key: :commerce_dispute_id,
    dependent: :restrict_with_error

  before_validation :assign_dispute_id
  before_validation :assign_opened_at

  validates :dispute_id, :opened_by_user_id, :reason, presence: true
  validates :dispute_id, uniqueness: true
  validates :reason, inclusion: { in: REASONS }
  validates :status, inclusion: { in: STATUSES }

  def open?
    status == "open"
  end

  private

  def assign_dispute_id
    return if dispute_id.present?

    self.dispute_id = "disp_#{SecureRandom.alphanumeric(12).downcase}"
  end

  def assign_opened_at
    self.opened_at ||= Time.current
  end
end
