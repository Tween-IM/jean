# frozen_string_literal: true

module Api
  module V1
    module Social
      class ModerationController < BaseController
        before_action :require_moderator

        def update_video_status
          video_ids = moderation_params[:video_ids]
          new_status = moderation_params[:moderation_status]

          unless %w[approved rejected limited].include?(new_status)
            return render json: { error: "invalid_status", message: "Must be approved, rejected, or limited" }, status: :unprocessable_entity
          end

          if video_ids.present? && video_ids.size > 0
            video = ::SocialVideo.find_by!(video_id: video_ids.first)
          elsif params[:video_id].present?
            video = ::SocialVideo.find_by!(video_id: params[:video_id])
          elsif params[:id].present?
            video = find_video
          else
            return render json: { error: "video_not_found", message: "No video specified" }, status: :not_found
          end

          video.update!(moderation_status: new_status)

          emit_moderation_updated(video)

          render json: {
            video: video_json(video),
            moderation_status: new_status,
            moderated_by: @current_user.matrix_user_id,
            moderated_at: Time.current.iso8601
          }
        end

        def bulk_update
          video_ids = Array(moderation_params[:video_ids])
          new_status = moderation_params[:moderation_status]

          unless %w[approved rejected limited].include?(new_status)
            return render json: { error: "invalid_status", message: "Must be approved, rejected, or limited" }, status: :unprocessable_entity
          end

          updated = 0
          video_ids.each do |vid|
            video = ::SocialVideo.find_by(video_id: vid)
            next unless video

            video.update!(moderation_status: new_status)
            emit_moderation_updated(video)
            updated += 1
          end

          render json: { updated_count: updated, moderation_status: new_status }
        end

        def report_list
          require_scope("social:moderate")

          status = params[:status] || "open"
          page = params[:page].to_i.clamp(1, 1000)
          per_page = [params[:per_page].to_i, 50].max.clamp(1, 50)

          reports = ::SocialReport
            .includes(:social_video)
            .where(status: status)
            .order(created_at: :desc)
            .limit(per_page)
            .offset((page - 1) * per_page)

          render json: {
            reports: reports.map { |r| report_with_video_json(r) },
            page: page,
            per_page: per_page,
            status: status
          }
        end

        def resolve_report
          report = ::SocialReport.find(params[:report_id])
          video = report.social_video

          ActiveRecord::Base.transaction do
            report.update!(status: "resolved")
            case moderation_params[:moderation_status]
            when "rejected"
              video.update!(moderation_status: "rejected")
            when "limited"
              video.update!(moderation_status: "limited")
            end
            emit_moderation_updated(video) if moderation_params[:moderation_status]
          end

          render json: { report: report_json(report), video: video_json(video) }
        end

        private

        def require_moderator
          require_scope("social:moderate")
        end

        def moderation_params
          params.require(:moderation).permit(:moderation_status, :reason, :video_ids => [])
        end

        def emit_moderation_updated(video)
          MatrixEventService.publish_moderation_updated(
            video_id: video.video_id,
            creator_id: video.creator_user_id,
            moderation_status: video.moderation_status,
            message: moderation_reason
          )
        end

        def moderation_reason
          moderation_params[:reason].presence || "Reviewed by moderator"
        end

        def report_with_video_json(report)
          {
            report_id: report.id,
            video_id: report.social_video.video_id,
            reason: report.reason,
            details: report.details,
            status: report.status,
            reporter_user_id: report.reporter_user_id,
            created_at: report.created_at,
            video: {
              video_id: report.social_video.video_id,
              caption: report.social_video.caption,
              creator_user_id: report.social_video.creator_user_id,
              moderation_status: report.social_video.moderation_status
            }
          }
        end
      end
    end
  end
end
