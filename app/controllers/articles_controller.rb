# The harvested articles, as a page or as a downloadable CSV.
class ArticlesController < ApplicationController
  CSV_CONTENT_TYPE = "text/csv; charset=utf-8".freeze

  # Rows per page. Small enough that the page renders instantly on a table that
  # grows without bound, large enough that paging through a day's harvest is not
  # a chore.
  PER_PAGE = 25

  # The export is a format of the index rather than a separate action or a
  # separate controller. It answers the same question about the same collection,
  # so it should be built from the same code: when the index grows a filter,
  # "export what I am looking at" comes for free instead of becoming a second
  # implementation that drifts out of step with the first.
  def index
    respond_to do |format|
      format.html do
        # The feeds that populate the filter select. Loaded only on the HTML
        # branch -- the CSV format has no select box and must not pay for one.
        @feeds = Feed.order(:title)

        # includes(:feed) is not a later optimisation. The table prints the feed
        # title on every row, so without it the page issues one query per
        # article and the cost grows with the page size; bullet raises on that
        # in the test environment rather than letting it reach production.
        #
        # Pagination is applied after the ordering so the page boundaries follow
        # published_at rather than whatever order the database felt like.
        @articles = articles_scope.includes(:feed).recent.page(params[:page]).per(PER_PAGE)
      end

      # Deliberately not paginated: an export that stopped at 25 rows would be a
      # trap. The exporter batches its own reads instead.
      format.csv { send_data(csv_body, csv_options) }
    end
  end

  private

  # The collection both formats answer about. It is deliberately unordered:
  # ordering belongs to the HTML branch, because the exporter batches with
  # find_each, which imposes primary-key order and discards any other.
  #
  # The feed filter is applied here rather than in the HTML branch so the CSV
  # export inherits it for free: "export what I am looking at" stays true.
  def articles_scope
    scope = Article.all
    scope = scope.where(feed_id: params[:feed_id]) if params[:feed_id].present?
    scope
  end

  # send_data rather than ActionController::Live.
  #
  # Live streams, but it does so by running *every* action of this controller on
  # its own thread with its own database connection, and by committing the
  # response headers before the first row has been read -- after which a failure
  # can no longer become an error page, only a truncated file the operator has
  # no reason to distrust. That is a large, permanent cost imposed on a whole
  # controller for the benefit of one format.
  #
  # The exporter still yields one line at a time and still walks the table in
  # batches, so the query side is bounded either way; what send_data adds is one
  # response body in memory, roughly the size of the file being downloaded. At
  # this application's volume that is small, and the simplicity is worth more.
  # The line to watch is the export outgrowing what a single request may
  # reasonably hold -- and at that point the answer is not Live either, it is a
  # background job writing the file and mailing the operator a link to it.
  def csv_body
    ArticleCsvExporter.new(articles_scope).call.to_a.join
  end

  def csv_options
    # send_data's :type is what actually sets the header; it is named here so
    # the download is read as CSV rather than offered as an unknown binary.
    response.headers["Content-Type"] = CSV_CONTENT_TYPE

    {
      type: CSV_CONTENT_TYPE,
      filename: "articles-#{Time.current.strftime('%Y%m%d%H%M%S')}.csv",
      disposition: "attachment"
    }
  end
end
