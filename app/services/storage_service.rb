class StorageService
  # TMCP Protocol Section 10.3: Mini-App Storage System

  # Storage limits per PROTO specification
  MAX_KEYS_PER_USER_APP = 1000
  MAX_KEY_SIZE = 1.megabyte # 1MB per key
  MAX_VALUE_SIZE = 10.megabytes # 10MB per user/app total

  class << self
    def get(user_id, miniapp_id, key)
      validate_access(user_id, miniapp_id, key)

      entry = StorageEntry.find_entry(user_id, miniapp_id, key)

      return nil unless entry
      return nil if entry.expired?

      entry.value
    end

    def set(user_id, miniapp_id, key, value, options = {})
      validate_access(user_id, miniapp_id, key)
      validate_value_size(value)

      existing_entry = StorageEntry.find_entry(user_id, miniapp_id, key)

      validate_total_size(user_id, miniapp_id, key, value)

      expires_at = options[:ttl] ? Time.current + options[:ttl].seconds : nil

      user = User.find_by!(matrix_user_id: user_id)

      if existing_entry
        existing_entry.update!(value: value, expires_at: expires_at)
      else
        StorageEntry.create!(user: user, miniapp_id: miniapp_id, key: key, value: value, expires_at: expires_at)
      end

      true
    end

    def delete(user_id, miniapp_id, key)
      validate_access(user_id, miniapp_id, key)

      entry = StorageEntry.find_entry(user_id, miniapp_id, key)

      entry&.destroy

      true
    end

    def list(user_id, miniapp_id, prefix: nil, limit: 100, offset: 0)
      validate_access_list(user_id, miniapp_id)

      entries = StorageEntry.user_miniapp_entries(user_id, miniapp_id)

      entries = entries.where("key LIKE ?", "#{prefix}%") if prefix.present?

      total = entries.count
      paginated_entries = entries.offset(offset).limit(limit)

      {
        keys: paginated_entries.map(&:key),
        total: total,
        has_more: (offset + limit) < total
      }
    end

    def batch_get(user_id, miniapp_id, keys)
      validate_access_batch(user_id, miniapp_id, keys)

      results = {}

      keys.each do |key|
        entry = StorageEntry.find_entry(user_id, miniapp_id, key)
        results[key] = entry.value if entry && !entry.expired?
      end

      results
    end

    def batch_set(user_id, miniapp_id, key_value_pairs)
      validate_access_batch(user_id, miniapp_id, key_value_pairs.keys)

      user = User.find_by!(matrix_user_id: user_id)

      # Validate total size for all pairs
      total_size = key_value_pairs.sum do |key, value|
        validate_value_size(value)
        value.to_json.bytesize
      end

      current_size = get_total_size(user, miniapp_id)
      if current_size + total_size > MAX_VALUE_SIZE
        raise StorageError.new("Total storage limit exceeded")
      end

      results = {}
      key_value_pairs.each do |key, value|
        begin
          set(user_id, miniapp_id, key, value)
          results[key] = true
        rescue => e
          results[key] = false
        end
      end

      results
    end

    def get_storage_info(user_id, miniapp_id)
      validate_access_list(user_id, miniapp_id)

      entries = StorageEntry.user_miniapp_entries(user_id, miniapp_id)

      total_size = entries.sum { |e| e.value.to_json.bytesize }
      key_count = entries.count

      {
        total_size: total_size,
        total_size_limit: MAX_VALUE_SIZE,
        key_count: key_count,
        key_count_limit: MAX_KEYS_PER_USER_APP,
        usage_percentage: ((total_size.to_f / MAX_VALUE_SIZE) * 100).round(2)
      }
    end

    private

    def validate_access(user_id, miniapp_id, key)
      user = User.find_by(matrix_user_id: user_id)
      raise StorageError.new("User not found") unless user

      raise StorageError.new("Invalid key format") if key.blank? || key.length > 255 || key.include?("..")
    end

    def validate_access_list(user_id, miniapp_id)
      user = User.find_by(matrix_user_id: user_id)
      raise StorageError.new("User not found") unless user
    end

    def validate_access_batch(user_id, miniapp_id, keys)
      validate_access_list(user_id, miniapp_id)
      keys.each { |key| validate_access(user_id, miniapp_id, key) }
    end

    def validate_value_size(value)
      size = value.to_json.bytesize
      raise StorageError.new("Value size exceeds limit") if size > MAX_KEY_SIZE
    end

    def validate_total_size(user_id, miniapp_id, new_key, new_value)
      current_size = get_total_size(user_id, miniapp_id)
      new_size = new_value.to_json.bytesize

      existing_entry = StorageEntry.find_entry(user_id, miniapp_id, new_key)
      if existing_entry
        current_size -= existing_entry.value.to_json.bytesize
      end

      if current_size + new_size > MAX_VALUE_SIZE
        raise StorageError.new("Total storage limit exceeded")
      end
    end

    def get_total_size(user_id, miniapp_id)
      user = User.find_by!(matrix_user_id: user_id)
      entries = StorageEntry.user_miniapp_entries(user, miniapp_id)
      entries.sum { |e| e.value.to_json.bytesize }
    end
  end

  class StorageError < StandardError; end
end
