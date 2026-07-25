require "webmock/rspec"

# Nothing in the suite is allowed to reach the network. A spec that forgets to
# stub a request fails loudly with the URL it tried to call, instead of quietly
# depending on somebody else's uptime -- and the feed fetching specs would
# otherwise hammer real publishers on every run.
#
# allow_localhost is false as well: there is no service worth talking to on the
# loopback interface during a test run, and permitting it only hides mistakes.
WebMock.disable_net_connect!(allow_localhost: false)
