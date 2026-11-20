module Admin::LayoutHelper
  def sidebar_link(path, label, icon_name, badge_count: nil)
    active = request.path == path || request.path.start_with?("#{path}/")
    parent = { 'compliance_checks' => 'verification_attempts', 'identity_documents' => 'verification_attempts', 'stashes' => 'pockets', 'scheduled_transfers' => 'pockets', 'saving_rules' => 'pockets', 'saving_sweeps' => 'pockets', 'webhook_deliveries' => 'webhooks' }[params[:resource]]
    active ||= parent && path == admin_resource_path(parent)
    link_to path, class: "admin-nav-link", aria: { current: active ? "page" : nil } do
      safe_join([ admin_icon(icon_name), content_tag(:span, label),
        (content_tag(:span, badge_count, class: "admin-badge") if badge_count) ].compact)
    end
  end

  RESOURCE_AREAS = {
    "Commerce" => %w[disputes payouts reviews warehouses shipping_profiles],
    "Money" => %w[wallets transactions cards pending_transfers payment_links protected_payments refunds bank_accounts bills pockets stashes scheduled_transfers saving_rules saving_sweeps exchange_rates rate_alerts recipients agents],
    "Trust & safety" => %w[verification_attempts compliance_checks identity_documents risk_reviews social_reports reports],
    "Community" => %w[rooms social_posts stories],
    "Settings" => %w[api_keys webhooks webhook_deliveries notifications]
  }.freeze

  def admin_navigation
    groups = { "Overview" => [{ label: "Overview", path: admin_dashboard_path, icon: "home" }],
      "People" => [], "Commerce" => [], "Money" => [], "Trust & safety" => [],
      "Community" => [], "Mini-apps" => [], "Settings" => [] }
    items = [
      [:manage_cards, "Money", "Card pricing", admin_card_pricing_path, "credit-card"],
      [:view_risk, "Trust & safety", "Monitoring", admin_monitoring_path, "chart"],
      [:view_users, "People", "Everyone", admin_users_path, "people"],
      [:view_businesses, "People", "Businesses", admin_resource_path("businesses"), "building"],
      [:view_orders, "Commerce", "Orders", admin_orders_path, "shopping-bag"],
      [:view_fulfillment, "Commerce", "Sourcing", admin_procurements_path, "package-search"],
      [:view_storefronts, "Commerce", "Stores", admin_storefronts_path, "store"],
      [:view_catalog, "Commerce", "Products", admin_products_path, "box"],
      [:view_merchants, "Commerce", "Merchants", admin_merchants_path, "handshake"],
      [:view_categories, "Commerce", "Categories", admin_categories_path, "tags"],
      [:view_imports, "Commerce", "Imports", admin_imports_path, "file-input"],
      [:view_mini_apps, "Mini-apps", "All apps", admin_mini_apps_path, "app-window"],
      [:view_mini_apps, "Mini-apps", "Review queue", admin_mini_app_reviews_path, "checkmark"],
      [:view_oauth, "Mini-apps", "OAuth clients", admin_oauth_applications_path, "fingerprint"],
      [:view_audit, "Settings", "Activity log", admin_activity_path, "clock"]
    ]
    items.each do |permission, area, label, path, icon|
      groups[area] << { label: label, path: path, icon: icon } if current_admin_user.has_admin_permission?(permission)
    end
    RESOURCE_AREAS.each do |area, keys|
      keys.each do |key|
        resource = Admin::Resources::CATALOG.fetch(key)
        next unless current_admin_user.has_admin_permission?(resource[:permission])
        next if %w[compliance_checks identity_documents stashes scheduled_transfers saving_rules saving_sweeps webhook_deliveries].include?(key)
        label = { "verification_attempts" => "Review cases", "pockets" => "Savings", "webhooks" => "Webhooks" }.fetch(key, resource[:label])
        groups[area] << { label: label, path: admin_resource_path(key), icon: resource[:icon] }
      end
    end
    groups.reject { |_, items| items.empty? }
  end

  WORKFLOW_VIEWS = [
    { "verification_attempts" => "Identity checks", "compliance_checks" => "Screening", "identity_documents" => "Documents" },
    { "pockets" => "Pockets", "stashes" => "Stashes", "scheduled_transfers" => "Scheduled transfers", "saving_rules" => "Rules", "saving_sweeps" => "Activity" },
    { "webhooks" => "Endpoints", "webhook_deliveries" => "Delivery history" }
  ].freeze

  def admin_jump_destinations
    groups = admin_navigation.transform_values(&:dup)
    RESOURCE_AREAS.each do |area, keys|
      next unless groups[area]
      keys.each do |key|
        resource = Admin::Resources::CATALOG.fetch(key)
        path = admin_resource_path(key)
        next unless current_admin_user.has_admin_permission?(resource[:permission])
        next if groups[area].any? { |item| item[:path] == path }
        groups[area] << { label: resource[:label], path: path, icon: resource[:icon] }
      end
    end
    groups
  end

  def admin_workflow_views
    WORKFLOW_VIEWS.find { |group| group.key?(params[:resource]) }&.filter { |key, _| current_admin_user.has_admin_permission?(Admin::Resources::CATALOG.fetch(key)[:permission]) } || {}
  end

  def admin_current_area
    return "Trust & safety" if %w[compliance_checks identity_documents].include?(params[:resource])
    return "Money" if %w[stashes scheduled_transfers saving_rules saving_sweeps].include?(params[:resource])
    return "Settings" if params[:resource] == "webhook_deliveries"
    @admin_current_area ||= admin_navigation.find do |_, items|
      items.any? { |item| request.path == item[:path] || request.path.start_with?("#{item[:path]}/") }
    end&.first || (controller_name == "users" ? "People" : "Overview")
  end

  def admin_badge(value)
    text = value.to_s
    tone = case text
    when "active", "passed", "success", "paid", "fulfilled", "verified", "approved" then "good"
    when "pending", "requires_review", "in_review", "processing", "initiated", "under_review", "pending_review" then "warning"
    when "suspended", "frozen", "failed", "deactivated", "rejected" then "danger"
    end
    content_tag(:span, text.humanize.presence || "Unknown", class: "admin-badge #{"admin-badge-#{tone}" if tone}")
  end

  def admin_value(value, key = nil, record = {})
    return "—" if value.nil? || value == ""
    return value ? "Yes" : "No" if value == true || value == false
    if key.to_s.end_with?("_cents")
      return "#{number_with_delimiter(value)} minor units" if record["currency"].blank?
      return "#{record['currency']} #{number_with_precision(BigDecimal(value.to_s) / 100, precision: 2, delimiter: ',')}"
    end
    return admin_badge(value) if key.to_s.end_with?("status") || %w[state review_status].include?(key.to_s)
    return value.join(", ") if value.is_a?(Array) && value.none? { |item| item.is_a?(Hash) }
    return "#{value.size} entries" if value.is_a?(Array) || value.is_a?(Hash)
    return admin_short_date(value) if key.to_s.end_with?("_at")
    value.to_s
  end

  # Orders that need a human right now. The sidebar badge and the topbar bell
  # both read this, so operators can see the queue from wherever they are.
  # Lines the platform has to buy and nobody has bought yet: the sourcing
  # queue's own "to do" count. Memoised for the same reason as above.
  def sourcing_queue_count
    return @sourcing_queue_count if defined?(@sourcing_queue_count)

    @sourcing_queue_count = begin
      if current_admin_user&.has_admin_permission?(:view_fulfillment)
        CommerceProcurement.awaiting_purchase.count
      else
        0
      end
    rescue ActiveRecord::StatementInvalid => e
      Rails.logger.error "sourcing_queue_count failed: #{e.message}"
      0
    end
  end

  def commerce_attention_count
    return @commerce_attention_count if defined?(@commerce_attention_count)

    @commerce_attention_count = begin
      if current_admin_user&.has_admin_permission?(:view_orders)
        CommerceOrder
          .where(status: %w[pending_payment paid processing], fulfillment_status: %w[unfulfilled partially_fulfilled])
          .count
      else
        0
      end
    rescue ActiveRecord::StatementInvalid => e
      Rails.logger.error "commerce_attention_count failed: #{e.message}"
      0
    end
  end
end
