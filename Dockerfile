# Development image for FeedHub.
#
# This image is intentionally a *development* image: it carries the build
# toolchain and installs every Bundler group. Production packaging is out of
# scope for this repository.
FROM ruby:3.3.6-slim

# build-essential + pkg-config: compile native gem extensions
# libpq-dev:                    headers required by the `pg` gem
# git:                          Bundler needs it for git-sourced gems
# curl:                         handy for container-side health probing
RUN apt-get update -qq \
    && apt-get install --no-install-recommends -y \
         build-essential \
         libpq-dev \
         git \
         curl \
         pkg-config \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=C.UTF-8 \
    TZ=UTC \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3

WORKDIR /app

# Copy the dependency manifests on their own first. Docker then reuses the
# cached `bundle install` layer for every build in which the Gemfile and the
# lockfile are unchanged, instead of reinstalling gems on every source edit.
#
# Gems land in the image default prefix (/usr/local/bundle). Nothing is mounted
# over that path in compose.yaml -- an empty named volume there would shadow the
# gems baked into the image.
COPY Gemfile Gemfile.lock ./
RUN bundle install

# Copy the rest of the application. In development compose.yaml bind mounts the
# project over /app, so this copy mainly serves builds run without the mount.
COPY . .

EXPOSE 3000

# Remove a stale PID file first: the bind mounted tmp/ survives container
# restarts, and Puma refuses to boot when tmp/pids/server.pid is left behind.
#
# `bundle exec rails` rather than `bin/rails` on purpose: the gem executable
# re-execs the application binstub through the Ruby interpreter, so booting does
# not depend on the executable bit surviving a bind mount from a Windows host.
CMD ["sh", "-c", "rm -f tmp/pids/server.pid && exec bundle exec rails server -b 0.0.0.0 -p 3000"]
