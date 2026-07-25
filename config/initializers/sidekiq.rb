# Both the server (the `worker` container) and the client (the `web` container,
# which enqueues jobs) need to reach the same Redis instance.
#
# Inside Docker Compose the hostname is the service name `redis`, never
# `localhost`. The fallback mirrors .env.example so the app still boots when the
# variable is missing.
redis_config = { url: ENV.fetch("REDIS_URL", "redis://redis:6379/0") }

Sidekiq.configure_server do |config|
  config.redis = redis_config
end

Sidekiq.configure_client do |config|
  config.redis = redis_config
end
