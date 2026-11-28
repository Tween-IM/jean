# frozen_string_literal: true

require "ipaddr"
require "timeout"

module Api
  module V1
    module Developer
      class MiniAppsController < Api::BaseController
        include Api::TepAuthenticatable

        before_action :authenticate_tep_token
        before_action :ensure_first_party
        before_action :set_mini_app, only: [ :update ]
        before_action :ensure_editable, only: [ :update ]
        rate_limit to: 6, within: 1.hour, only: [ :create, :update ],
          by: -> { @current_user&.id || request.remote_ip },
          with: -> { render json: { error: "rate_limited", message: "Try again later." }, status: :too_many_requests }

        CATEGORIES = %w[shopping finance social productivity entertainment utilities].freeze
        ALLOWED_PERMISSIONS = %w[user:read storage:read storage:write].freeze

        def index
          apps = MiniApp.where(developer_user_id: @current_user.matrix_user_id).order(created_at: :desc)
          render json: { apps: apps.map { |app| serialize(app) } }
        end

        def create
          entry_url = params[:entry_url].to_s.strip
          raise ArgumentError, "Add your website URL." if entry_url.blank?
          raise ArgumentError, "Use a public HTTPS website URL." unless valid_submission_url?(entry_url)

          preview = needs_preview? ? preview_for(entry_url) : nil
          proposed_name = params[:name].to_s.strip.presence ||
            preview&.dig(:name).to_s.strip.presence ||
            derived_name(entry_url)
          app = MiniApp.new(app_id: build_app_id(proposed_name))
          app.developer_user_id = @current_user.matrix_user_id
          submit(app, resubmit: false, preview: preview)
          render json: { app: serialize(app) }, status: :created
        rescue Admin::MiniAppSubmission::Invalid, ActiveRecord::RecordInvalid, ArgumentError => error
          render json: { error: "invalid_submission", message: error.message }, status: :unprocessable_entity
        end

        def update
          submit(@mini_app, resubmit: true, preview: nil)
          render json: { app: serialize(@mini_app) }
        rescue Admin::MiniAppSubmission::Invalid, ActiveRecord::RecordInvalid, ArgumentError => error
          render json: { error: "invalid_submission", message: error.message }, status: :unprocessable_entity
        end

        private

        def submit(app, resubmit:, preview:)
          entry_url = params[:entry_url].to_s.strip.presence ||
            app.manifest&.dig("entry_url").to_s.presence
          raise ArgumentError, "Add your website URL." if entry_url.blank?
          raise ArgumentError, "Use a public HTTPS website URL." unless valid_submission_url?(entry_url)

          provided_name = params[:name].to_s.strip
          provided_description = params[:description].to_s.strip
          provided_category = params[:category].to_s.strip.downcase
          provided_icon = params[:icon_url].to_s.strip
          raise ArgumentError, "Choose a valid category." if provided_category.present? && !CATEGORIES.include?(provided_category)
          raise ArgumentError, "App name is too long." if provided_name.length > 80
          raise ArgumentError, "Description is too long." if provided_description.length > 2000
          raise ArgumentError, "Use an HTTPS icon URL." if provided_icon.present? && PublicWebsiteFetch.url(provided_icon).nil?

          preview_name = preview&.dig(:name).to_s.strip
          preview_description = preview&.dig(:description).to_s.strip
          preview_icon = preview&.dig(:icon_url)
          preview_category = preview&.dig(:category)
          preview_screenshots = Array(preview&.dig(:screenshots))

          if resubmit
            name = provided_name.presence || app.name
            description = provided_description.presence || app.description.to_s
            category = provided_category.presence || app.manifest&.dig("category").presence || "utilities"
            icon_url = provided_icon.presence || app.manifest&.dig("icon_url")
            screenshots = if params.key?(:screenshots)
              clean_screenshots(params[:screenshots])
            else
              Array(app.manifest&.dig("screenshots"))
            end
            header_image = app.manifest&.dig("header_image")
            enrichment = app.manifest&.dig("enrichment") || {}
          else
            name = provided_name.presence || preview_name.presence || derived_name(entry_url)
            name = name.first(80) if provided_name.blank? && name.length > 80
            description = provided_description.presence || preview_description
            description = description.first(2000) if description.present? && provided_description.blank?
            category = provided_category.presence || preview_category.presence || "utilities"
            icon_url = provided_icon.presence || preview_icon
            screenshots = if params.key?(:screenshots) && Array(params[:screenshots]).any?
              clean_screenshots(params[:screenshots])
            else
              preview_screenshots
            end
            header_image = preview&.dig(:header_image)
            enrichment = {
              "fill_name" => provided_name.blank? && preview_name.blank?,
              "fill_description" => provided_description.blank? && preview_description.blank?,
              "fill_category" => provided_category.blank? && !CATEGORIES.include?(preview_category),
              "fill_icon" => provided_icon.blank? && preview_icon.blank?,
              "fill_screenshots" => (params.key?(:screenshots) ? screenshots.blank? : true) &&
                preview_screenshots.empty?
            }
            enrichment["pending"] = enrichment["fill_name"] || enrichment["fill_icon"]
          end

          raise ArgumentError, "App name is required." if name.blank?
          raise ArgumentError, "Choose a valid category." unless CATEGORIES.include?(category)

          developer_name = params[:developer_name].to_s.strip.presence ||
            app.developer_name.presence ||
            @current_user.matrix_username.to_s.split(":").first.presence ||
            "Tween developer"
          permissions = if params.key?(:permissions)
            Array(params[:permissions]).map(&:to_s).uniq & ALLOWED_PERMISSIONS
          else
            Array(app.manifest&.dig("permissions"))
          end

          manifest = (app.manifest || {}).deep_dup
          manifest.merge!(
            "category" => category,
            "developer" => { "name" => developer_name },
            "permissions" => permissions,
            "redirect_uris" => [ entry_url ],
            "enrichment" => enrichment
          )
          if header_image.present? && manifest["header_image"].blank?
            manifest["header_image"] = header_image
          end
          app.manifest = manifest

          attributes = {
            "name" => name,
            "description" => description.to_s,
            "version" => app.persisted? ? app.version : (params[:version].presence || "1.0.0"),
            "developer_name" => developer_name,
            "classification" => app.persisted? ? app.classification : "community",
            "client_type" => "public"
          }
          attributes["app_id"] = app.app_id unless app.persisted?

          submission_manifest = {
            "entry_url" => entry_url,
            "icon_url" => icon_url.to_s,
            "screenshots" => screenshots.join("\n"),
            "runtime" => "website",
            "permissions" => [ "public", *permissions ].uniq
          }

          Admin::MiniAppSubmission.call(app: app, attributes: attributes, manifest: submission_manifest)
          app.update!(
            developer_user_id: @current_user.matrix_user_id,
            submitted_at: Time.current,
            reviewed_at: nil,
            rejection_reason: nil,
            revision_request: nil,
            revision_requested_at: nil
          )
          MiniAppSubmissionEnrichmentJob.perform_later(app.id) if enrichment["pending"]
        end

        def needs_preview?
          params[:name].blank? ||
            params[:description].blank? ||
            params[:icon_url].blank? ||
            params[:category].blank? ||
            !params.key?(:screenshots) ||
            Array(params[:screenshots]).empty?
        end

        def preview_for(entry_url)
          Timeout.timeout(10) { MiniAppWebsitePreview.new.call(entry_url) }
        rescue StandardError => error
          Rails.logger.info(
            "Submission enrichment skipped for #{entry_url}: #{error.class}"
          )
          nil
        end

        def clean_screenshots(value)
          urls = Array(value).map { |url| url.to_s.strip }.reject(&:empty?).uniq
          raise ArgumentError, "Use up to six HTTPS screenshot URLs." if urls.length > 6
          raise ArgumentError, "Use HTTPS screenshot URLs." unless urls.all? { |url| PublicWebsiteFetch.url(url) }

          urls
        end

        def derived_name(entry_url)
          host = URI.parse(entry_url).hostname.to_s.sub(/\Awww\./, "")
          host.split(".").first.to_s.split(/[-_]/).map(&:capitalize).join(" ").presence ||
            "Mini app"
        rescue URI::Error
          "Mini app"
        end

        def valid_submission_url?(value)
          uri = PublicWebsiteFetch.url(value)
          return false unless uri

          host = uri.hostname.to_s.downcase
          return false if host == "localhost" || host.end_with?(".local", ".internal", ".localhost")
          return false unless host.include?(".")

          begin
            ip = IPAddr.new(host)
            return false if ip.private? || ip.loopback? || ip.link_local?
          rescue IPAddr::InvalidAddressError
            # Hostname, not a literal IP.
          end
          true
        end

        def ensure_first_party
          allowed = ENV.fetch(
            "FIRST_PARTY_MINIAPPS",
            "ma_tweenpay,ma_tweencommerce,ma_tweensocial"
          ).split(",")
          return if allowed.include?(@miniapp_id)

          render json: {
            error: "forbidden",
            message: "Publishing is only available in Tween."
          }, status: :forbidden
        end

        def set_mini_app
          @mini_app = MiniApp.find_by(
            app_id: params[:miniapp_id],
            developer_user_id: @current_user.matrix_user_id
          )
          render json: { error: "not_found", message: "Mini-app not found." }, status: :not_found unless @mini_app
        end

        def ensure_editable
          return if %w[pending_review under_review changes_requested rejected].include?(@mini_app.status)

          render json: {
            error: "not_editable",
            message: "Only apps in review or needing changes can be edited here."
          }, status: :unprocessable_entity
        end

        def build_app_id(name)
          base = name.to_s.parameterize(separator: "").first(24).presence || "app"
          10.times do
            candidate = "ma_#{base}#{SecureRandom.alphanumeric(4).downcase}"
            return candidate unless MiniApp.exists?(app_id: candidate)
          end
          "ma_#{SecureRandom.alphanumeric(12).downcase}"
        end

        def serialize(app)
          manifest = app.manifest || {}
          {
            miniapp_id: app.app_id,
            name: app.name,
            description: app.description.to_s,
            category: manifest["category"].to_s,
            status: app.status,
            classification: app.classification,
            icon_url: manifest["icon_url"].presence,
            entry_url: manifest["entry_url"].to_s,
            permissions: Array(manifest["permissions"]),
            screenshots: Array(manifest["screenshots"]),
            enrichment_pending: manifest.dig("enrichment", "pending") == true,
            version: app.version,
            submitted_at: app.submitted_at&.iso8601,
            reviewed_at: app.reviewed_at&.iso8601,
            rejection_reason: app.rejection_reason,
            revision_request: app.revision_request,
            created_at: app.created_at&.iso8601,
            updated_at: app.updated_at&.iso8601
          }
        end
      end
    end
  end
end
