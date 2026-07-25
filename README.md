# FeedHub

A small Rails application that collects RSS/Atom feeds on a schedule and supports bulk CSV import/export.

> This README is a skeleton. The full bilingual version (English + 日本語) is written in phase 7.

## Getting Started

```bash
cp .env.example .env
docker compose up
docker compose exec web bin/rails db:setup
```

The application is then available at <http://localhost:3000>.
