# frozen_string_literal: true

class MiniAppSubmissionEnrichmentJob < ApplicationJob
  queue_as :default

  def perform(mini_app_id)
    app = MiniApp.find_by(id: mini_app_id)
    return unless app

    preview = MiniAppWebsitePreview.new.call(app.manifest["entry_url"])
    manifest = app.manifest.deep_dup
    if manifest["icon_url"].blank? && preview[:icon_url].present?
      manifest["icon_url"] = preview[:icon_url]
    end
    if manifest["header_image"].blank? && preview[:header_image].present?
      manifest["header_image"] = preview[:header_image]
    end
    if Array(manifest["screenshots"]).empty? && preview[:screenshots].present?
      manifest["screenshots"] = preview[:screenshots]
    end
    app.update!(manifest: manifest)
  rescue PublicWebsiteFetch::Unavailable
    Rails.logger.info("Mini-app enrichment skipped for #{app&.app_id}: site unavailable")
  end
end
