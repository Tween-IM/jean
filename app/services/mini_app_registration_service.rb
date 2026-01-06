class MiniAppRegistrationService
  CATEGORIES = %w[shopping finance social productivity entertainment utilities].freeze
  CLASSIFICATIONS = %w[community official partner].freeze

  def self.register(
    name:,
    short_name:,
    description:,
    category:,
    developer:,
    technical:,
    branding:,
    classification:,
    user_id:
  )
    raise ArgumentError, "name is required" if name.blank?
    raise ArgumentError, "short_name is required" if short_name.blank?
    raise ArgumentError, "category is required" if category.blank?
    raise ArgumentError, "user_id is required" if user_id.blank?

    validate_category(category)
    validate_technical_params(technical)

    miniapp_id = generate_miniapp_id(short_name)
    client_secret = generate_client_secret
    webhook_secret = generate_webhook_secret

    miniapp = MiniApp.create!(
      miniapp_id: miniapp_id,
      name: name,
      short_name: short_name,
      description: description,
      category: category,
      classification: classification,
      status: "pending_review",
      developer_user_id: user_id,
      developer_company: developer[:company_name],
      developer_email: developer[:email],
      developer_website: developer[:website],
      entry_url: technical[:entry_url],
      redirect_uris: technical[:redirect_uris] || [],
      webhook_url: technical[:webhook_url],
      requested_scopes: technical[:scopes_requested] || [],
      icon_url: branding[:icon_url],
      primary_color: branding[:primary_color],
      client_id: miniapp_id,
      client_secret: client_secret,
      webhook_secret: webhook_secret,
      created_at: Time.current,
      updated_at: Time.current
    )

    MiniAppReviewService.run_automated_checks(miniapp)

    {
      miniapp_id: miniapp.miniapp_id,
      status: miniapp.status,
      credentials: {
        client_id: miniapp.client_id,
        client_secret: miniapp.client_secret,
        webhook_secret: miniapp.webhook_secret
      },
      created_at: miniapp.created_at.iso8601
    }
  end

  def self.update(miniapp:, params:)
    attributes = {}

    attributes[:name] = params[:name] if params[:name].present?
    attributes[:short_name] = params[:short_name] if params[:short_name].present?
    attributes[:description] = params[:description] if params[:description].present?
    attributes[:category] = params[:category] if params[:category].present?
    attributes[:primary_color] = params[:branding][:primary_color] if params.dig(:branding, :primary_color).present?
    attributes[:icon_url] = params[:branding][:icon_url] if params.dig(:branding, :icon_url).present?
    attributes[:entry_url] = params.dig(:technical, :entry_url) if params.dig(:technical, :entry_url).present?
    attributes[:redirect_uris] = params.dig(:technical, :redirect_uris) if params.dig(:technical, :redirect_uris).present?
    attributes[:webhook_url] = params.dig(:technical, :webhook_url) if params.dig(:technical, :webhook_url).present?

    attributes[:updated_at] = Time.current

    miniapp.update!(attributes)

    {
      miniapp_id: miniapp.miniapp_id,
      status: miniapp.status,
      updated_at: miniapp.updated_at.iso8601
    }
  end

  def self.submit_for_review(miniapp)
    if miniapp.status != "draft"
      raise ArgumentError, "Mini-app must be in draft status to submit for review"
    end

    validation_errors = validate_for_submission(miniapp)
    if validation_errors.any?
      raise ArgumentError, "Validation failed: #{validation_errors.join(', ')}"
    end

    miniapp.update!(
      status: "under_review",
      submitted_at: Time.current,
      updated_at: Time.current
    )

    MiniAppReviewService.run_automated_checks(miniapp)

    {
      miniapp_id: miniapp.miniapp_id,
      status: miniapp.status,
      submitted_at: miniapp.submitted_at.iso8601
    }
  end

  def self.submit_appeal(miniapp:, reason:, supporting_info:, user_id:)
    if miniapp.status != "rejected"
      raise ArgumentError, "Mini-app must be rejected to submit appeal"
    end

    appeal = MiniAppAppeal.create!(
      miniapp_id: miniapp.miniapp_id,
      user_id: user_id,
      reason: reason,
      supporting_info: supporting_info,
      status: "pending_review",
      created_at: Time.current
    )

    miniapp.update!(
      status: "appeal_submitted",
      updated_at: Time.current
    )

    {
      appeal_id: appeal.id,
      miniapp_id: miniapp.miniapp_id,
      status: miniapp.status,
      appeal_status: appeal.status,
      created_at: appeal.created_at.iso8601
    }
  end

  def self.validate_for_submission(miniapp)
    errors = []

    errors << "Name is required" if miniapp.name.blank?
    errors << "Description is required" if miniapp.description.blank?
    errors << "Category is required" if miniapp.category.blank?
    errors << "Entry URL is required" if miniapp.entry_url.blank?
    errors << "Entry URL must be HTTPS" unless miniapp.entry_url&.start_with?("https://")
    errors << "Redirect URIs must be HTTPS" unless miniapp.redirect_uris.all? { |uri| uri.start_with?("https://") }

    valid_categories = %w[shopping finance social productivity entertainment utilities]
    errors << "Invalid category" unless valid_categories.include?(miniapp.category)

    errors
  end

  def self.validate_category(category)
    unless CATEGORIES.include?(category)
      raise ArgumentError, "Invalid category: #{category}. Must be one of: #{CATEGORIES.join(', ')}"
    end
  end

  def self.validate_technical_params(technical)
    if technical[:entry_url].blank?
      raise ArgumentError, "entry_url is required"
    end

    unless technical[:entry_url].start_with?("https://")
      raise ArgumentError, "entry_url must use HTTPS"
    end

    if technical[:redirect_uris]
      technical[:redirect_uris].each do |uri|
        unless uri.start_with?("https://")
          raise ArgumentError, "redirect_uris must use HTTPS"
        end
      end
    end
  end

  def self.generate_miniapp_id(short_name)
    sanitized = short_name.downcase.gsub(/[^a-z0-9]/, "")
    "#{sanitized}_#{SecureRandom.alphanumeric(8)}"
  end

  def self.generate_client_secret
    "secret_#{SecureRandom.alphanumeric(24)}"
  end

  def self.generate_webhook_secret
    "whsec_#{SecureRandom.alphanumeric(24)}"
  end
end
