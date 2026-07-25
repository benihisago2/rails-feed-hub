class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Deliberately loose HTTP(S) check shared by Feed#url and Article#url.
  # Feed URLs come from users and from imported CSV files, so the point is to
  # reject obvious mistakes (a bare hostname, a mailto:, an ftp:) before a job
  # ever tries to fetch them -- not to re-implement RFC 3986. Schemes are
  # case insensitive, hence the /i.
  URL_FORMAT = %r{\Ahttps?://\S+\z}i
end
