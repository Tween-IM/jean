# frozen_string_literal: true

class AdminOauthGrant < ApplicationRecord
  belongs_to :user
  self.filter_attributes += [ :encrypted_credentials ]

  class ConnectionRequired < Admin::RemoteClient::Forbidden; end
  SYNAPSE_SCOPE = "urn:synapse:admin:*"
  MAS_SCOPE = "urn:mas:admin"
  REQUIRED_SCOPES = [ "openid", "urn:matrix:client:api:*", SYNAPSE_SCOPE, MAS_SCOPE ].freeze
  MESSAGE = "Authorize administration with your own Tween ID to continue."

  def self.digest(key)
    Digest::SHA256.hexdigest(key.to_s)
  end

  def self.for_session(user, key)
    raise ConnectionRequired, MESSAGE if key.blank? || !user&.active? || !user.platform_admin?
    grant = find_by(user_id: user.id, session_digest: digest(key))
    unless grant && grant.session_expires_at.future? && grant.issuer == Admin::MasOidc.issuer &&
        grant.client_id == Admin::MasOidc.client_id && user.mas_user_id == grant.subject
      disconnect(key) if grant
      raise ConnectionRequired, MESSAGE
    end
    grant
  end

  def self.install!(user:, key:, subject:, tokens:)
    raise ConnectionRequired, "Use the Tween ID linked to your staff account." unless user.mas_user_id.present? && user.mas_user_id == subject
    grant = find_or_initialize_by(session_digest: digest(key))
    grant.assign_attributes(user: user, subject: subject, issuer: Admin::MasOidc.issuer,
      client_id: Admin::MasOidc.client_id, session_expires_at: 12.hours.from_now)
    grant.accept_tokens!(tokens)
    grant.save!
    grant
  end

  def self.disconnect(key)
    return if key.blank?
    grant = find_by(session_digest: digest(key))
    return unless grant
    tokens = grant.credentials
    grant.destroy!
    if grant.issuer == Admin::MasOidc.issuer && grant.client_id == Admin::MasOidc.client_id
      Admin::MasOidc.revoke(tokens["refresh_token"].presence || tokens["access_token"])
    end
  rescue Admin::MasOidc::Error, ActiveSupport::MessageEncryptor::InvalidMessage
    # Local removal is authoritative; never keep usable local credentials because
    # an unavailable identity provider could not acknowledge revocation.
    grant&.destroy! if grant&.persisted?
  end

  def credentials
    self.class.encryptor.decrypt_and_verify(encrypted_credentials)
  end

  def access_token_for(required_scope)
    permission = required_scope == SYNAPSE_SCOPE ? :view_messaging : :view_identity
    unless user.reload.active? && user.platform_admin? && user.has_admin_permission?(permission)
      destroy!
      raise ConnectionRequired, MESSAGE
    end
    failure = nil
    token = nil
    with_lock do
      if session_expires_at.past? || issuer != Admin::MasOidc.issuer || client_id != Admin::MasOidc.client_id || user.mas_user_id != subject
        destroy!
        failure = ConnectionRequired.new(MESSAGE)
      else
        begin
          data = credentials
          if expires_at <= 30.seconds.from_now
            raise ConnectionRequired, MESSAGE if data["refresh_token"].blank?
            refreshed = Admin::MasOidc.refresh(data["refresh_token"])
            refreshed["refresh_token"] ||= data["refresh_token"]
            refreshed["scope"] ||= scope
            accept_tokens!(refreshed)
            save!
            data = credentials
          end
          raise ConnectionRequired, MESSAGE unless scope.split.include?(required_scope)
          token = data.fetch("access_token")
        rescue Admin::MasOidc::AuthorizationRejected, ConnectionRequired, ActiveSupport::MessageEncryptor::InvalidMessage, KeyError
          destroy!
          failure = ConnectionRequired.new(MESSAGE)
        rescue Admin::MasOidc::Error
          failure = Admin::RemoteClient::Unavailable.new("Tween ID is temporarily unavailable. Please try again.")
        end
      end
    end
    raise failure if failure
    token
  end

  def accept_tokens!(tokens)
    granted = tokens.fetch("scope", "").split
    expiry = Integer(tokens.fetch("expires_in", 0))
    unless tokens["access_token"].present? && tokens["token_type"].to_s.casecmp?("Bearer") &&
        expiry.positive? && (REQUIRED_SCOPES - granted).empty?
      raise ConnectionRequired, "Tween ID did not grant the required administration permissions."
    end
    self.scope = granted.join(" ")
    self.expires_at = expiry.seconds.from_now
    self.encrypted_credentials = self.class.encryptor.encrypt_and_sign(tokens.slice("access_token", "refresh_token"))
  rescue ArgumentError, TypeError
    raise ConnectionRequired, "Tween ID returned an invalid authorization."
  end

  def self.encryptor
    key = Rails.application.key_generator.generate_key("tween-admin-oauth-grants-v1", 32)
    ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm", serializer: JSON)
  end
end
