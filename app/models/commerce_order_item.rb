# frozen_string_literal: true

class CommerceOrderItem < ApplicationRecord
  belongs_to :commerce_order
  has_one :commerce_procurement, dependent: :destroy
  # The listing this line was bought from, by its own id. Used to freeze the
  # supplier snapshot below and to link an order back to its source.
  belongs_to :product, class_name: "CommerceProduct", foreign_key: :product_id,
                       primary_key: :product_id, optional: true

  before_validation :snapshot_supplier
  after_create :open_procurement!

  validates :sku_id, :product_id, :title, :currency, presence: true
  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price_cents, :line_total_cents, numericality: { greater_than_or_equal_to: 0 }

  # A line the platform sells has to be bought from somewhere before it can be
  # delivered, so it opens a procurement job. A merchant fulfilling their own
  # order already knows where their stock is.
  #
  # Nothing is bought at import time, and nothing is bought for an order that
  # has not been paid for: the guard below is what keeps an abandoned checkout
  # out of the sourcing queue. A line added to an order that is already paid
  # still opens one immediately.
  def open_procurement!
    return nil unless commerce_order.commerce_merchant.system_owned?
    return nil unless commerce_order.status == "paid"
    return commerce_procurement if commerce_procurement.present?

    create_commerce_procurement!(
      status: "pending",
      supplier_name: supplier_name,
      supplier_platform: supplier_platform,
      supplier_url: supplier_url,
      currency: currency
    )
  end

  private

  # Where this line has to be bought from, copied at purchase time. A
  # re-import rewrites the listing's supplier freely; an order has to keep
  # recording where *that* order was meant to come from.
  def snapshot_supplier
    return if supplier_name.present?

    source = product
    return if source.nil?

    self.brand ||= source.brand
    self.supplier_name ||= source.supplier_name
    self.supplier_id ||= source.supplier_id
    # A listing that never had its supplier lifted out of the payload still
    # knows which marketplace it came from and where it lives there.
    self.supplier_platform ||= source.supplier_platform.presence || source.source_platform.presence
    self.supplier_url ||= source.supplier_url.presence || source.source_url.presence
    self.source_price_cents ||= source.source_price_cents
  end
end
