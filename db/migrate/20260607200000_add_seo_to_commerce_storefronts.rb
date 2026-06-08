# frozen_string_literal: true

class AddSeoToCommerceStorefronts < ActiveRecord::Migration[8.1]
  def change
    add_column :commerce_storefronts, :seo_title, :string
    add_column :commerce_storefronts, :seo_description, :text
  end
end
