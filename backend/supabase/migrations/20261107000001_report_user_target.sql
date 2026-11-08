-- Adds 'user' as a valid content_reports.target_type so a profile can be
-- reported from AuthorProfileView (App Review Guideline 1.2 — users need a
-- way to flag objectionable *users*, not only routes/comments/photos).
-- Own file because Postgres won't let a freshly-added enum value be used in
-- the same transaction that added it. No auto-hide trigger branch on
-- purpose: a profile isn't hidden by report count; user reports are
-- reviewed by an admin (they land in content_reports like every other
-- report, and admins can ban via the existing admin_set_banned RPC).
alter type report_target add value if not exists 'user';
