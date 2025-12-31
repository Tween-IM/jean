class StorageEntry < ApplicationRecord
  # TMCP Protocol Section 10.3: Mini-App Storage

  belongs_to :user

  # Validations
  validates :user, presence: true
  validates :miniapp_id, presence: true
  validates :key, presence: true, length: { maximum: 255 }
  validates :value, length: { maximum: 1.megabyte } # 1MB per key limit

  # Scopes
  scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :expired, -> { where("expires_at <= ?", Time.current) }
  scope :by_miniapp, ->(miniapp_id) { where(miniapp_id: miniapp_id) }

  # Class methods for TMCP storage operations
  def self.find_entry(matrix_user_id, miniapp_id, key)
    user = User.find_by(matrix_user_id: matrix_user_id)
    return nil unless user
    active.where(user_id: user.id, miniapp_id: miniapp_id, key: key).first
  end

  def self.user_miniapp_entries(matrix_user_id, miniapp_id)
    user = User.find_by(matrix_user_id: matrix_user_id)
    return none unless user
    active.where(user_id: user.id, miniapp_id: miniapp_id)
  end

  # Instance methods
  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def set_ttl(seconds)
    self.expires_at = Time.current + seconds
  end
end
