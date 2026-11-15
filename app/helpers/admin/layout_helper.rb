module Admin::LayoutHelper
  def sidebar_link(path, label, icon_name, badge_count: nil)
    active = request.path == path || request.path.start_with?("#{path}/")
    link_to path, class: "admin-nav-link", aria: { current: active ? "page" : nil } do
      safe_join([ fluent_icon(icon_name), content_tag(:span, label),
        (content_tag(:span, badge_count, class: "admin-badge") if badge_count) ].compact)
    end
  end

  def admin_navigation
    groups = { "" => [ { label: "Overview", path: admin_dashboard_path, icon: "home" } ],
      "Workspace" => [ { label: "People", path: admin_users_path, icon: "people" } ],
      "Commerce" => [], "Money" => [], "Messaging" => [], "Platform" => [], "Administration" => [] }
    [ [ :view_orders, "Orders", admin_orders_path, "money" ],
     [ :view_fulfillment, "Sourcing", admin_procurements_path, "box" ],
     [ :view_storefronts, "Stores", admin_storefronts_path, "building" ],
     [ :view_catalog, "Products", admin_products_path, "clipboard" ],
     [ :view_merchants, "Merchants", admin_merchants_path, "people" ],
     [ :view_categories, "Categories", admin_categories_path, "filter" ],
     [ :view_imports, "Imports", admin_imports_path, "document" ] ].each do |permission, label, path, icon|
      groups["Commerce"] << { label: label, path: path, icon: icon } if current_admin_user.has_admin_permission?(permission)
    end
    Admin::Resources::CATALOG.each do |key, resource|
      next unless current_admin_user.has_admin_permission?(resource[:permission])
      groups[resource[:group]] << { label: resource[:label], path: admin_resource_path(key), icon: resource[:icon] }
    end
    [ [ :view_mini_apps, "Mini-apps", admin_mini_apps_path, "clipboard" ],
     [ :view_mini_apps, "App reviews", admin_mini_app_reviews_path, "checkmark" ],
     [ :view_oauth, "OAuth apps", admin_oauth_applications_path, "settings" ] ].each do |permission, label, path, icon|
      groups["Platform"] << { label: label, path: path, icon: icon } if current_admin_user.has_admin_permission?(permission)
    end
    if current_admin_user.has_admin_permission?(:view_audit)
      groups["Administration"] << { label: "Activity log", path: admin_activity_path, icon: "document" }
    end
    groups
  end

  def admin_badge(value)
    text = value.to_s
    tone = case text
    when "active", "passed", "success", "paid", "fulfilled", "verified" then "good"
    when "pending", "requires_review", "in_review", "processing", "initiated" then "warning"
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
    return admin_badge(value) if %w[status state].include?(key.to_s)
    return value.join(", ") if value.is_a?(Array) && value.none? { |item| item.is_a?(Hash) }
    return "#{value.size} entries" if value.is_a?(Array) || value.is_a?(Hash)
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
