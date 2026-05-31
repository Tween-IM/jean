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
  end
end
