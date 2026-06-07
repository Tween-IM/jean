# frozen_string_literal: true
class CommerceProductShipping < ApplicationRecord
  belongs_to :commerce_product
  belongs_to :commerce_shipping_profile
end
