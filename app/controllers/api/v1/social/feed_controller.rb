# frozen_string_literal: true

require "base64"

module Api
  module V1
    module Social
      class FeedController < BaseController
        FEED_TYPES = %w[for_you following creator saved].freeze
        RANKED_FEED_SIZE = 500

        def show
          require_scope("social:read")

          feed_type = params[:type].presence || "for_you"
          cursor = params[:cursor]
          limit = limit_param

          videos, next_cursor = case feed_type
          when "following"
            following_feed(cursor, limit)
          when "creator"
            creator_feed(params[:creator_id], cursor, limit)
          when "saved"
            saved_feed(cursor, limit)
          else
            for_you_feed(cursor, limit)
          end

          render json: {
            items: videos.map { |video| video_json(video) },
            next_cursor: next_cursor,
            has_more: next_cursor.present?,
            feed_type: feed_type
          }
        end

        private

        def for_you_feed(cursor, limit)
          ranked_feed(cursor, limit)
        end

        def following_feed(cursor, limit)
          following_ids = SocialFollow.active.where(follower_user_id: @current_user.matrix_user_id).pluck(:creator_user_id)
          return [ [], nil ] if following_ids.empty?

          query = ::SocialVideo.feedable.where(creator_user_id: following_ids)
          apply_cursor(query, cursor, limit)
        end

        def creator_feed(creator_id, cursor, limit)
          return [ [], nil ] if creator_id.blank?

          query = ::SocialVideo.feedable.where(creator_user_id: creator_id)
          apply_cursor(query, cursor, limit)
        end

        def saved_feed(cursor, limit)
          saved_video_ids = SocialBookmark.where(user_id: @current_user.matrix_user_id).pluck(:social_video_id)
          return [ [], nil ] if saved_video_ids.empty?

          query = ::SocialVideo.feedable.where(id: saved_video_ids)
          apply_cursor(query, cursor, limit)
        end

        def ranked_feed(cursor, limit)
          engagement_scores = ::SocialVideo.feedable
            .pluck(:id, :like_count, :comment_count, :share_count, :view_count, :published_at)
            .map do |id, likes, comments, shares, views, published|
            score = (likes * 3) + (comments * 5) + (shares * 10) + (views * 0.5)
            recency = published ? (Time.current - published) / 3600 : 1000
            adjusted = score / recency
            [id, adjusted]
          end
          .sort_by { |_, score| -score }
          .first(500)
          .to_h

          ranked_ids = engagement_scores.keys
          return [ [], nil ] if ranked_ids.empty?

          query = ::SocialVideo.feedable.where(id: ranked_ids)
          videos, next_cursor_val = apply_cursor(query, cursor, limit)

          [videos, next_cursor_val]
        end

        def encode_cursor(video)
          Base64.urlsafe_encode64({
            published_at: video.published_at&.iso8601,
            created_at: video.created_at.iso8601,
            id: video.id
          }.to_json)
        end

        def decode_cursor(cursor)
          JSON.parse(Base64.urlsafe_decode64(cursor))
        rescue StandardError
          nil
        end

        def apply_cursor(query, cursor, limit)
          base_query = query.order(published_at: :desc, created_at: :desc)

          decoded = cursor.present? ? decode_cursor(cursor) : nil
          scoped = if decoded
            base_query.where(
              "published_at < :published_at OR (published_at = :published_at AND created_at < :created_at) OR (published_at = :published_at AND created_at = :created_at AND id < :id)",
              published_at: decoded["published_at"],
              created_at: decoded["created_at"],
              id: decoded["id"]
            )
          else
            base_query
          end

          results = scoped.limit(limit + 1).to_a
          has_more = results.length > limit
          trimmed = has_more ? results.first(limit) : results
          next_cursor_val = has_more ? encode_cursor(trimmed.last) : nil

          [trimmed, next_cursor_val]
        end
      end
    end
  end
end
