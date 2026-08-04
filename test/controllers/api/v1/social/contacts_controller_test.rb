require "test_helper"

class Api::V1::Social::ContactsControllerTest < ActionDispatch::IntegrationTest
  test "returns mutual phone-contact matches" do
    alice = create_user("alice-contacts")
    bob = create_user("bob-contacts")
    bob_profile = SocialCreatorProfile.create!(user_id: bob.matrix_user_id, handle: "bob_contacts")

    # Alice's address book contains Bob's number; Bob's contains Alice's.
    alice_numbers = [ "+2348012345678" ]
    bob_numbers = [ "+2348098765432" ]

    post api_v1_social_contacts_sync_url,
      params: { numbers: alice_numbers },
      headers: tep_headers(alice, "social:engage"),
      as: :json
    assert_response :success
    # No match yet: Bob hasn't synced Alice's number.
    body = response.parsed_body
    assert_equal 1, body["synced"]
    assert_equal 0, body["matched_count"]

    post api_v1_social_contacts_sync_url,
      params: { numbers: bob_numbers },
      headers: tep_headers(bob, "social:engage"),
      as: :json
    assert_response :success

    # Now Alice syncs again — Bob has her number, so he matches.
    post api_v1_social_contacts_sync_url,
      params: { numbers: alice_numbers },
      headers: tep_headers(alice, "social:engage"),
      as: :json
    assert_response :success

    body = response.parsed_body
    assert_equal 1, body["matched_count"]
    assert_equal bob.matrix_user_id, body.dig("matched", 0, "user_id")
    assert_equal "bob_contacts", body.dig("matched", 0, "handle")
  end

  test "requires social:engage scope" do
    alice = create_user("alice-no-scope")

    post api_v1_social_contacts_sync_url,
      params: { numbers: [ "+2348012345678" ] },
      headers: tep_headers(alice, "user:read"),
      as: :json

    assert_response :forbidden
  end

  test "rejects non-array payload" do
    alice = create_user("alice-bad-payload")

    post api_v1_social_contacts_sync_url,
      params: { numbers: "not-an-array" },
      headers: tep_headers(alice, "social:engage"),
      as: :json

    assert_response :bad_request
  end

  test "rejects too many numbers" do
    alice = create_user("alice-too-many")
    numbers = Array.new(Api::V1::Social::ContactsController::MAX_NUMBERS + 1) { |i| "+234801000#{i.to_s.rjust(6, "0")}" }

    post api_v1_social_contacts_sync_url,
      params: { numbers: numbers },
      headers: tep_headers(alice, "social:engage"),
      as: :json

    assert_response :unprocessable_entity
    assert_equal "too_many_hashes", response.parsed_body["error"]
  end

  test "drops malformed numbers and clears previous sync when none valid" do
    alice = create_user("alice-malformed")
    bob = create_user("bob-malformed")

    # First sync a valid number so there is a stale row.
    post api_v1_social_contacts_sync_url,
      params: { numbers: [ "+2348012345678" ] },
      headers: tep_headers(alice, "social:engage"),
      as: :json
    assert_equal 1, response.parsed_body["synced"]

    # Second sync: only malformed numbers -> previous sync cleared, synced=0.
    post api_v1_social_contacts_sync_url,
      params: { numbers: [ "not-a-number", "08012345678", "" ] },
      headers: tep_headers(alice, "social:engage"),
      as: :json
    assert_response :success
    assert_equal 0, response.parsed_body["synced"]
    assert_equal 0, PhoneContactHash.where(user_id: alice.matrix_user_id).count
  end

  test "does not match self" do
    alice = create_user("alice-self")

    # Alice's own number is in her own book.
    post api_v1_social_contacts_sync_url,
      params: { numbers: [ "+2348012345678" ] },
      headers: tep_headers(alice, "social:engage"),
      as: :json

    assert_response :success
    assert_equal 0, response.parsed_body["matched_count"]
  end

  private

  def create_user(username)
    User.create!(
      matrix_user_id: "@#{username}:example.com",
      matrix_username: "#{username}:example.com",
      matrix_homeserver: "example.com"
    )
  end

  def tep_headers(user, scopes)
    token = TepTokenService.encode(
      { user_id: user.matrix_user_id, miniapp_id: "miniapp.social.test" },
      scopes: scopes.split
    )
    { "Authorization" => "Bearer #{token}" }
  end
end
