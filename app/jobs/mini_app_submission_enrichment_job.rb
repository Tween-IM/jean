# frozen_string_literal: true

class MiniAppSubmissionEnrichmentJob < ApplicationJob
  queue_as :default

  CATEGORIES = %w[shopping finance social productivity entertainment utilities].freeze

  def perform(mini_app_id)
    app = MiniApp.find_by(id: mini_app_id)
    return unless app

    manifest = app.manifest.deep_dup
    enrichment = manifest["enrichment"].to_h
    return unless enrichment["pending"]

    preview = MiniAppWebsitePreview.new.call(manifest["entry_url"])
    updates = {}

    if enrichment["fill_name"] && preview[:name].present?
      updates[:name] = preview[:name].first(80)
    end
    if enrichment["fill_description"] && preview[:description].present?
      updates[:description] = preview[:description]
    end
    if enrichment["fill_category"] && CATEGORIES.include?(preview[:category])
      manifest["category"] = preview[:category]
    end
    if enrichment["fill_icon"] && preview[:icon_url].present?
      manifest["icon_url"] = preview[:icon_url]
    end
    if enrichment["fill_screenshots"] && preview[:screenshots].present?
      manifest["screenshots"] = preview[:screenshots]
    end
    if manifest["header_image"].blank? && preview[:header_image].present?
      manifest["header_image"] = preview[:header_image]
    end

    manifest["enrichment"] = enrichment.merge("pending" => false)
    updates[:manifest] = manifest
    app.update!(updates)
  rescue StandardError => error
    Rails.logger.info(
      "Mini-app enrichment skipped for #{app&.app_id}: #{error.class}"
    )
  end
end
