# frozen_string_literal: true

require "test_helper"

class SocialCreatorProfileTest < ActiveSupport::TestCase
  def setup
    @profile_a = SocialCreatorProfile.find_or_create_by!(user_id: "@alice:tween.im") do |p|
      p.handle = "alice"
      p.display_name = "Alice"
    end
    @profile_b = SocialCreatorProfile.find_or_create_by!(user_id: "@bob:tween.im") do |p|
      p.handle = "bob"
      p.display_name = "Bob"
    end
    @profile_c = SocialCreatorProfile.find_or_create_by!(user_id: "@charlie:tween.im") do |p|
      p.handle = "charlie"
      p.display_name = "Charlie"
    end
  end

  def teardown
    ContactShare.delete_all
  end

  test "explicit_contact? returns false when no contact shares exist" do
    assert_not @profile_a.explicit_contact?("@bob:tween.im")
  end

  test "explicit_contact? returns true when from_user shares with to_user" do
    ContactShare.create!(from_user_id: "@alice:tween.im", to_user_id: "@bob:tween.im")
    assert @profile_a.explicit_contact?("@bob:tween.im")
  end

  test "explicit_contact? returns true when to_user shares with from_user (unilateral)" do
    ContactShare.create!(from_user_id: "@bob:tween.im", to_user_id: "@alice:tween.im")
    assert @profile_a.explicit_contact?("@bob:tween.im")
  end

  test "explicit_contact? returns true when both share" do
    ContactShare.create!(from_user_id: "@alice:tween.im", to_user_id: "@bob:tween.im")
    ContactShare.create!(from_user_id: "@bob:tween.im", to_user_id: "@alice:tween.im")
    assert @profile_a.explicit_contact?("@bob:tween.im")
  end

  test "explicit_contact? returns false for self-check" do
    ContactShare.create!(from_user_id: "@alice:tween.im", to_user_id: "@bob:tween.im")
    assert_not @profile_a.explicit_contact?("@alice:tween.im")
  end

  test "explicit_contact? returns false for nil/blank user_id" do
    assert_not @profile_a.explicit_contact?(nil)
    assert_not @profile_a.explicit_contact?("")
  end

  test "explicit_contact? returns false for unrelated users" do
    ContactShare.create!(from_user_id: "@alice:tween.im", to_user_id: "@bob:tween.im")
    assert_not @profile_a.explicit_contact?("@charlie:tween.im")
  end

  test "ContactShare enforces uniqueness of from_user_id + to_user_id" do
    ContactShare.create!(from_user_id: "@alice:tween.im", to_user_id: "@bob:tween.im")
    dup = ContactShare.new(from_user_id: "@alice:tween.im", to_user_id: "@bob:tween.im")
    assert_not dup.valid?
  end

  test "explicit_contact? returns true when both have phone contacts synced" do
    PhoneContactHash.create!(user_id: "@alice:tween.im", phone_hash: "hash_a")
    PhoneContactHash.create!(user_id: "@bob:tween.im", phone_hash: "hash_b")
    assert @profile_a.explicit_contact?("@bob:tween.im")
  end

  test "explicit_contact? returns false when only one has phone contacts synced" do
    PhoneContactHash.create!(user_id: "@alice:tween.im", phone_hash: "hash_a")
    assert_not @profile_a.explicit_contact?("@bob:tween.im")
  end

  test "explicit_contact? returns false when neither has phone contacts synced" do
    assert_not @profile_a.explicit_contact?("@bob:tween.im")
  end
end
