# frozen_string_literal: true

class Api::V1::Social::ContactsController < Api::V1::Social::BaseController
  def sync
    require_scope("social:engage")

    hashes = params[:hashes]
    return render json: { error: "missing_hashes" }, status: :bad_request unless hashes.is_a?(Array)

    my_id = @current_user.matrix_user_id
    count = 0

    PhoneContactHash.transaction do
      PhoneContactHash.where(user_id: my_id).delete_all
      hashes.each do |hash|
        PhoneContactHash.create!(user_id: my_id, phone_hash: hash.to_s)
        count += 1
      end
    end

    # Count mutual contacts (both users have each other's phone)
    matched = PhoneContactHash.where(phone_hash: hashes)
                               .where.not(user_id: my_id)
                               .distinct
                               .pluck(:user_id)

    render json: { synced: count, matched_count: matched.length, matched: matched }
  end
end
