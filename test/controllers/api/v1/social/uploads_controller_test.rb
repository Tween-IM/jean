require "test_helper"

class Api::V1::Social::UploadsControllerTest < ActionDispatch::IntegrationTest
  test "should get create" do
    get api_v1_social_uploads_create_url
    assert_response :success
  end
end
