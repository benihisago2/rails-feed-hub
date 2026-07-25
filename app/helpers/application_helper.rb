module ApplicationHelper
  # One spelling of a timestamp for the whole application.
  #
  # An explicit format string rather than a localised one: the only reader is an
  # operator comparing "when did this feed last run" against a log line, and a
  # sortable, unambiguous stamp serves that better than a locale-dependent one.
  TIMESTAMP_FORMAT = "%Y-%m-%d %H:%M".freeze

  # placeholder is what to print when there is no time yet -- a feed that has
  # never been fetched, an article whose publisher gave no date. Rendering an
  # empty cell would leave the operator guessing whether the value is missing or
  # the page is broken.
  def timestamp(time, placeholder: "-")
    return placeholder if time.blank?

    time.strftime(TIMESTAMP_FORMAT)
  end
end
