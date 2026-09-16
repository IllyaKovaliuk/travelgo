-- The app is "everything, anywhere" now (see the 2026-09-07 scope reversal
-- — this app is going maximally broad, not staying in the outdoor niche),
-- and two whole transport types people actually log routes for were
-- missing from the fixed set: cycling and paragliding.
alter type public.transport_mode add value 'bike';
alter type public.transport_mode add value 'paraglide';
