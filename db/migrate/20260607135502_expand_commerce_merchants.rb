class ExpandCommerceMerchants < ActiveRecord::Migration[8.1]
  def change
    add_column :commerce_merchants, :logo_url, :string
    add_column :commerce_merchants, :banner_url, :string
    add_column :commerce_merchants, :business_type, :string, default: "individual"
    add_column :commerce_merchants, :registration_number, :string
    add_column :commerce_merchants, :phone, :string
    add_column :commerce_merchants, :email, :string
    add_column :commerce_merchants, :website, :string
    add_column :commerce_merchants, :address_line1, :string
    add_column :commerce_merchants, :address_line2, :string
    add_column :commerce_merchants, :city, :string
    add_column :commerce_merchants, :state, :string
    add_column :commerce_merchants, :country, :string, default: "NG"
    add_column :commerce_merchants, :about, :text
    add_column :commerce_merchants, :policies, :jsonb, default: {}
    add_column :commerce_merchants, :social_links, :jsonb, default: {}
    add_column :commerce_merchants, :verified_at, :datetime
    add_column :commerce_merchants, :payout_settings, :jsonb, default: {}
    add_column :commerce_merchants, :commission_rate, :integer, default: 500

    add_index :commerce_merchants, :business_type
    add_index :commerce_merchants, :verified_at
  end
end
