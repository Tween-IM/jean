class StorageService
  # TMCP Protocol Section 10.3: Mini-App Storage System

  # Storage limits per PROTO specification
  MAX_KEYS_PER_USER_APP = 1000
  MAX_KEY_SIZE = 1.megabyte # 1MB per key
  MAX_VALUE_SIZE = 10.megabytes # 10MB per user/app total

  class << self
    def get(user_id, miniapp_id, key)
      validate_access(user_id, miniapp_id, key)

      storage_key = build_storage_key(user_id, miniapp_id, key)
      data = Rails.cache.read(storage_key)

      return nil unless data

      # Validate data hasn't expired
      return nil if data["expires_at"] && Time.parse(data["expires_at"]) < Time.current

      data["value"]
    end

    def set(user_id, miniapp_id, key, value, options = {})
      validate_access(user_id, miniapp_id, key)
      validate_value_size(value)
      validate_total_size(user_id, miniapp_id, key, value)

      expires_at = options[:ttl] ? Time.current + options[:ttl].seconds : nil

      storage_key = build_storage_key(user_id, miniapp_id, key)
      data = {
        "value" => value,
        "created_at" => Time.current.iso8601,
        "expires_at" => expires_at&.iso8601,
        "size" => value.to_json.bytesize
      }

      Rails.cache.write(storage_key, data, expires_in: expires_at ? (expires_at - Time.current) : nil)

      true
    end

    def delete(user_id, miniapp_id, key)
      validate_access(user_id, miniapp_id, key)

      storage_key = build_storage_key(user_id, miniapp_id, key)
      Rails.cache.delete(storage_key)

      true
    end

    def list(user_id, miniapp_id, prefix: nil, limit: 100, offset: 0)
      validate_access_list(user_id, miniapp_id)

      # In production, this would use a proper key-value store with scanning
      # For demo, we'll simulate with cache keys
      pattern = build_storage_key(user_id, miniapp_id, prefix || "*")

      # Mock implementation - in reality would scan the key-value store
      keys = Rails.cache.instance_variable_get(:@data)&.keys&.select do |k|
        k.start_with?(build_storage_key(user_id, miniapp_id, ""))
      end || []

      filtered_keys = keys.select { |k| prefix.nil? || k.include?(prefix) }
      paginated_keys = filtered_keys[offset, limit] || []

      {
        keys: paginated_keys.map { |k| extract_key_name(k, user_id, miniapp_id) },
        total: filtered_keys.size,
        has_more: (offset + limit) < filtered_keys.size
      }
    end

    def batch_get(user_id, miniapp_id, keys)
      validate_access_batch(user_id, miniapp_id, keys)

      results = {}
      keys.each do |key|
        value = get(user_id, miniapp_id, key)
        results[key] = value if value
      end

      results
    end

    def batch_set(user_id, miniapp_id, key_value_pairs)
      validate_access_batch(user_id, miniapp_id, key_value_pairs.keys)

      # Validate total size for all pairs
      total_size = key_value_pairs.sum do |key, value|
        validate_value_size(value)
        value.to_json.bytesize
      end

      current_size = get_total_size(user_id, miniapp_id)
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

      total_size = get_total_size(user_id, miniapp_id)
      key_count = get_key_count(user_id, miniapp_id)

      {
        total_size: total_size,
        total_size_limit: MAX_VALUE_SIZE,
        key_count: key_count,
        key_count_limit: MAX_KEYS_PER_USER_APP,
        usage_percentage: ((total_size.to_f / MAX_VALUE_SIZE) * 100).round(2)
      }
    end

    private

    def build_storage_key(user_id, miniapp_id, key)
      "storage:#{user_id}:#{miniapp_id}:#{key}"
    end

    def extract_key_name(full_key, user_id, miniapp_id)
      prefix = "storage:#{user_id}:#{miniapp_id}:"
      full_key.sub(prefix, "")
    end

    def validate_access(user_id, miniapp_id, key)
      # Validate user exists
      user = User.find_by(matrix_user_id: user_id)
      raise StorageError.new("User not found") unless user

      # Note: Mini-app validation is handled by controller before_action
      # This service assumes mini-app access has already been validated

      # Validate key format (no path traversal, reasonable length)
      raise StorageError.new("Invalid key format") if key.blank? || key.length > 255 || key.include?("..")
    end

    def validate_access_list(user_id, miniapp_id)
      user = User.find_by(matrix_user_id: user_id)
      raise StorageError.new("User not found") unless user

      # Note: Mini-app validation is handled by controller before_action
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

      # If key exists, subtract its current size
      existing_value = get(user_id, miniapp_id, new_key)
      if existing_value
        existing_size = existing_value.to_json.bytesize
        current_size -= existing_size
      end

      if current_size + new_size > MAX_VALUE_SIZE
        raise StorageError.new("Total storage limit exceeded")
      end
    end

    def get_total_size(user_id, miniapp_id)
      # Mock implementation - in production would sum all key sizes
      1024 * 1024 # 1MB for demo
    end

    def get_key_count(user_id, miniapp_id)
      # Mock implementation - in production would count keys
      50
    end
  end

  class StorageError < StandardError; end
end
