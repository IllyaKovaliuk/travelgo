-- Adds 'photo' as a valid content_reports.target_type, ahead of the
-- route_photos table itself (next migration) — split into its own file
-- because Postgres won't let a freshly-added enum value be *used* (e.g. in
-- a CHECK, a function body, an INSERT) inside the same transaction that
-- added it. Each migration file runs as its own transaction, so by the
-- time the next migration references 'photo', this one has already
-- committed.
alter type report_target add value if not exists 'photo';
