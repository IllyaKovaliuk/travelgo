-- Re-cropped (3:2) covers for wide photos, so the already-submitted build renders cards correctly.
begin;
update public.routes set cover_image_url = 'https://smdnbjvelqsgjoubognc.supabase.co/storage/v1/object/public/route-covers/curated/odle-munkelweg-v2.jpg' where cover_image_url like '%/curated/odle-munkelweg.jpg';
update public.routes set cover_image_url = 'https://smdnbjvelqsgjoubognc.supabase.co/storage/v1/object/public/route-covers/curated/pip-ivan-shybene-v2.jpg' where cover_image_url like '%/curated/pip-ivan-shybene.jpg';
update public.routes set cover_image_url = 'https://smdnbjvelqsgjoubognc.supabase.co/storage/v1/object/public/route-covers/curated/ramon-crater-v2.jpg' where cover_image_url like '%/curated/ramon-crater.jpg';
commit;
select left(replace(title,E'\n',' / '),30) t, cover_image_url from public.routes where cover_image_url like '%-v2.jpg';
