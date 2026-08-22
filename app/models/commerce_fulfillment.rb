# frozen_string_literal: true

class CommerceFulfillment < ApplicationRecord
  KINDS = %w[shipment local_delivery pickup service].freeze

  STATUSES = {
    "shipment" => %w[unfulfilled preparing shipped delivered accepted failed],
    "local_delivery" => %w[unfulfilled preparing shipped delivered accepted failed],
    "pickup" => %w[scheduled ready handover_pending handed_over accepted failed],
    "service" => %w[scheduled in_progress submitted inspection revision_requested accepted disputed failed]
  }.freeze

  TRANSITIONS = {
    "unfulfilled" => %w[preparing failed],
    "preparing" => %w[shipped failed],
    "shipped" => %w[delivered failed],
    "delivered" => %w[accepted failed],
    "scheduled" => %w[ready in_progress failed],
    "ready" => %w[handover_pending handed_over failed],
    "handover_pending" => %w[handed_over failed],
    "handed_over" => %w[accepted],
    "in_progress" => %w[submitted failed],
    "submitted" => %w[inspection revision_requested accepted disputed],
    "inspection" => %w[revision_requested accepted disputed],
    "revision_requested" => %w[in_progress submitted disputed],
    "disputed" => %w[accepted failed],
    "accepted" => [],
    "failed" => []
  }.freeze

  belongs_to :commerce_order
  has_many :events,
    class_name: "CommerceFulfillmentEvent",
    dependent: :restrict_with_error
  has_many :commerce_pickup_codes, dependent: :restrict_with_error

  before_validation :assign_fulfillment_id, on: :create
  before_update :validate_status_transition

  scope :latest_first, -> { order(created_at: :desc) }
  scope :not_terminal, -> { where.not(status: %w[accepted failed]) }

  def self.active_or_latest
    not_terminal.latest_first.first || latest_first.first
  end

  validates :fulfillment_id, presence: true, uniqueness: true
  validates :kind, inclusion: { in: KINDS }
  validate :status_matches_kind

  private

  def assign_fulfillment_id
    self.fulfillment_id ||= "ful_#{SecureRandom.alphanumeric(12).downcase}"
  end

  def status_matches_kind
    return if STATUSES.fetch(kind, []).include?(status)

    errors.add(:status, "is not valid for #{kind || 'this fulfillment type'}")
  end

  def validate_status_transition
    return unless status_changed?
    return if TRANSITIONS.fetch(status_was, []).include?(status)

    errors.add(:status, "cannot transition from #{status_was} to #{status}")
    throw :abort
  end
end
