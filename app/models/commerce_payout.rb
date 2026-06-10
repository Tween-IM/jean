# frozen_string_literal: true
class CommercePayout < ApplicationRecord
  belongs_to :commerce_merchant

  before_validation :assign_payout_id, on: :create
  before_validation :assign_reference_id, on: :create

  validates :payout_id, :amount_cents, :currency, :status, presence: true
  validates :payout_id, uniqueness: true
  validates :reference_id, uniqueness: true, allow_nil: true
  validates :amount_cents, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: %w[pending processing completed failed cancelled] }

  scope :pending, -> { where(status: %w[pending processing]) }
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def pending?
    status.in?(%w[pending processing])
  end

  private

  def assign_payout_id
    return if payout_id.present?

    self.class.uncached do
      10.times do
        candidate = "pyo_#{SecureRandom.alphanumeric(12).downcase}"
        unless self.class.exists?(payout_id: candidate)
          self.payout_id = candidate
          return
        end
      end
    end

    raise "Failed to generate unique payout_id after 10 attempts"
  end

  def assign_reference_id
    return if reference_id.present?

    self.reference_id = "PO#{Time.current.strftime('%Y%m%d%H%M%S')}#{SecureRandom.hex(4).upcase}"
  end
end
