module Admin::FluentIconHelper
  # Renders a Fluent UI System Icon SVG inline
  # Usage: <%= fluent_icon "home", class: "w-5 h-5" %>
  def fluent_icon(name, options = {})
    classes = options[:class] || "w-5 h-5"
    path = Rails.root.join("app/views/admin/shared/icons/#{name}.svg")
    return "<!-- missing: #{name} -->".html_safe unless File.exist?(path)

    svg_content = File.read(path)
    # Inject classes into the svg tag
    svg_content = svg_content.sub(/<svg/, "<svg class=\"#{classes}\"")
    svg_content.html_safe
  end
end
