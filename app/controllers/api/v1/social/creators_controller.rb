# frozen_string_literal: true

class Api::V1::Social::CreatorsController < Api::V1::Social::BaseController
  def show
    require_scope("social:read")

    render json: { creator: creator_json(find_creator_profile) }
  end

  def update
    require_scope("social:write")

    creator = find_creator_profile
    unless creator.user_id == @current_user.matrix_user_id
      return render json: { error: "forbidden", message: "Only the creator can update this profile" }, status: :forbidden
    end

    if creator.update(creator_params)
      render json: { creator: creator_json(creator) }
    else
      render_errors(creator)
    end
  end

  private

  def creator_params
    params.require(:creator).permit(:handle, :display_name, :avatar_url, :bio, :commerce_storefront_id)
  end
end
