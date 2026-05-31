# frozen_string_literal: true

module Api
  module V1
    module Social
      class BaseController < Api::BaseController
        include Api::TepAuthenticatable

        before_action :authenticate_tep_token

        private

        def current_creator_profile
          @current_creator_profile ||= SocialCreatorProfile.find_or_create_by!(user_id: @current_user.matrix_user_id) do |profile|
            profile.handle = @current_user.matrix_username.to_s.split(":").first
            profile.display_name = @current_user.matrix_username
          end
        end

        def find_video
          ::SocialVideo.find_by!(video_id: params[:video_id] || params[:id])
        end

        def find_creator_profile
          ::SocialCreatorProfile.find_by!(user_id: params[:creator_id] || params[:id])
        end

        def ensure_video_visible(video)
          return false if video.visible_to?(@current_user)

          render json: { error: "not_found", message: "Video not found" }, status: :not_found
          true
        end

        def ensure_video_owner(video)
          return false if video.creator_user_id == @current_user.matrix_user_id

          render json: { error: "forbidden", message: "Only the creator can change this video" }, status: :forbidden
          true
        end

        def render_errors(record)
          render json: { error: "validation_failed", messages: record.errors.full_messages }, status: :unprocessable_entity
        end

        def preload_creator_profiles(videos)
          creator_ids = videos.map(&:creator_user_id).uniq
          @creator_profiles = SocialCreatorProfile.where(user_id: creator_ids).index_by(&:user_id)
        end

        def video_json(video)
          creator = @creator_profiles&.[](video.creator_user_id) || SocialCreatorProfile.find_by(user_id: video.creator_user_id)
          {
            video_id: video.video_id,
            creator_user_id: video.creator_user_id,
            creator: creator ? creator_json(creator) : nil,
            caption: video.caption,
            playback_url: video.playback_url,
            thumbnail_url: video.thumbnail_url,
            source_video_attached: video.source_video.attached?,
            duration_seconds: video.duration_seconds,
            visibility: video.visibility,
            status: video.status,
            moderation_status: video.moderation_status,
            commerce_refs: video.commerce_refs,
            view_count: video.view_count,
            like_count: video.like_count,
            comment_count: video.comment_count,
            share_count: video.share_count,
            liked: video.liked_by?(@current_user),
            bookmarked: video.bookmarked_by?(@current_user),
            published_at: video.published_at,
            created_at: video.created_at
          }
        end

        def creator_json(profile)
          {
            user_id: profile.user_id,
            handle: profile.handle,
            display_name: profile.display_name,
            avatar_url: profile.avatar_url,
            bio: profile.bio,
            follower_count: profile.follower_count,
            following_count: profile.following_count,
            video_count: profile.video_count,
            verified: profile.verified
          }
        end

        def comment_json(comment)
          {
            comment_id: comment.id,
            video_id: comment.social_video.video_id,
            parent_comment_id: comment.parent_comment_id,
            author_user_id: comment.author_user_id,
            body: comment.body,
            status: comment.status,
            created_at: comment.created_at
          }
        end

        def bookmark_json(bookmark)
          {
            bookmark_id: bookmark.id,
            video: video_json(bookmark.social_video),
            created_at: bookmark.created_at
          }
        end

        def share_json(share)
          {
            share_id: share.id,
            video_id: share.social_video.video_id,
            target: share.target,
            room_id: share.room_id,
            metadata: share.metadata,
            created_at: share.created_at
          }
        end

        def report_json(report)
          {
            report_id: report.id,
            video_id: report.social_video.video_id,
            reason: report.reason,
            status: report.status,
            created_at: report.created_at
          }
        end

        def limit_param(default: 20, max: 50)
          [[ params.fetch(:limit, default).to_i, 1 ].max, max].min
        end
      end
    end
  end
end
