# FeedHub

Register RSS/Atom feeds, fetch them on a schedule, store the articles, and move them in and out as CSV.

[![CI](https://github.com/benihisago2/rails-feed-hub/actions/workflows/ci.yml/badge.svg)](https://github.com/benihisago2/rails-feed-hub/actions/workflows/ci.yml)

## Why this repository exists

This is a portfolio repository. It is deliberately small, because the point is not how much code it contains. The value is in how the work was done: the [merged pull requests](https://github.com/benihisago2/rails-feed-hub/pulls?q=is%3Apr+is%3Amerged) show the Issue → PR → review → merge history, and [`docs/adr/`](docs/adr/) records the design decisions and their trade-offs. Read those first — they are the part worth reading.

## Features

- Register RSS and Atom feeds through a small web UI.
- Fetch every active feed once an hour, one background job per feed.
- Deduplicate articles at the database level with a unique index on `(feed_id, guid)`.
- Import feeds in bulk from CSV, with per-row error reporting: good rows are saved, bad rows are recorded with their line number, already-registered URLs are skipped rather than reported as errors.
- Export articles as CSV from the same collection the index shows.
- A minimal admin UI for feeds, articles, and import jobs.

## Tech Stack

| Area | Choice |
|---|---|
| Language | Ruby 3.3.6 |
| Framework | Rails 8.0.5 |
| Database | PostgreSQL 16 |
| Background jobs | Sidekiq 7 + sidekiq-cron, on Redis 7 |
| Container | Docker Compose |
| CI | GitHub Actions |
| Tests | RSpec, FactoryBot, WebMock, SimpleCov |

## Getting Started

There is no Ruby toolchain on the host; everything runs in containers.

```bash
cp .env.example .env
docker compose up -d
docker compose exec web bin/rails db:prepare
```

Then open:

- <http://localhost:3000/feeds> — registered feeds (also the root path)
- <http://localhost:3000/articles> — harvested articles (`/articles.csv` exports the same list)
- <http://localhost:3000/import_jobs> — CSV import runs and their results
- <http://localhost:3000/sidekiq> — Sidekiq dashboard (development only)

## Architecture

Feeds are fetched by a chain of background jobs. The schedule triggers one parent job; the parent enqueues one job per feed; each feed is fetched and stored on its own.

```
sidekiq-cron (hourly)
        │
        ▼
ScheduleFeedFetchesJob        enqueues one job per active feed
        │
        ├──▶ FetchFeedJob(feed_id)   ─▶ FeedFetcher ─▶ Article.upsert_all
        ├──▶ FetchFeedJob(feed_id)   ─▶ FeedFetcher ─▶ Article.upsert_all
        └──▶ FetchFeedJob(feed_id)   ─▶ FeedFetcher ─▶ Article.upsert_all
```

One job per feed means a single unreachable host fails and retries on its own, without holding up or re-running the feeds that were fine. Storage uses `upsert_all` against the unique index, so two workers fetching the same feed cannot create duplicate rows.

The reasoning behind each decision, including the options that were rejected, is in the ADRs:

- [ADR-0001: why Sidekiq](docs/adr/0001-why-sidekiq.md) — the background job backend, and why jobs are scoped per feed.
- [ADR-0002: article deduplication](docs/adr/0002-article-deduplication.md) — the database constraint plus `upsert_all`.
- [ADR-0003: CSV import partial failure](docs/adr/0003-csv-import-partial-failure.md) — row-level errors instead of an all-or-nothing rollback.
- [ADR-0004: testing external HTTP](docs/adr/0004-testing-external-http.md) — stubbing the network in tests.

## Testing

Run the suite in the container:

```bash
docker compose exec web bundle exec rspec
```

SimpleCov enforces a floor of 80% line coverage; the suite is currently at about 99%. All external HTTP is stubbed with WebMock, so the tests never reach the network. The error paths — timeouts, 404s, and malformed XML — are covered as explicit cases rather than left to chance.

## Out of Scope

These were decided out of v1 to keep the scope closed, not left out for lack of time. Each is tracked as an issue:

- **Authentication** — the app runs as a single-operator tool for now.
- **Full-text search** — the article list is paginated, which is enough at this volume.
- **A tag-editing UI** — the tag model exists, but editing tags from the browser is not built.
- **OPML import** — bulk registration is CSV only.

## 日本語での補足

FeedHub は、RSS/Atom フィードを登録して定期的に取得し、記事を蓄積したうえで CSV による一括入出力を行う小さな Rails アプリケーションです。

このリポジトリは、作れるものの大きさではなく、開発の進め方そのものを見ていただくために用意しました。ですので、アプリの規模はあえて小さく抑えています。見どころは Issue から Pull Request、レビュー、マージへと至る履歴と、`docs/adr/` に残した設計判断の記録です。

設計の方針は一貫して「何を選ばなかったか、なぜか」を残すことに置いています。たとえばフィード取得のジョブはフィード単位に分けています。全件を一つのジョブでまとめて処理すると、一件の失敗が全体を巻き込み、リトライも全件やり直しになるためです。記事の重複排除はアプリ側の存在チェックに頼らず、`(feed_id, guid)` の複合ユニーク制約と `upsert_all` に任せています。並行して同じフィードを取得しても、重複が生まれない形にするためです。CSV インポートは全件ロールバックを避け、行ごとに成否を記録します。1000 行のうち 3 行が誤っていたときに、正しい 997 行まで捨ててしまうのは運用者にとって不親切だからです。

`docs/adr/` の設計判断記録はすべて日本語で書いています。日本語の仕様書や Issue をそのまま読んで実装に落とし込めますし、設計の意図を日本語の技術文書として書き起こすこともできます。翻訳を挟む必要はありません。
