module Admin::PresentationHelper
  def admin_detail_link(label, path, **options)
    data = { turbo_frame: "admin-detail", action: "click->admin-workspace#open" }.merge(options.delete(:data) || {})
    link_to(label, path, **options, data: data)
  end

  def admin_reference(value)
    return "—" if value.blank?
    content_tag(:span, class: "admin-reference", title: value.to_s) do
      safe_join([content_tag(:code, value.to_s.length > 20 ? "…#{value.to_s.last(12)}" : value),
        button_tag("Copy", type: "button", class: "admin-copy", data: { action: "admin-workspace#copy", copy_value: value }, aria: { label: "Copy reference" })])
    end
  end

  def admin_person_name(value)
    return "Not linked" if value.blank?
    value.to_s.delete_prefix("@").split(":").first.tr("_", " ").split.map(&:capitalize).join(" ")
  end

  def admin_person_cell(name, secondary = nil, image: nil)
    content_tag(:div, class: "admin-entity") do
      avatar = image.present? ? image_tag(image, alt: "", loading: "lazy", class: "admin-entity-image") :
        content_tag(:span, name.to_s.split.map(&:first).first(2).join.upcase, class: "admin-avatar", aria: { hidden: true })
      safe_join([avatar, content_tag(:div) { safe_join([content_tag(:strong, name), (content_tag(:small, secondary) if secondary.present?)].compact) }])
    end
  end

  def admin_short_date(value)
    return "—" if value.blank?
    time = value.is_a?(Numeric) ? Time.zone.at(value > 10_000_000_000 ? value / 1000.0 : value) : Time.zone.parse(value.to_s)
    time ? time.strftime("%d %b %Y · %H:%M %Z") : value.to_s
  rescue ArgumentError, TypeError
    "—"
  end

  def admin_field_label(key)
    { "kyc_tier" => "KYC tier", "nin_status" => "NIN verification", "bvn_status" => "BVN verification",
      "pep_status" => "Politically exposed person", "last_four" => "Card ending", "last_updated" => "Last updated",
      "balance_cents" => "Available balance", "limit_cents" => "Spending limit", "gross_amount_cents" => "Payment amount" }
      .fetch(key.to_s, key.to_s.delete_suffix("_cents").humanize)
  end
end
