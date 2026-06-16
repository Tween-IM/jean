# frozen_string_literal: true

class Api::V1::Social::FollowsController < Api::V1::Social::BaseController
  def create
    require_scope("social:engage")

    creator = find_creator_profile
    follow = ::SocialFollow.find_or_create_by!(
      follower_user_id: @current_user.matrix_user_id,
      creator_user_id: creator.user_id
    )

    emit_follow_created(follow, creator) if follow.previously_new_record?
    render json: { follow_id: follow.id, creator: creator_json(creator.reload) }, status: :created
  end

  def following
    require_scope("social:read")

    following_relations = ::SocialFollow.where(follower_user_id: @current_user.matrix_user_id, status: :active)
    creator_user_ids = following_relations.pluck(:creator_user_id)
    creators = SocialCreatorProfile.where(user_id: creator_user_ids)
    # Wrapped response — the Flutter app reads `data['creators']` to
    # populate the following list. Returning a top-level array was
    # breaking the client silently.
    render json: { creators: creators.map { |c| creator_json(c) } }
  end

  def destroy
    require_scope("social:engage")

    creator = find_creator_profile
    follow = ::SocialFollow.find_by(follower_user_id: @current_user.matrix_user_id, creator_user_id: creator.user_id)
    follow&.destroy!

    head :no_content
  end

  private

  def emit_follow_created(follow, creator)
    MatrixEventService.publish_follow_created(
      follower_id: follow.follower_user_id,
      creator_id: creator.user_id
    )

    NotificationService.create_follow_notification(
      creator: creator,
      follower_user_id: @current_user.matrix_user_id,
      follower_display_name: current_creator_profile.display_name
    )
  end
end
