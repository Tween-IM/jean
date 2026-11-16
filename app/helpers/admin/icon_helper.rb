module Admin::IconHelper
  LEGACY_NAMES = {
      "home" => "house",
      "people" => "users-round",
      "person" => "user-round",
      "chart" => "chart-no-axes-combined",
      "money" => "banknote",
      "box" => "package",
      "building" => "building-2",
      "clipboard" => "clipboard-list",
      "settings" => "settings-2",
      "shield" => "shield-check",
      "document" => "file-text",
      "clock" => "history",
      "alert" => "triangle-alert",
      "checkmark" => "check",
      "filter" => "list-filter",
      "add" => "plus",
      "arrow_swap" => "arrow-left-right",
      "dismiss" => "x",
      "chevron_right" => "chevron-right",
      "sign_out" => "log-out",
      "more_horizontal" => "ellipsis"
  }.freeze
  ICON_ROOT = Rails.root.join('app/assets/images/admin/icons')
  ICONS = Dir[ICON_ROOT.join('*.svg')].to_h { |path| [File.basename(path, '.svg'), File.read(path).freeze] }.freeze

  def admin_icon(name, options = {})
    key = LEGACY_NAMES.fetch(name.to_s, name.to_s)
    svg = ICONS[key]
    return ''.html_safe unless svg
    classes = ERB::Util.html_escape("admin-icon lucide lucide-#{key} #{options[:class]}")
    svg.sub(/class="[^"]*"/, "class=\"#{classes}\"").sub('<svg', '<svg aria-hidden="true" focusable="false"').html_safe
  end
end
