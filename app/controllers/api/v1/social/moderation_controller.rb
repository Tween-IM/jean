# frozen_string_literal: true

class Api::V1::Social::ModerationController < Api::V1::Social::BaseController
  before_action :require_moderator

  def update_post_status
    post_ids = moderation_params[:post_ids]
    new_status = moderation_params[:moderation_status]

    unless %w[approved rejected limited].include?(new_status)
      return render json: { error: "invalid_status", message: "Must be approved, rejected, or limited" }, status: :unprocessable_entity
    end

    if post_ids.present? && post_ids.size > 0
      post = ::SocialPost.find_by!(post_id: post_ids.first)
    elsif params[:id].present?
      post = find_post
    else
      return render json: { error: "post_not_found", message: "No post specified" }, status: :not_found
    end

    post.update!(moderation_status: new_status)

    emit_moderation_updated(post)

    render json: {
      post: post_json(post),
      moderation_status: new_status,
      moderated_by: @current_user.matrix_user_id,
      moderated_at: Time.current.iso8601
    }
  end

  def bulk_update
    post_ids = Array(moderation_params[:post_ids])
    new_status = moderation_params[:moderation_status]

    unless %w[approved rejected limited].include?(new_status)
      return render json: { error: "invalid_status", message: "Must be approved, rejected, or limited" }, status: :unprocessable_entity
    end

    updated = 0
    ActiveRecord::Base.transaction do
      post_ids.each do |post_id|
        post = ::SocialPost.find_by(post_id: post_id)
        next unless post

        post.update!(moderation_status: new_status)
        emit_moderation_updated(post)
        updated += 1
      end
    end

    render json: { updated_count: updated, moderation_status: new_status }
  end

  def report_list
    require_scope("social:moderate")

    status = params[:status] || "open"
    page = params[:page].to_i.clamp(1, 1000)
    per_page = (params[:per_page].presence || 50).to_i.clamp(1, 50)

    reports = ::SocialReport
      .includes(:social_post)
      .where(status: status)
      .order(created_at: :desc)
      .limit(per_page)
      .offset((page - 1) * per_page)

    render json: {
      reports: reports.map { |r| report_with_post_json(r) },
      page: page,
      per_page: per_page,
      status: status
    }
  end

  def resolve_report
    report = ::SocialReport.find(params[:report_id])
    post = report.social_post

    ActiveRecord::Base.transaction do
      report.update!(status: "resolved")
      case moderation_params[:moderation_status]
      when "rejected"
        post.update!(moderation_status: "rejected")
      when "limited"
        post.update!(moderation_status: "limited")
      end
      emit_moderation_updated(post) if moderation_params[:moderation_status]
    end

    render json: { report: report_json(report), post: post_json(post) }
  end

  private

  def require_moderator
    require_scope("social:moderate")
  end

  def moderation_params
    params.require(:moderation).permit(:moderation_status, :reason, post_ids: [])
  end

  def emit_moderation_updated(post)
    MatrixEventService.publish_moderation_updated(
      post_id: post.post_id,
      creator_id: post.creator_user_id,
      moderation_status: post.moderation_status,
      message: moderation_reason
    )
  end

  def moderation_reason
    moderation_params[:reason].presence || "Reviewed by moderator"
  end

  def report_with_post_json(report)
    {
      report_id: report.id,
      post_id: report.social_post.post_id,
      reason: report.reason,
      details: report.details,
      status: report.status,
      reporter_user_id: report.reporter_user_id,
      created_at: report.created_at,
      post: {
        post_id: report.social_post.post_id,
        caption: report.social_post.caption,
        creator_user_id: report.social_post.creator_user_id,
        moderation_status: report.social_post.moderation_status
      }
    }
  end
end
