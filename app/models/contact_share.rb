# frozen_string_literal: true

class ContactShare < ApplicationRecord
  validates :from_user_id, :to_user_id, presence: true
  validates :from_user_id, uniqueness: { scope: :to_user_id }
end
