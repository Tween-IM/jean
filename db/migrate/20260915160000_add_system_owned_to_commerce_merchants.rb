# frozen_string_literal: true

# Catalogs mirrored from Jumia, Konga and friends belong to the platform, not
# to a human merchant account. This marks the merchant that holds them so the
# import API can accept writes to it and the admin can tell it apart.
class AddSystemOwnedToCommerceMerchants < ActiveRecord::Migration[8.1]
  def change
    add_column :commerce_merchants, :system_owned, :boolean, default: false, null: false
    add_index :commerce_merchants, :system_owned, where: "system_owned",
      name: "index_commerce_merchants_on_system_owned"
  end
end
