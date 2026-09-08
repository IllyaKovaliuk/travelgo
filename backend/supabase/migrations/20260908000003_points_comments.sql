-- Comments never earned points, unlike likes/saves/follows — an
-- inconsistency, not an intentional exclusion. No symmetric "uncomment"
-- deduction since comments can't be un-posted in this app (no delete
-- flow exists yet), so there's no toggle-to-farm risk here.
create function public.handle_comment_posted()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare v_author uuid;
begin
  select author_id into v_author from public.routes where id = new.route_id;
  if v_author is not null and v_author <> new.author_id then
    perform public.award_points(v_author, 2, 'route_commented', new.route_id);
  end if;
  return new;
end;
$$;

create trigger on_comment_posted
  after insert on public.route_comments
  for each row execute procedure public.handle_comment_posted();
