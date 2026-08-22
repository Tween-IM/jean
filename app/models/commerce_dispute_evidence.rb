# frozen_string_literal: true

class CommerceDisputeEvidence < ApplicationRecord
  belongs_to :commerce_dispute

  before_validation :assign_evidence_id
  before_validation :assign_uploaded_at

  validates :evidence_id, :media_type, :url, presence: true
  validates :evidence_id, uniqueness: true
  validates :media_type, inclusion: { in: %w[image video audio document other] }

  private

  def assign_evidence_id
    return if evidence_id.present?

    self.evidence_id = "evi_#{SecureRandom.alphanumeric(12).downcase}"
  end

  def assign_uploaded_at
    self.uploaded_at ||= Time.current
  end
end
