-- Seed data — mirrors Sources/Models/Route.mock and RouteDetailInfo exactly,
-- so the app renders identically whether it's reading the SwiftUI mocks or
-- this database.

-- Minimal auth.users rows so profiles can reference them (local dev only —
-- these accounts have no usable password; sign in with real sign-up instead).
insert into auth.users (id, instance_id, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, aud, role)
values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'tamar@nomadterminal.io', crypt('placeholder', gen_salt('bf')), now(), '{}', '{"username":"tamarondirt","display_name":"Tamar Meladze"}', 'authenticated', 'authenticated'),
  ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000', 'luka@nomadterminal.io', crypt('placeholder', gen_salt('bf')), now(), '{}', '{"username":"lkpaddles","display_name":"Luka Kranjc"}', 'authenticated', 'authenticated'),
  ('33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000000', 'ainara@nomadterminal.io', crypt('placeholder', gen_salt('bf')), now(), '{}', '{"username":"ainara.r","display_name":"Ainara Ruiz"}', 'authenticated', 'authenticated'),
  ('44444444-4444-4444-4444-444444444444', '00000000-0000-0000-0000-000000000000', 'sana@nomadterminal.io', crypt('placeholder', gen_salt('bf')), now(), '{}', '{"username":"sanadrives","display_name":"Sana Kadyrova"}', 'authenticated', 'authenticated')
on conflict (id) do nothing;

update public.profiles set username = 'tamarondirt', display_name = 'Tamar Meladze', home_location = 'Mestia, Georgia', km_logged = 4870, routes_completed = 214 where id = '11111111-1111-1111-1111-111111111111';
update public.profiles set username = 'lkpaddles', display_name = 'Luka Kranjc', home_location = 'Bovec, Slovenia', km_logged = 1120, routes_completed = 61 where id = '22222222-2222-2222-2222-222222222222';
update public.profiles set username = 'ainara.r', display_name = 'Ainara Ruiz', home_location = 'Cangas de Onís, Spain', km_logged = 640, routes_completed = 39 where id = '33333333-3333-3333-3333-333333333333';
update public.profiles set username = 'sanadrives', display_name = 'Sana Kadyrova', home_location = 'Almaty, KZ', km_logged = 4218, routes_completed = 38 where id = '44444444-4444-4444-4444-444444444444';

-- ── Routes ──────────────────────────────────────────────────────────────
insert into public.routes (id, author_id, title, place, difficulty, transport, transport_label, secondary_badge_icon, secondary_badge_label, distance_km, coordinates, season, duration, ascent_m, high_point_m, elevation_profile, elevation_peak_label, quote, quote_author)
values (
  'aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
  'Zagar Pass' || chr(10) || 'at first light', 'SVANETI, GEORGIA', 'hard', 'overland', '4×4',
  'figure.hiking', 'FOOT 4KM', 62.4, 'SVANETI · 42.68°N 43.02°E', 'JUN – OCT', '2 DAYS', 1840, 2410,
  array[0.42,0.38,0.55,0.5,0.7,0.66,0.82,0.78,0.95,0.9,1.0,0.86,0.72,0.6], '2410 M',
  'Leave Mestia before four. The pass holds cloud until the sun clears the Ushba ridge, and once it does you get about forty minutes of the light everyone comes here for.',
  '— TAMAR MELADZE, LOGGED SEP 2025'
), (
  'aaaaaaaa-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222',
  'The Emerald' || chr(10) || 'Corridor', 'SOČA VALLEY, SLOVENIA', 'moderate', 'water', 'KAYAK',
  null, null, 18.9, 'SOČA VALLEY · 46.24°N 13.62°E', 'MAY – SEP', '1 DAY', 120, 480,
  array[0.5,0.48,0.6,0.55,0.5,0.62,0.58,0.44,0.4,0.5,0.46,0.38], '480 M',
  'Put in above the gorge at first light — the glacial melt keeps flow predictable until early afternoon.',
  '— LUKA KRANJC, LOGGED JUL 2025'
), (
  'aaaaaaaa-0000-0000-0000-000000000003', '33333333-3333-3333-3333-333333333333',
  'Naranjo' || chr(10) || 'north face', 'PICOS DE EUROPA, SPAIN', 'hard', 'climb', 'CLIMB · 6b',
  null, null, 0.54, 'PICOS DE EUROPA · 43.19°N 4.85°W', 'JUN – SEP', '1–2 DAYS', 540, 2519,
  array[0.2,0.3,0.35,0.5,0.48,0.62,0.7,0.66,0.82,0.9,0.95,1.0], '2519 M',
  'The crux pitch faces north and stays wet after rain for two full days — check the topo forum before you commit.',
  '— AINARA RUIZ, LOGGED AUG 2025'
);

