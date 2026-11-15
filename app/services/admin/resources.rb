module Admin
  module Resources
    # Reviewed, explicit presentation metadata. Keys are never supplied as model names by a request.
    CATALOG = YAML.safe_load_file(Rails.root.join("config/admin_resources.yml")).transform_values do |entry|
      entry = entry.symbolize_keys
      entry[:permission] = entry[:permission].to_sym
      entry[:service] = entry[:service].to_sym
      entry[:columns] = entry[:columns].map(&:symbolize_keys)
      entry[:fields] ||= entry[:columns].map { |column| column[:key] }
      entry
    end.freeze
  end
end
