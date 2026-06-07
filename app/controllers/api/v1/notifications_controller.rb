# frozen_string_literal: true

class Api::V1::NotificationsController < Api::V1::Social::BaseController
  def index
    require_scope("social:read")

    scope = Notification.for_user(@current_user.matrix_user_id)
    scope = scope.by_source(params[:source]) if params[:source].present?
    scope = scope.recent

    notifications = scope.page(params[:page] || 1).per(limit_param(default: 20, max: 50))

    render json: {
      success: true,
      data: notifications.map(&:as_json),
      meta: {
        pagination: pagination_meta(notifications),
        unread_count: Notification.for_user(@current_user.matrix_user_id).unread.count
      }
    }
  end

  def unread_count
    require_scope("social:read")

    count = Notification.for_user(@current_user.matrix_user_id).unread.count
    render json: { success: true, unread_count: count }
  end

  def mark_read
    require_scope("social:engage")

    notification = Notification.for_user(@current_user.matrix_user_id).find(params[:id])
    notification.mark_as_read!

    render json: { success: true, data: notification.as_json }
  end

  def mark_all_read
    require_scope("social:engage")

    Notification.for_user(@current_user.matrix_user_id).unread.update_all(read_at: Time.current)

    render json: { success: true, message: "All notifications marked as read" }
  end

  def mark_unread
    require_scope("social:engage")

    notification = Notification.for_user(@current_user.matrix_user_id).find(params[:id])
    notification.mark_as_unread!

    render json: { success: true, data: notification.as_json }
  end

  private

  def pagination_meta(collection)
    {
      current_page: collection.current_page,
      per_page: collection.limit_value,
      total_pages: collection.total_pages,
      total_count: collection.total_count
    }
  end
end
