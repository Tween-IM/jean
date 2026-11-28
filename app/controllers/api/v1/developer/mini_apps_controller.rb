# frozen_string_literal: true

require "ipaddr"

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
          app = MiniApp.new(app_id: build_app_id(params[:name]))
          app.developer_user_id = @current_user.matrix_user_id
          submit(app, resubmit: false)
          render json: { app: serialize(app) }, status: :created
        rescue Admin::MiniAppSubmission::Invalid, ActiveRecord::RecordInvalid, ArgumentError => error
          render json: { error: "invalid_submission", message: error.message }, status: :unprocessable_entity
        end

        def update
          submit(@mini_app, resubmit: true)
          render json: { app: serialize(@mini_app) }
        rescue Admin::MiniAppSubmission::Invalid, ActiveRecord::RecordInvalid, ArgumentError => error
          render json: { error: "invalid_submission", message: error.message }, status: :unprocessable_entity
        end

        private

        def submit(app, resubmit:)
          entry_url = value_for(:entry_url, app)
          raise ArgumentError, "A public HTTPS launch URL is required." unless valid_submission_url?(entry_url)

          category = value_for(:category, app)
          raise ArgumentError, "Choose a valid category." unless CATEGORIES.include?(category)

          permissions = permitted_permissions(app)
          developer_name = value_for(:developer_name, app).presence ||
            @current_user.matrix_username.to_s.split(":").first.presence || "Tween developer"
          name = value_for(:name, app).to_s.strip
          description = value_for(:description, app).to_s.strip
          raise ArgumentError, "App name is required." if name.blank?
          raise ArgumentError, "Description is required." if description.blank?
          raise ArgumentError, "App name is too long." if name.length > 80
          raise ArgumentError, "Description is too long." if description.length > 2000

          icon_url = value_for(:icon_url, app).to_s.strip
          screenshots = screenshot_urls(app)
          icon_url = nil if icon_url.blank?
          raise ArgumentError, "Use an HTTPS icon URL." unless icon_url.nil? || PublicWebsiteFetch.url(icon_url)

          manifest = (app.manifest || {}).deep_dup
          manifest.merge!(
            "category" => category,
            "developer" => { "name" => developer_name },
            "permissions" => permissions,
            "redirect_uris" => [ entry_url ]
          )
          app.manifest = manifest

          attributes = {
            "name" => name,
            "description" => description,
            "version" => app.persisted? ? app.version : (params[:version].presence || "1.0.0"),
            "developer_name" => developer_name,
            "classification" => app.persisted? ? app.classification : "community",
            "client_type" => "public"
          }
          attributes["app_id"] = app.app_id unless app.persisted?

          submission_manifest = {
            "entry_url" => entry_url,
            "icon_url" => icon_url,
            "screenshots" => screenshots.join("\n"),
            "runtime" => "website",
            "permissions" => [ "public", *permissions ].uniq
          }

          if icon_url.blank?
            submission_manifest["entry_url"] = entry_url
          end

          Admin::MiniAppSubmission.call(app: app, attributes: attributes, manifest: submission_manifest)
          app.update!(
            developer_user_id: @current_user.matrix_user_id,
            submitted_at: Time.current,
            reviewed_at: nil,
            rejection_reason: nil,
            revision_request: nil,
            revision_requested_at: nil
          )
          MiniAppSubmissionEnrichmentJob.perform_later(app.id) if icon_url.blank? || screenshots.empty?
        end

        def value_for(key, app)
          value = params[key]
          return value if value.present?

          case key
          when :entry_url, :category, :icon_url
            app.manifest&.dig(key.to_s)
          when :developer_name
            app.developer_name
          when :name
            app.name
          when :description
            app.description
          end
        end

        def permitted_permissions(app)
          requested = params[:permissions]
          if requested.nil?
            existing = Array(app.manifest&.dig("permissions"))
            requested = existing
          end
          Array(requested).map(&:to_s).uniq & ALLOWED_PERMISSIONS
        end

        def screenshot_urls(app)
          requested = params[:screenshots]
          urls = requested.nil? ? Array(app.manifest&.dig("screenshots")) : Array(requested)
          urls = urls.map { |url| url.to_s.strip }.reject(&:empty?).uniq
          raise ArgumentError, "Use up to six HTTPS screenshot URLs." if urls.length > 6
          raise ArgumentError, "Use HTTPS screenshot URLs." unless urls.all? { |url| PublicWebsiteFetch.url(url) }

          urls
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
