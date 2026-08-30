# frozen_string_literal: true

class AddOrderIdToCommercePayouts < ActiveRecord::Migration[8.0]
  def change
    add_column :commerce_payouts, :order_id, :string
    add_index  :commerce_payouts, :order_id
  end
end
