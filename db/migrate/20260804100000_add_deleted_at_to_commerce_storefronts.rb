# frozen_string_literal: true

class AddDeletedAtToCommerceStorefronts < ActiveRecord::Migration[8.1]
  def change
    add_column :commerce_storefronts, :deleted_at, :datetime
    add_index :commerce_storefronts, :deleted_at
  end
end
