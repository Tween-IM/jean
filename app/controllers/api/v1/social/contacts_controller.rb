# frozen_string_literal: true

class Api::V1::Social::ContactsController < Api::V1::Social::BaseController
  MAX_NUMBERS = 2000
  SYNC_LIMIT = 10
  SYNC_WINDOW = 3600 # seconds

  rate_limit action: :sync, limit: SYNC_LIMIT, window: SYNC_WINDOW, key: "social:contacts:sync::user_id"

  def sync
    require_scope("social:engage")

    numbers = params[:numbers]
    unless numbers.is_a?(Array)
      return render json: { error: "missing_numbers" }, status: :bad_request
    end

    # Guard against enormous payloads / abuse.
    if numbers.length > MAX_NUMBERS
      return render json: { error: "too_many_hashes", message: "Cannot sync more than #{MAX_NUMBERS} numbers" }, status: :unprocessable_entity
    end

    # Only accept valid E.164 numbers; silently drop anything malformed.
    valid_numbers = numbers.filter_map { |n| n.to_s.strip if PhoneContactHashService.valid_number?(n.to_s.strip) }.uniq

    my_id = @current_user.matrix_user_id

    if valid_numbers.any?
      hashes = PhoneContactHashService.hash_all(valid_numbers)
      rows = hashes.map { |h| { user_id: my_id, phone_hash: h, created_at: Time.current, updated_at: Time.current } }

      PhoneContactHash.transaction do
        PhoneContactHash.where(user_id: my_id).delete_all
        PhoneContactHash.insert_all(rows) # unique index guarantees (user_id, phone_hash) uniqueness
      end
    else
      # Empty/no valid numbers: still clear the previous sync so stale
      # matches disappear.
      PhoneContactHash.where(user_id: my_id).delete_all
    end

    # Mutual contacts: users who have also synced one of the same hashes.
    store_hashed = valid_numbers.any? ? PhoneContactHashService.hash_all(valid_numbers) : []
    matched_user_ids = PhoneContactHash.where(phone_hash: store_hashed)
                                       .where.not(user_id: my_id)
                                       .distinct
                                       .pluck(:user_id)

    profiles = SocialCreatorProfile.where(user_id: matched_user_ids).index_by(&:user_id)

    matched = matched_user_ids.map do |uid|
      contact_json(uid, profiles[uid])
    end

    render json: {
      synced: store_hashed.length,
      matched_count: matched.length,
      matched: matched,
      pepper_fingerprint: PhoneContactHashService.pepper_fingerprint
    }
  end

  private

  # Unlike creator_json (which withholds user_id for non-self views), contact
  # matches are intentional mutual discoveries, so the requester is explicitly
  # told the matched user's matrix id (needed to start a DM).
  def contact_json(user_id, profile)
    if profile.nil?
      { user_id: user_id, handle: nil, display_name: nil, avatar_url: nil }
    else
      {
        user_id: user_id,
        handle: profile.handle,
        display_name: profile.display_name,
        avatar_url: profile.avatar_url
      }
    end
  end
end