---
date: 2026-06-02
topic: hls-video-transcoding
---

# HLS Video Transcoding

## Summary

Self-hosted ffmpeg pipeline transcodes uploaded feed videos into 2-rendition HLS (360p + 720p) on S3, played back via the existing video player on iOS/Android and via hls.js on web. The post stays live with the raw MP4; the transcode job swaps `playback_url` to the master manifest when it lands. Stories stay on the existing MP4 path but are capped at 1 minute, enforced in both the UI capture flow and the server.

---

## Problem Frame

Feed videos currently serve the raw uploaded MP4. On slow connections the timeline stalls, buffers, and re-buffers — a real product pain for users on cellular or weak Wi-Fi. Adaptive bitrate (HLS) is the standard solution: the player picks the right rendition for the current bandwidth, and segments seek quickly. Stories are a separate problem: they're ephemeral and short, so we cap them at 1 minute and let the client do the heavy lifting rather than spending transcode budget on something that disappears in 24 hours.

---

## Key Decisions

- **Self-hosted ffmpeg, not managed service** — Full control, no per-minute billing, fits the existing Rails/SolidQueue stack.
- **2 renditions: 360p + 720p** — Covers the common phone/tablet screen sizes. Larger ladders can come later.
- **S3 for HLS output** — CDN-friendly, scales across servers, decoupled from the Rails box.
- **Same SolidQueue for the transcode job** — Simpler ops; transcode spikes the worker CPU but is the only meaningful new CPU load.
- **Post publishes with raw MP4 first; HLS job overwrites `playback_url` later** — Already implemented today (publish-immediately fix). The post is visible in the feed immediately and the URL swaps to the HLS master as soon as the job completes.
- **Stories stay on MP4** — Ephemeral, short, mobile-only viewing. HLS would burn transcode budget for no UX gain.
- **1-minute cap on stories** — Enforced in the UI capture flow (camerawesome max recording time) and on the server (story validation).
- **hls.js on web only** — `video_player` already handles HLS natively on iOS/Android (ExoPlayer/AVPlayer). Web needs a JS player layer because the Dart package doesn't do HLS in the browser.

---

## Requirements

**Transcoding pipeline**
- R1. When a video post is created, the existing `SocialPostProcessingJob` transcodes the source MP4 to HLS with 2 renditions: 360p and 720p.
- R2. The transcode produces a master `m3u8` and per-rendition variant playlists + `.ts` segments, written to a configurable S3 bucket under a path keyed by `post_id`.
- R3. On successful transcode, the post's `playback_url` is updated to the master `m3u8` URL, the `variants` field is updated with the rendition metadata, and a `transcode_status` field reflects "ready" (or "failed" with a stored error).
- R4. Transcode failures (ffmpeg error, S3 write error) do not roll back the post. The post remains visible with the raw MP4 `playback_url`, and the job logs the failure with the post id for retry.
- R5. The transcode job is idempotent — re-running it for the same post overwrites the previous HLS output and updates `playback_url` consistently.

**Client playback**
- R6. iOS and Android playback: the existing `VideoPlayerWidget` (which uses the `video_player` package) plays HLS natively. No code change needed on these targets.
- R7. Web playback: the `VideoPlayerWidget` detects the web target and, when the URL ends in `.m3u8`, swaps to an `hls.js` player layer. On browsers that natively support HLS (Safari), the native path is used; on others, `hls.js` is attached.
- R8. The Flutter app pulls `hls.js` as a web-only asset (single JS file loaded at runtime; no native plugin needed).

**Stories**
- R9. Story video capture in the UI caps recording at 60 seconds. The user gets a visual countdown and the recording stops automatically at the limit.
- R10. Story video upload (file picker / gallery) rejects files longer than 60 seconds with a clear error.
- R11. The server validates `duration_seconds` on story create: if `> 60`, the create is rejected with a 422 and a clear message. The UI can also send `duration_seconds` for the validation; if absent, the server falls back to probing the source media.

