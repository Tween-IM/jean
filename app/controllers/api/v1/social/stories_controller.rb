# frozen_string_literal: true

class Api::V1::Social::StoriesController < Api::V1::Social::BaseController
  def index
    require_scope("social:read")

    # Active stories from followed creators + self
    following_ids = SocialFollow.where(
      follower_user_id: @current_user.matrix_user_id,
      status: "active"
    ).pluck(:creator_user_id)

    creator_ids = (following_ids + [@current_user.matrix_user_id]).uniq

    # Return oldest first so stories play chronologically (oldest → newest)
    stories = SocialStory.active
                         .where(creator_user_id: creator_ids)
                         .order(created_at: :asc)

    # Group by creator
    grouped = stories.group_by(&:creator_user_id)

    # Preload creator profiles
    profiles = SocialCreatorProfile.where(user_id: creator_ids).index_by(&:user_id)

    # Preload which stories the current user has viewed
    story_ids = stories.map(&:id)
    viewed_story_ids = SocialStoryView.where(
      social_story_id: story_ids,
      viewer_user_id: @current_user.matrix_user_id
    ).pluck(:social_story_id).to_set

    render json: {
      stories: grouped.transform_values do |creator_stories|
        creator_stories.map { |s| story_json(s, viewed_story_ids) }
      end,
      creators: profiles.transform_values { |p| creator_json(p) }
    }
  end

  def create
    require_scope("social:write")

    creator = current_creator_profile
    attributes = story_params.merge(creator_user_id: creator.user_id)
    signed_blob_id = attributes.delete(:signed_blob_id)

    story = creator.social_stories.new(attributes)

    if signed_blob_id.present?
      story.source_media.attach(signed_blob_id)
      if story.source_media.attached?
        ActiveStorage::Current.url_options = { host: request.base_url }
        story.media_url = story.source_media.url
        # Duration is sent by client (trimmed on device); no server-side probe needed
      end
    end

    if story.save
      render json: { story: story_json(story, Set.new) }, status: :created
    else
      render_errors(story)
    end
  end

  def destroy
    require_scope("social:write")

    story = SocialStory.find(params[:id])

    unless story.creator_user_id == @current_user.matrix_user_id
      return render json: { error: "forbidden", message: "Only the creator can delete this story" }, status: :forbidden
    end

    story.update!(status: "deleted")
    head :no_content
  end

  def view
    require_scope("social:engage")

    story = SocialStory.active.find(params[:id])

    SocialStoryView.find_or_create_by!(
      social_story: story,
      viewer_user_id: @current_user.matrix_user_id
    ) do |view|
      view.viewed_at = Time.current
    end

    head :no_content
  end

  private

  def story_params
    params.require(:story).permit(:media_url, :media_type, :caption, :signed_blob_id, :background_color, :duration_seconds)
  end

  def probe_video_duration(attachment)
    return nil unless defined?(Open3) && system("which ffprobe > /dev/null 2>&1")

    temp = File.join(Dir.tmpdir, "story_probe_#{SecureRandom.hex(4)}.bin")
    File.open(temp, "wb") { |f| attachment.blob.download { |c| f.write(c) } }
    out, _err, status = Open3.capture3(
      "ffprobe", "-v", "error",
      "-show_entries", "format=duration",
      "-of", "default=noprint_wrappers=1:nokey=1",
      temp
    )
    File.delete(temp) if File.exist?(temp)
    return nil unless status.success?

    seconds = out.to_f
    seconds.positive? ? seconds.round : nil
  rescue StandardError
    nil
  end

  def story_json(story, viewed_set)
    ActiveStorage::Current.url_options = { host: request.base_url } if ActiveStorage::Current.url_options.blank?

    {
      id: story.id,
      story_id: story.story_id,
      creator_user_id: story.creator_user_id,
      media_url: story.source_media.attached? ? story.source_media.url : story.media_url,
      media_type: story.media_type,
      caption: story.caption,
      background_color: story.background_color,
      duration: story.duration_seconds,
      viewed: viewed_set.include?(story.id),
      created_at: story.created_at,
      expires_at: story.expires_at
    }
  end
end