-- ── Segments ────────────────────────────────────────────────────────────
insert into public.route_segments (route_id, icon, name, distance_km, tint, sort_order) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'figure.hiking', 'Mestia → Zhabeshi trail', 14.2, '#5FA777', 0),
  ('aaaaaaaa-0000-0000-0000-000000000001', 'car.side', 'Ushguli track, 4×4 only', 31.6, '#E8743B', 1),
  ('aaaaaaaa-0000-0000-0000-000000000001', 'water.waves', 'Enguri ford crossing', 0.4, '#3E92CC', 2),
  ('aaaaaaaa-0000-0000-0000-000000000001', 'mountain.2.fill', 'Zagar scramble to col', 16.2, '#7A5FBF', 3),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'water.waves', 'Put-in to gorge narrows', 8.4, '#3E92CC', 0),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'water.waves', 'Gorge run to take-out', 10.5, '#3E92CC', 1),
  ('aaaaaaaa-0000-0000-0000-000000000003', 'figure.hiking', 'Approach to base of wall', 3.1, '#5FA777', 0),
  ('aaaaaaaa-0000-0000-0000-000000000003', 'mountain.2.fill', 'North face, 12 pitches', 0.54, '#7A5FBF', 1);

-- ── Requirements ────────────────────────────────────────────────────────
insert into public.route_requirements (route_id, icon, title, subtitle, tint, sort_order) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'car.side', 'High-clearance 4×4, locked diff', 'NO SOFT-ROADERS PAST WP2', '#AE1800', 0),
  ('aaaaaaaa-0000-0000-0000-000000000001', 'drop.fill', '6 L water per person', 'LAST SPRING AT KM 21', '#3E92CC', 1),
  ('aaaaaaaa-0000-0000-0000-000000000001', 'cloud.rain.fill', 'Impassable after heavy rain', 'CHECK FORD AT WP3 · 48H RULE', '#B33A2B', 2),
  ('aaaaaaaa-0000-0000-0000-000000000001', 'doc.text.fill', 'Border-zone permit required', 'FREE · 3 DAYS LEAD TIME', '#5FA777', 3),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'figure.pool.swim', 'Grade III whitewater experience', 'NOT FOR FIRST-TIMERS', '#3E92CC', 0),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'thermometer.snowflake', 'Drysuit below 12°C', 'GLACIAL MELT, YEAR-ROUND COLD', '#7A5FBF', 1),
  ('aaaaaaaa-0000-0000-0000-000000000003', 'figure.climbing', 'Trad rack to 3in, double ropes', '12 PITCHES, NO FIXED GEAR', '#7A5FBF', 0),
  ('aaaaaaaa-0000-0000-0000-000000000003', 'tent.fill', 'Bivy gear for the col', 'MOST PARTIES SPLIT OVER 2 DAYS', '#E0A458', 1);

-- ── Badges ──────────────────────────────────────────────────────────────
insert into public.badges (key, title, subtitle, icon, color_start, color_end) values
  ('diff_locker', 'Diff Locker', '10 TRACKS', 'car.side', '#F19A6B', '#C2551F'),
  ('cold_water', 'Cold Water', 'GRADE III', 'water.waves', '#6FB4DD', '#2A6E9B'),
  ('vertical_mile', 'Vertical Mile', '1609 M', 'mountain.2.fill', '#9C86D8', '#5B41A0'),
  ('hundred_club', 'Hundred Club', '100 KM FOOT', 'figure.hiking', '#8FCBA3', '#3D7A54'),
  ('true_north', 'True North', '50 H OFFLINE', 'location.north.circle.fill', '#F0C98A', '#A8721F'),
  ('night_ford', 'Night Ford', 'LOCKED', 'lock.fill', '#605D5D', '#444141')
on conflict (key) do nothing;

insert into public.user_badges (user_id, badge_id)
select '44444444-4444-4444-4444-444444444444', id from public.badges where key <> 'night_ford';

-- ── Likes / saves so the feed counters aren't zero ─────────────────────
insert into public.route_saves (route_id, user_id, downloaded_offline)
values ('aaaaaaaa-0000-0000-0000-000000000001', '44444444-4444-4444-4444-444444444444', true);
