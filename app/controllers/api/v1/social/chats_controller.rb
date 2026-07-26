# frozen_string_literal: true

class Api::V1::Social::ChatsController < Api::V1::Social::BaseController
  def create
    require_scope("social:engage")

    target_id = params[:target_user_id]
    return render json: { error: "missing_target", message: "target_user_id required" }, status: :bad_request if target_id.blank?

    my_id = @current_user.matrix_user_id
    return render json: { error: "self_chat", message: "Cannot chat with yourself" }, status: :bad_request if target_id == my_id

    chat = SocialChat.find_by(user_a_id: my_id, user_b_id: target_id) ||
           SocialChat.find_by(user_a_id: target_id, user_b_id: my_id)

    unless chat
      chat = SocialChat.create!(user_a_id: my_id, user_b_id: target_id, status: 'active')
      # Bot room creation deferred to U10 (relay bot service)
    end

    other = SocialCreatorProfile.find_by(user_id: chat.other_user_id(my_id))
    render json: {
      chat_id: chat.id,
      matrix_room_id: chat.matrix_room_id,
      status: chat.status,
      blocked: chat.blocked_by?(my_id),
      other_user: other ? creator_json(other) : nil
    }, status: :created
  end

  def index
    require_scope("social:read")

    chats = SocialChat.for_user(@current_user.matrix_user_id)
                      .active
                      .order(last_message_at: :desc, updated_at: :desc)

    render json: {
      chats: chats.map { |c| chat_json(c) }
    }
  end

  def show
    require_scope("social:read")

    chat = find_chat
    render json: { chat: chat_full_json(chat) }
  end

  def block
    require_scope("social:engage")

    chat = find_chat
    return render json: { error: "already_blocked" }, status: :conflict if chat.blocked?

    chat.update!(status: 'blocked', blocked_by_user_id: @current_user.matrix_user_id)
    render json: { chat: chat_json(chat) }
  end

  def unblock
    require_scope("social:engage")

    chat = find_chat
    return render json: { error: "not_blocked" }, status: :conflict unless chat.blocked?
    return render json: { error: "not_blocker" }, status: :forbidden unless chat.blocked_by?(@current_user.matrix_user_id)

    chat.update!(status: 'active', blocked_by_user_id: nil)
    render json: { chat: chat_json(chat) }
  end

  def share_contact
    require_scope("social:engage")

    chat = find_chat
    my_id = @current_user.matrix_user_id
    other_id = chat.other_user_id(my_id)

    ContactShare.find_or_create_by!(from_user_id: my_id, to_user_id: other_id)

    render json: { shared: true, message: "Tween ID shared. When they share back, you can chat directly." }
  end

  def destroy
    require_scope("social:engage")

    chat = find_chat
    chat.update!(status: 'destroyed')
    # Bot room cleanup deferred to U10

    render json: { destroyed: true }
  end

  private

  def find_chat
    SocialChat.for_user(@current_user.matrix_user_id).find(params[:id])
  end

  def chat_json(chat)
    my_id = @current_user.matrix_user_id
    other_id = chat.other_user_id(my_id)
    other = SocialCreatorProfile.find_by(user_id: other_id)

    {
      id: chat.id,
      matrix_room_id: chat.matrix_room_id,
      status: chat.status,
      blocked: chat.blocked_by?(my_id),
      other_user: other ? creator_json(other) : nil,
      last_message_at: chat.last_message_at,
      created_at: chat.created_at
    }
  end

  def chat_full_json(chat)
    chat_json(chat).merge(updated_at: chat.updated_at)
  end
end