**S3 configuration**
- R12. S3 credentials, bucket name, region, and public/CDN base URL are read from Rails credentials / environment, not hardcoded.
- R13. The HLS output path layout: `hls/{post_id}/master.m3u8`, `hls/{post_id}/360p/index.m3u8` + segments, `hls/{post_id}/720p/index.m3u8` + segments.

---

## Acceptance Examples

- AE1. **Covers R1, R3, R4.** Given a video post is created with a valid MP4, when the processing job runs successfully, then `playback_url` points to a master.m3u8 on S3, `variants` lists 360p and 720p, and the post remains visible in the feed.
- AE2. **Covers R4.** Given a video post is created with a valid MP4, when ffmpeg fails (e.g. corrupt source), then the post remains visible with the raw MP4 `playback_url` and a failure is logged with the post id.
- AE3. **Covers R7.** Given a viewer is on Flutter web and opens a video reel, when the post's `playback_url` ends in `.m3u8`, then the player attaches `hls.js` and the video plays with adaptive bitrate.
- AE4. **Covers R9.** Given the user is recording a story video, when 60 seconds of recording elapse, then recording stops automatically and the compose page appears with the captured video.
- AE5. **Covers R11.** Given a story create request with `duration_seconds: 75`, when the server processes it, then the response is HTTP 422 with a message indicating the 60-second cap.

---

## Success Criteria

- A user on a 3G connection can scroll the feed and watch videos without buffering stalls (rendition auto-switches to 360p).
- Existing video posts continue to work — the publish-immediately fix from today is preserved, so a missing or failed transcode never strands a post in `processing`.
- A user trying to upload a 75-second video as a story is blocked client-side and server-side, not silently truncated.
- A planning doc can be written from this requirements doc without inventing product behavior, scope, or success criteria.

---

## Scope Boundaries

- Migrating existing posts to HLS (only new posts get the HLS upgrade).
- Live streaming (RTMP, WebRTC, LL-HLS).
- DRM / encryption of streams.
- Captions, subtitles, multi-audio tracks.
- 3+ rendition ladders (240p, 480p, 1080p, etc.).
- Stories: HLS transcoding, longer-than-1-min stories, looping or boomerang effects.
- Chat event videos (Matrix attachments) — separate code path, out of scope.
- CDN configuration beyond pointing the player at a public S3 base URL (CloudFront / Cloudflare in front of S3 is a follow-up).
- Adaptive bitrate switching analytics.

---

## Key Decisions

(Already covered in the Key Decisions section above; included here for completeness.)

---

## Dependencies / Assumptions

- ffmpeg is installed on the worker host (verifiable on this machine at `/opt/homebrew/bin/ffmpeg`; production needs the same).
- An S3 bucket is available with credentials in Rails credentials / env. The implementation will assume standard `aws-sdk` Rails env vars.
- The Flutter web build pipeline can include a JS asset (hls.js) loaded at runtime.
- The `variants` column on `social_posts` is JSONB and can hold the rendition metadata (verify during planning).
- A migration may be needed to add `transcode_status` and `transcode_error` to `social_posts` (verify during planning).

---

## Outstanding Questions

### Resolve Before Planning
*(none)*

### Deferred to Planning

- **[Affects R1] [Technical]** Exact ffmpeg command and flags (codec, GOP, segment duration, CRF). The job implementation picks the right values.
- **[Affects R2] [Technical]** Concrete S3 upload mechanism (direct from ffmpeg, or ffmpeg to local then rails uploads to S3). Pick the lower-mem path during planning.
- **[Affects R7] [Technical]** How hls.js is packaged for Flutter web (asset bundle vs CDN). Pick whichever the existing web build pipeline supports.
- **[Affects R3, R13] [Needs research]** Whether `variants` already exists on `social_posts` and its current shape; whether `transcode_status` needs a migration.
