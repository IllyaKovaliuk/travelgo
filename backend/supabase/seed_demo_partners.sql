-- DEMO data for testing the marketplace around Zhytomyr / Berdychiv.
-- Names are clearly fake ("DEMO ...") — replace with real, signed-up
-- partners before launch; never ship fake "verified" businesses.
insert into public.partners (id, name, category, latitude, longitude, is_verified) values
  ('a0000000-0000-0000-0000-000000000001', 'DEMO Quad Rental Zhytomyr', 'quad_rental', 50.2547, 28.6587, true),
  ('a0000000-0000-0000-0000-000000000002', 'DEMO Mountain Lodge', 'hotel', 50.2400, 28.7000, true),
  ('a0000000-0000-0000-0000-000000000003', 'DEMO Trail Gear Shop', 'equipment', 49.8960, 28.6000, true),
  ('a0000000-0000-0000-0000-000000000004', 'DEMO Trailhead Café', 'cafe', 50.2650, 28.6700, true)
on conflict (id) do nothing;

insert into public.rewards (id, partner_id, title, description, points_cost, stock, expires_at) values
  ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', '1 hour free quad rental', 'One hour on a quad with helmet included.', 400, 20, null),
  ('b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', '20% off a full-day rental', 'Applies to any full-day quad booking.', 250, 50, null),
  ('b0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000002', 'Free breakfast for two', 'Breakfast for two guests during your stay.', 300, 30, null),
  ('b0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000003', '15% off any gear', 'One-time discount on a single purchase.', 150, 100, null),
  ('b0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000004', 'Free coffee', 'One coffee of your choice.', 60, 200, null)
on conflict (id) do nothing;
