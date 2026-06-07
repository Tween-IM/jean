class CreateCommerceCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :commerce_categories do |t|
      t.string :category_id, null: false
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :icon
      t.bigint :parent_id
      t.integer :sort_order, default: 0
      t.integer :product_count, default: 0
      t.string :status, default: "active", null: false

      t.timestamps
    end

    add_index :commerce_categories, :category_id, unique: true
    add_index :commerce_categories, :slug, unique: true
    add_index :commerce_categories, :parent_id
    add_index :commerce_categories, :status

    # Add foreign key for self-referential
    add_foreign_key :commerce_categories, :commerce_categories, column: :parent_id
  end
end
