module Admin::LayoutHelper
  def sidebar_link(path, label, icon_name, badge_count: nil)
    active = request.path == path || request.path.start_with?("#{path}/")
    base_classes = "flex items-center gap-3 px-3 py-2 text-sm font-medium rounded-lg transition-colors"
    active_classes = "bg-gray-100 text-gray-900 border-l-2 border-indigo-600 -ml-0.5 pl-[13px]"
    inactive_classes = "text-gray-600 hover:bg-gray-50 hover:text-gray-900"

    link_to path, class: "#{base_classes} #{active ? active_classes : inactive_classes}" do
      icon = fluent_icon(icon_name, class: "w-5 h-5 flex-shrink-0 #{active ? 'text-indigo-600' : 'text-gray-400'}")
      label_html = "<span>#{label}</span>"
      badge_html = badge_count ? "<span class=\"ml-auto px-2 py-0.5 text-xs font-medium bg-red-500 text-white rounded-full\">#{badge_count}</span>" : ""
      "#{icon}#{label_html}#{badge_html}".html_safe
    end
  end
end