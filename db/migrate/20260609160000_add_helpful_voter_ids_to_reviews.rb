class AddHelpfulVoterIdsToReviews < ActiveRecord::Migration[8.0]
  def change
    add_column :commerce_reviews, :helpful_voter_ids, :text, array: true, default: []
    add_index :commerce_reviews, :helpful_voter_ids, using: :gin
  end
end
