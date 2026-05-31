# frozen_string_literal: true
class MiniappInstallation < ApplicationRecord
  belongs_to :user
  belongs_to :mini_app
end
