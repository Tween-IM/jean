require 'test_helper'
class Admin::ComponentsHelperTest < ActionView::TestCase
  include Admin::ComponentsHelper
  include Admin::IconHelper

  test 'all icons use Lucide outlines with safe decorative semantics' do
    svg = Nokogiri::HTML.fragment(admin_icon('package'))
    assert_equal 'none', svg.at_css('svg')['fill']
    assert_equal 'currentColor', svg.at_css('svg')['stroke']
    assert_equal 'true', svg.at_css('svg')['aria-hidden']
    assert_includes svg.at_css('svg')['class'], 'lucide-package'
    assert_empty admin_icon('../outside')
  end

  test 'field errors and hints are associated with the submitted input' do
    html = Nokogiri::HTML.fragment(admin_input('app_name', label: 'App name', value: '<script>', hint: 'Public display name', error: 'Required'))
    assert_equal 'app_name', html.at_css('label')['for']
    assert_equal '<script>', html.at_css('input')['value']
    assert_equal 'true', html.at_css('input')['aria-invalid']
    assert_equal 'app_name-hint app_name-error', html.at_css('input')['aria-describedby']
    assert_empty html.css('script')
  end

  test 'switches preserve native form values and keyboard semantics' do
    html = Nokogiri::HTML.fragment(admin_checkbox('featured', label: 'Featured store', checked: true, switch: true))
    assert_equal 'checkbox', html.at_css('input')['type']
    assert_equal 'switch', html.at_css('input')['role']
    assert_equal 'featured', html.at_css('input')['name']
    assert html.at_css('input')['checked']
    assert_equal html.at_css('input')['id'], html.at_css('label')['for']
  end
end
