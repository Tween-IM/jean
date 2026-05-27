class Api::V1::Social::CreatorsController < Api::V1::Social::BaseController
  def show
    require_scope("social:read")

    render json: { creator: creator_json(find_creator_profile) }
  end
end
