# frozen_string_literal: true
class CommerceOrder < ApplicationRecord
  belongs_to :commerce_merchant
  has_many :commerce_order_items, dependent: :destroy
  has_many :items, class_name: "CommerceOrderItem", dependent: :destroy
  has_many :commerce_fulfillments, dependent: :restrict_with_error
  has_many :commerce_change_orders, dependent: :restrict_with_error
  has_many :commerce_disputes, dependent: :restrict_with_error
  has_many :commerce_service_milestones, dependent: :restrict_with_error

  SOURCES = %w[storefront conversation service_booking].freeze
  PROTECTION_STATUSES = %w[not_eligible eligible active completed void].freeze
  FULFILLMENT_TYPES = %w[shipment local_delivery pickup service].freeze

  PROTECTION_TRANSITIONS = {
    "not_eligible" => %w[eligible],
    "eligible" => %w[active void],
    "active" => %w[completed void],
    "completed" => [],
    "void" => []
  }.freeze

  before_validation :assign_order_id

  validates :order_id, :buyer_user_id, :payment_id, :currency, presence: true
  validates :order_id, uniqueness: true
  validates :status, inclusion: { in: %w[pending_payment paid processing fulfilled cancelled refunded partially_refunded] }
  validates :fulfillment_status, inclusion: { in: %w[not_required unfulfilled partially_fulfilled fulfilled failed] }
  validates :source, inclusion: { in: SOURCES }
  validates :protection_status, inclusion: { in: PROTECTION_STATUSES }
  validates :fulfillment_type, inclusion: { in: FULFILLMENT_TYPES }
  validates :terms_version, numericality: { only_integer: true, greater_than: 0 }

  before_update :validate_status_transition
  before_update :validate_protection_status_transition

  VALID_TRANSITIONS = {
    'pending_payment' => %w[paid cancelled],
    'paid' => %w[processing fulfilled cancelled refunded partially_refunded],
    'processing' => %w[fulfilled partially_fulfilled cancelled refunded partially_refunded],
    'fulfilled' => %w[refunded partially_refunded],
    'partially_fulfilled' => %w[fulfilled refunded partially_refunded],
    'cancelled' => [],
    'refunded' => [],
    'partially_refunded' => []
  }.freeze

  def validate_status_transition
    return unless status_changed?
    return unless status_was.present?

    allowed = VALID_TRANSITIONS[status_was]
    return if allowed&.include?(status)

    errors.add(:status, "cannot transition from #{status_was} to #{status}")
    throw :abort
  end

  def shipping_address
    {
      line1: shipping_address_line1,
      line2: shipping_address_line2,
      city: shipping_city,
      state: shipping_state,
      postal_code: shipping_postal_code,
      country: shipping_country,
      phone: shipping_phone
    }.compact
  end

  def protected?
    protection_status.in?(%w[active completed])
  end

  def is_service_order?
    source == "service_booking" || fulfillment_type == "service"
  end

  private
    def assign_order_id
      return if order_id.present?

      self.class.uncached do
        10.times do
          candidate = "ord_#{SecureRandom.alphanumeric(12).downcase}"
          unless self.class.exists?(order_id: candidate)
            self.order_id = candidate
            return
          end
        end
      end

      raise "Failed to generate unique order_id after 10 attempts"
    end

    def validate_protection_status_transition
      return unless protection_status_changed?
      return unless protection_status_was.present?
      return if PROTECTION_TRANSITIONS.fetch(protection_status_was, []).include?(protection_status)

      errors.add(
        :protection_status,
        "cannot transition from #{protection_status_was} to #{protection_status}"
      )
      throw :abort
    end
end
