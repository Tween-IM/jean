class ExpandCommerceStorefronts < ActiveRecord::Migration[8.1]
  def change
    add_column :commerce_storefronts, :logo_url, :string
    add_column :commerce_storefronts, :banner_url, :string
    add_column :commerce_storefronts, :accent_color, :string, default: "#7C3AED"
    add_column :commerce_storefronts, :about, :text
    add_column :commerce_storefronts, :policies, :jsonb, default: {}
    add_column :commerce_storefronts, :is_default, :boolean, default: false
    add_column :commerce_storefronts, :featured, :boolean, default: false
    add_column :commerce_storefronts, :view_count, :integer, default: 0
    add_column :commerce_storefronts, :product_count, :integer, default: 0
    add_column :commerce_storefronts, :order_count, :integer, default: 0
    add_column :commerce_storefronts, :rating_average, :decimal, precision: 3, scale: 2
    add_column :commerce_storefronts, :rating_count, :integer, default: 0
    add_column :commerce_storefronts, :social_share_enabled, :boolean, default: true
    add_column :commerce_storefronts, :store_url_slug, :string

    add_index :commerce_storefronts, :store_url_slug, unique: true
    add_index :commerce_storefronts, :featured
    add_index :commerce_storefronts, :status
  end
end
