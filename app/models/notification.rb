# frozen_string_literal: true

class Notification < ApplicationRecord
  # ---------------------------------------------------------------------------
  # Enums
  # ---------------------------------------------------------------------------

  enum :notification_type, {
    like: "like",
    comment: "comment",
    follow: "follow",
    mention: "mention",
    payment: "payment",
    system: "system"
  }, prefix: true

  enum :source, {
    social: "social",
    matrix: "matrix",
    tweenpay: "tweenpay",
    system: "system"
  }, prefix: true

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------

  belongs_to :actor_profile,
             class_name: "SocialCreatorProfile",
             foreign_key: :actor_id,
             primary_key: :user_id,
             optional: true

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------

  scope :recent, -> { order(created_at: :desc) }
  scope :unread, -> { where(read_at: nil) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }
  scope :by_source, ->(source) { where(source: source) }

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------

  validates :user_id, presence: true
  validates :notification_type, presence: true
  validates :source, presence: true

  # ---------------------------------------------------------------------------
  # Instance methods
  # ---------------------------------------------------------------------------

  def read?
    read_at.present?
  end

  def mark_as_read!
    update!(read_at: Time.current) unless read?
  end

  def mark_as_unread!
    update!(read_at: nil)
  end

  # ---------------------------------------------------------------------------
  # JSON serialization helpers (used by controller inline JSON)
  # ---------------------------------------------------------------------------

  def as_json(opts = {})
    base = {
      id: id,
      notification_type: notification_type,
      source: source,
      target_type: target_type,
      target_id: target_id,
      title: title,
      body: body,
      read: read?,
      created_at: created_at.iso8601,
      metadata: metadata
    }

    if actor_profile
      base[:actor] = {
        user_id: actor_profile.user_id,
        display_name: actor_profile.display_name,
        handle: actor_profile.handle,
        avatar_url: actor_profile.avatar_url
      }
    elsif actor_id.present?
      base[:actor] = { user_id: actor_id }
    end

    base
  end
end
