# Opens and closes a bullet "request" around every example.
#
# bullet detects N+1 queries by watching the associations loaded between
# start_request and end_request. Its Rack middleware does that for a real HTTP
# request, but the collector is process-global: without an explicit reset here,
# associations loaded while an example builds its fixtures leak into the next
# example's window and produce a warning that has nothing to do with the page
# under test.
#
# Everything is guarded, so the suite still runs unchanged if the gem is absent
# or switched off. A spec run should never fail because a development tool is
# missing.
RSpec.configure do |config|
  bullet_active = -> { defined?(Bullet) && Bullet.enable? }

  config.before(:each) do
    Bullet.start_request if bullet_active.call
  end

  config.after(:each) do
    next unless bullet_active.call

    begin
      # Bullet.raise is set in the test environment, so this is what turns a
      # detected N+1 into a failing example: it raises
      # Bullet::Notification::UnoptimizedQueryError naming the model and the
      # association that should have been preloaded.
      Bullet.perform_out_of_channel_notifications if Bullet.notification?
    ensure
      Bullet.end_request
    end
  end
end
