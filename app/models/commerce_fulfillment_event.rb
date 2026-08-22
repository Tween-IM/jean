# frozen_string_literal: true

class CommerceFulfillmentEvent < ApplicationRecord
  belongs_to :commerce_fulfillment

  before_validation :assign_event_id, on: :create
  before_validation :assign_occurred_at, on: :create
  before_update :prevent_mutation
  before_destroy :prevent_mutation

  validates :event_id, :event_type, :occurred_at, presence: true
  validates :event_id, uniqueness: true

  private

  def assign_event_id
    self.event_id ||= "fev_#{SecureRandom.alphanumeric(12).downcase}"
  end

  def assign_occurred_at
    self.occurred_at ||= Time.current
  end

  def prevent_mutation
    errors.add(:base, "fulfillment events are immutable")
    throw :abort
  end
end
