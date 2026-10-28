-- Same, but ALSO deletes illya_kovaliuk's "Zhytomir-Berdychiv". Only use if you really want it gone.
begin;
delete from public.routes r
 using public.profiles p
 where p.id = r.author_id and p.username <> 'nomad_curated'
returning r.id, left(replace(r.title, E'\n', ' / '), 40) as title, p.username as author;
commit;
