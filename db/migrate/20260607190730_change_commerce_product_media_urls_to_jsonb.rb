class ChangeCommerceProductMediaUrlsToJsonb < ActiveRecord::Migration[8.1]
  def up
    change_column :commerce_products, :media_urls, :jsonb, default: [], null: false, using: 'media_urls::jsonb'
  end

  def down
    change_column :commerce_products, :media_urls, :json, default: [], null: false, using: 'media_urls::json'
  end
end
