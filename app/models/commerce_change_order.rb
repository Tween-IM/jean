# frozen_string_literal: true

# An accepted amendment to a service order's scope, price or deadline.
# No price or scope change takes effect until the customer accepts it.
class CommerceChangeOrder < ApplicationRecord
  STATUSES = %w[proposed accepted declined expired].freeze

  belongs_to :commerce_order

  before_validation :assign_change_order_id

  validates :change_order_id, :proposer_user_id, presence: true
  validates :change_order_id, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :amount_delta_cents, numericality: { only_integer: true }

  def accepted?
    status == "accepted"
  end

  private

  def assign_change_order_id
    return if change_order_id.present?

    self.change_order_id = "cho_#{SecureRandom.alphanumeric(12).downcase}"
  end
end
