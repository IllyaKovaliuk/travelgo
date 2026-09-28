-- Real emergency contacts — the Settings row existed as a dead stub
-- (no value, no tap target) and SOSView's "contacts row" showed a
-- hardcoded fake "Giorgi K. and 1 more" placeholder. Entirely private,
-- same single owner-only policy `visits` already uses.
create table public.emergency_contacts (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles(id) on delete cascade,
    name text not null,
    phone text,
    email text,
    created_at timestamptz not null default now(),
    constraint emergency_contacts_has_reach_method check (phone is not null or email is not null)
);

create index emergency_contacts_user_id_idx on public.emergency_contacts(user_id);

alter table public.emergency_contacts enable row level security;

create policy "Users manage their own emergency contacts"
    on public.emergency_contacts for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);
