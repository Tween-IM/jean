# frozen_string_literal: true

# One line of a platform-sold order: what has to be bought, from whom, and how
# far it has got.
#
# The platform is the seller of record for the mirrored catalogue, so a paid
# order for an imported listing is not a request to a merchant — it is the
# platform's own purchase. This is the record an operator works from: go to
# `supplier_url`, buy the item, then walk the status down to delivered.
class CommerceProcurement < ApplicationRecord
  STATUSES = %w[pending ordered received dispatched delivered cancelled failed].freeze
  OPEN_STATUSES = %w[pending ordered received dispatched].freeze
  #: Statuses that mean we have done something about it.
  ACTED_STATUSES = %w[ordered received dispatched delivered].freeze

  #: The steps an operator walks. Each one stamps its own timestamp.
  TRANSITIONS = {
    "pending" => %w[ordered cancelled failed],
    "ordered" => %w[received cancelled failed],
    "received" => %w[dispatched cancelled failed],
    "dispatched" => %w[delivered failed],
    "delivered" => [],
    "cancelled" => [],
    # A failed purchase is retryable: the next attempt is a fresh order.
    "failed" => %w[ordered cancelled]
  }.freeze

  STAMP_COLUMNS = {
    "ordered" => :ordered_at,
    "received" => :received_at,
    "dispatched" => :dispatched_at,
    "delivered" => :delivered_at
  }.freeze

  #: Everything an operator may correct on the way through.
  EDITABLE = %w[
    external_order_ref cost_cents currency courier tracking_number notes
    supplier_name supplier_platform supplier_url
  ].freeze

  belongs_to :commerce_order
  belongs_to :commerce_order_item

  validates :status, inclusion: { in: STATUSES }
  validates :cost_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # A purchase belongs to the order that caused it. Callers work from the line,
  # so the order is read off the line rather than made everybody's business.
  before_validation :derive_order_from_item, on: :create

  scope :open, -> { where(status: OPEN_STATUSES) }
  scope :awaiting_purchase, -> { where(status: "pending") }
  scope :delivered, -> { where(status: "delivered") }

  def next_statuses
    TRANSITIONS.fetch(status, [])
  end

  def open?
    OPEN_STATUSES.include?(status)
  end

  # `frozen?` reads oddly on a record, so name the two facts the queue needs.
  def purchased?
    ordered_at.present?
  end

  def settled?
    %w[delivered cancelled].include?(status)
  end

  #: Where an operator has to go to buy this.
  def buy_from
    supplier_url.presence || commerce_order_item.supplier_url.presence
  end

  #: Who we are buying from, falling back to whatever the line recorded.
  def supplier
    supplier_name.presence || commerce_order_item.supplier_name.presence
  end

  def marketplace
    supplier_platform.presence || commerce_order_item.supplier_platform.presence
  end

  private

  # Callers create a purchase from the line that needs buying, so the order is
  # read off the line rather than made every caller's business.
  def derive_order_from_item
    self.commerce_order ||= commerce_order_item&.commerce_order
  end
end
