-- Crews and expeditions carry user-written text (names, notes), so they have
-- to be reportable (App Review Guideline 1.2). Own file because Postgres won't
-- let a freshly-added enum value be used in the transaction that added it.
alter type report_target add value if not exists 'crew';
alter type report_target add value if not exists 'expedition';
