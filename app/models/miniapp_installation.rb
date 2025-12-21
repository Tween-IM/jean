class MiniappInstallation < ApplicationRecord
  belongs_to :user
  belongs_to :miniapp
end
