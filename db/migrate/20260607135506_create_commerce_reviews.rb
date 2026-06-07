class CreateCommerceReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :commerce_reviews do |t|
      t.string :review_id, null: false
      t.references :commerce_product, foreign_key: true
      t.references :commerce_merchant, null: false, foreign_key: true
      t.string :buyer_user_id, null: false
      t.references :commerce_order, foreign_key: true
      t.integer :rating, null: false
      t.string :title
      t.text :body
      t.integer :helpful_count, default: 0
      t.string :status, default: "pending", null: false

      t.timestamps
    end

    add_index :commerce_reviews, :review_id, unique: true
    add_index :commerce_reviews, [:commerce_product_id, :status]
    add_index :commerce_reviews, [:commerce_merchant_id, :status]
    add_index :commerce_reviews, [:buyer_user_id, :commerce_product_id], unique: true, where: "commerce_product_id IS NOT NULL"
  end
end
