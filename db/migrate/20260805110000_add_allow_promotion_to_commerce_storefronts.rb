class AddAllowPromotionToCommerceStorefronts < ActiveRecord::Migration[7.2]
  def change
    add_column :commerce_storefronts, :allow_promotion, :boolean, default: true, null: false
  end
end
