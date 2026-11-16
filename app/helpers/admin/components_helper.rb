module Admin::ComponentsHelper
  def admin_field(name, label:, hint: nil, error: nil, id: nil, &block)
    id ||= name.to_s.gsub(/[^a-zA-Z0-9_-]/, '_')
    content_tag(:div, class: 'admin-form-field') do
      safe_join([label_tag(id, label), capture(id, &block),
        (content_tag(:small, hint, id: "#{id}-hint", class: 'admin-control-hint') if hint),
        (content_tag(:p, error, id: "#{id}-error", class: 'admin-control-error', role: 'alert') if error)].compact)
    end
  end

  def admin_input(name, label:, value: nil, type: 'text', hint: nil, error: nil, **options)
    admin_field(name, label: label, hint: hint, error: error, id: options[:id]) do |id|
      tag.input(**options.merge(name: name, id: id, type: type, value: value,
        class: "admin-input #{options[:class]}", aria: { invalid: error.present? ? 'true' : nil,
          describedby: [hint && "#{id}-hint", error && "#{id}-error"].compact.join(' ').presence }))
    end
  end

  def admin_select(name, label:, choices:, selected: nil, hint: nil, error: nil, **options)
    admin_field(name, label: label, hint: hint, error: error, id: options[:id]) do |id|
      select_tag(name, options_for_select(choices, selected), **options.merge(id: id,
        class: "admin-input #{options[:class]}", aria: { invalid: error.present? ? 'true' : nil,
          describedby: [hint && "#{id}-hint", error && "#{id}-error"].compact.join(' ').presence }))
    end
  end

  def admin_checkbox(name, label:, checked: false, value: '1', hint: nil, switch: false, id: nil, **options)
    id ||= "#{name}-#{value}".gsub(/[^a-zA-Z0-9_-]/, '_')
    content_tag(:label, for: id, class: "admin-check-control #{'admin-switch-control' if switch}") do
      safe_join([check_box_tag(name, value, checked, **options.merge(id: id, role: (switch ? 'switch' : nil))),
        content_tag(:span) { safe_join([content_tag(:span, label), (content_tag(:small, hint) if hint)].compact) }])
    end
  end

  def admin_data_table(records:, columns:, caption: nil, &row)
    if records.empty?
      return render('admin/shared/empty', title: 'No records found', description: 'Try another search or adjust the filters to see more results.')
    end
    content_tag(:div, class: 'admin-table-wrap') do
      content_tag(:table, class: 'admin-table') do
        safe_join([(content_tag(:caption, caption, class: 'sr-only') if caption),
          content_tag(:thead) { content_tag(:tr) { safe_join(columns.map { |column| content_tag(:th, column[:label], scope: 'col') }) } },
          content_tag(:tbody) { safe_join(records.map { |record| content_tag(:tr, capture(record, &row)) }) }].compact)
      end
    end
  end
end
