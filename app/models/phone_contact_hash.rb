# frozen_string_literal: true

class PhoneContactHash < ApplicationRecord
  validates :user_id, :phone_hash, presence: true
end
