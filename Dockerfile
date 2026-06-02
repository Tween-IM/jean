  # syntax=docker/dockerfile:1
 # check=skip=SecretsUsedInArgOrEnv

# This Dockerfile is designed for development and production. Use with Kamal or build'n'run by hand:
# docker build -t tmcp_server .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name tmcp_server tmcp_server

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.4.4

# Build arguments for deployment
ARG SOURCE_COMMIT
ARG COOLIFY_URL
ARG COOLIFY_FQDN
ARG MATRIX_HS_TOKEN
ARG COOLIFY_BUILD_SECRETS_HASH
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /app

# Install base packages
# ffmpeg + ffprobe are required at runtime by SocialPostProcessingJob
# (HlsTranscodeService shells out to both). libvips is for ActiveStorage
# image variants. We pin the ffmpeg package version to make the build
# reproducible — bump deliberately when you need newer codecs.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
        curl \
        libjemalloc2 \
        libvips \
        postgresql-client \
        libyaml-dev \
        pkg-config \
        ffmpeg \
    && \
    ffmpeg -version >/dev/null && \
    ffprobe -version >/dev/null && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set environment (will be overridden for dev in compose)
ENV RAILS_ENV="development" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT=""

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
# ffmpeg in the build stage so any gem (e.g. paperclip-era adapters) that
# needs to link against libav* can; the runtime image already has ffmpeg
# from the base stage.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
        build-essential \
        git \
        libpq-dev \
        pkg-config \
        libyaml-dev \
        ffmpeg \
    && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY Gemfile Gemfile.lock ./
RUN bundle install --with development test && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/

# Build Tailwind CSS for production admin dashboard
RUN SECRET_KEY_BASE=dummy RAILS_ENV=production bundle exec rails tailwindcss:build

# Precompiling assets for development (no assets needed)
# RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile




# Final stage for app image
FROM base

# Copy built artifacts: gems, application
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /app /app

# Run as root for development (bind mounts preserve host ownership)

# Entrypoint prepares the database.
ENTRYPOINT ["/app/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]
