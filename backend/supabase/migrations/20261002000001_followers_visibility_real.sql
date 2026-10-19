-- "Followers" visibility was a real, selectable option in the app's own
-- publish flow (RouteReviewPublishView.visButton) that silently did
-- nothing: routes.author_id = auth.uid() OR (status='published' AND
-- visibility='public') were the only two SELECT-permitting conditions on
-- `routes` — nobody but the author could ever read a route set to
-- "Followers," which also meant its comments and photos (gated by "follow
-- their route's visibility") were unreadable by followers too. A flagged-
-- correct field read: either make it real or remove the option; this makes
-- it real.

-- Routes: add the missing third branch — a signed-in follower of the
-- author can read a published, followers-visibility route. Additive
-- (permissive) policy alongside the existing "readable by anyone" one,
-- not a replacement.
create policy "Followers can read followers-visibility routes"
on routes for select
to authenticated
using (
  status = 'published'
  and visibility = 'followers'
  and exists (
    select 1 from follows
    where follows.followee_id = routes.author_id
      and follows.follower_id = auth.uid()
  )
);

-- Comments and photos: their own policies embed the same "what visibility
-- makes the parent route readable" logic as routes did, duplicated. Rather
-- than duplicate the followers check a third time, extract it into one
-- reusable function (`follows` has a "publicly readable" policy already,
-- so this needs no elevated privilege) and have both policies call it.
create or replace function route_readable_by_viewer(p_author_id uuid, p_status route_status, p_visibility route_visibility)
returns boolean
language sql
stable
as $$
  select
    p_author_id = auth.uid()
    or (
      p_status = 'published'
      and (
        p_visibility = 'public'
        or (
          p_visibility = 'followers'
          and exists (
            select 1 from follows
            where follows.followee_id = p_author_id
              and follows.follower_id = auth.uid()
          )
        )
      )
    );
$$;

drop policy if exists "Comments follow their route's visibility" on route_comments;
create policy "Comments follow their route's visibility"
on route_comments for select
using (
  not hidden
  and exists (
    select 1 from routes r
    where r.id = route_comments.route_id
      and route_readable_by_viewer(r.author_id, r.status, r.visibility)
  )
);

drop policy if exists "Photos follow their route's visibility" on route_photos;
create policy "Photos follow their route's visibility"
on route_photos for select
using (
  not hidden
  and exists (
    select 1 from routes r
    where r.id = route_photos.route_id
      and route_readable_by_viewer(r.author_id, r.status, r.visibility)
  )
);
