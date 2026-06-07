class ExpandCommerceProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :commerce_products, :category_id, :bigint
    add_column :commerce_products, :subcategory_id, :bigint
    add_column :commerce_products, :tags, :string, array: true, default: []
    add_column :commerce_products, :weight_grams, :integer
    add_column :commerce_products, :dimensions, :jsonb, default: {}
    add_column :commerce_products, :condition, :string, default: "new"
    add_column :commerce_products, :featured, :boolean, default: false
    add_column :commerce_products, :view_count, :integer, default: 0
    add_column :commerce_products, :sales_count, :integer, default: 0
    add_column :commerce_products, :rating_average, :decimal, precision: 3, scale: 2
    add_column :commerce_products, :rating_count, :integer, default: 0
    add_column :commerce_products, :seo_title, :string
    add_column :commerce_products, :seo_description, :text

    add_index :commerce_products, :category_id
    add_index :commerce_products, :featured
    add_index :commerce_products, :tags, using: :gin
  end
end
