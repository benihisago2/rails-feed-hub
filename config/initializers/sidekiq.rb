# Both the server (the `worker` container) and the client (the `web` container,
# which enqueues jobs) need to reach the same Redis instance.
#
# Inside Docker Compose the hostname is the service name `redis`, never
# `localhost`. The fallback mirrors .env.example so the app still boots when the
# variable is missing.
redis_config = { url: ENV.fetch("REDIS_URL", "redis://redis:6379/0") }

Sidekiq.configure_server do |config|
  config.redis = redis_config

  # The recurring schedule belongs to the server process alone. The web
  # container enqueues jobs but must not register cron entries, and neither the
  # test environment nor `rails console` ever reaches this block -- so booting
  # without Redis, or without sidekiq-cron loaded, stays possible.
  config.on(:startup) do
    schedule_file = Rails.root.join("config/sidekiq_cron.yml")

    if defined?(Sidekiq::Cron::Job) && schedule_file.exist?
      Sidekiq::Cron::Job.load_from_hash!(YAML.load_file(schedule_file))
    end
  end
end

Sidekiq.configure_client do |config|
  config.redis = redis_config
end
