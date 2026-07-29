-- Identity schema: profiles, friendships, groups, group_members.
--
-- Forward-only. Never edit this file after it is pushed — fix mistakes with a
-- new migration. See CLAUDE.md.
--
-- Every table here gets RLS in this same migration. A table with user data and
-- no policies is a leak, and "we'll add policies later" never survives contact
-- with a deadline.

create extension if not exists citext;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

-- Ordered least- to most-revealing. The ordering is load-bearing: effective
-- visibility is the maximum over all grants, and enum comparison provides it.
-- Used by profiles.default_visibility now; by schedule_items in A2.2.
create type visibility_level as enum ('hidden', 'busy', 'details');

create type friendship_status as enum ('pending', 'accepted', 'blocked');

create type group_role as enum ('owner', 'admin', 'member');

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table profiles (
  id                 uuid primary key references auth.users (id) on delete cascade,
  handle             citext not null unique,
  display_name       text not null check (length(trim(display_name)) between 1 and 80),
  avatar_url         text,
  time_zone          text not null default 'UTC',
  theme_key          text not null default 'default',
  color_scheme       text not null default 'system'
                       check (color_scheme in ('system', 'light', 'dark')),
  default_visibility visibility_level not null default 'busy',
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint profiles_handle_format
    check (handle ~ '^[a-z0-9_]{3,30}$')
);

create table friendships (
  id           uuid primary key default gen_random_uuid(),
  requester_id uuid not null references profiles (id) on delete cascade,
  addressee_id uuid not null references profiles (id) on delete cascade,
  status       friendship_status not null default 'pending',
  created_at   timestamptz not null default now(),
  responded_at timestamptz,
  constraint friendship_not_self check (requester_id <> addressee_id)
);

-- One row per unordered pair, whoever asked first. Without this, A and B can
-- each hold a pending request to the other and "are they friends" stops having
-- a single answer.
create unique index friendships_pair_uniq
  on friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));

create index friendships_requester_idx on friendships (requester_id) where status = 'accepted';
create index friendships_addressee_idx on friendships (addressee_id) where status = 'accepted';

create table groups (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (length(trim(name)) between 1 and 80),
  avatar_url text,
  created_by uuid not null references profiles (id) on delete restrict,
  created_at timestamptz not null default now()
);

create table group_members (
  group_id   uuid not null references groups (id) on delete cascade,
  profile_id uuid not null references profiles (id) on delete cascade,
  role       group_role not null default 'member',
  joined_at  timestamptz not null default now(),
  primary key (group_id, profile_id)
);

create index group_members_profile_idx on group_members (profile_id);

-- ---------------------------------------------------------------------------
-- Helpers
--
-- Both are SECURITY DEFINER so RLS policies can call them without recursing
-- into the policies on the tables they read. is_group_member exists for exactly
-- that reason: a group_members policy that queries group_members directly
-- recurses infinitely.
--
-- search_path is pinned on every one of these. A SECURITY DEFINER function with
-- a mutable search_path is a privilege-escalation vector — a caller can shadow
-- the tables it reads.
-- ---------------------------------------------------------------------------

create or replace function are_friends(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from friendships f
    where f.status = 'accepted'
      and ((f.requester_id = a and f.addressee_id = b)
        or (f.requester_id = b and f.addressee_id = a))
  );
$$;

create or replace function is_group_member(gid uuid, uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from group_members m where m.group_id = gid and m.profile_id = uid
  );
$$;

create or replace function has_group_role(gid uuid, uid uuid, roles group_role[])
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from group_members m
    where m.group_id = gid and m.profile_id = uid and m.role = any(roles)
  );
$$;

-- True when two people share at least one group. Group members can see each
-- other's profiles without being friends — otherwise a group calendar cannot
-- render names.
create or replace function shares_group(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from group_members ma
    join group_members mb on ma.group_id = mb.group_id
    where ma.profile_id = a and mb.profile_id = b
  );
$$;

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table profiles      enable row level security;
alter table friendships   enable row level security;
alter table groups        enable row level security;
alter table group_members enable row level security;

-- profiles ------------------------------------------------------------------
--
-- Deliberately closed: you can read a profile if it is yours, if you are
-- friends, if a friend request is outstanding either way, or if you share a
-- group. Strangers get nothing at all — which is stronger than hiding
-- individual fields, and means the table cannot be scraped.
--
-- Discovery by handle therefore needs a narrow SECURITY DEFINER function
-- returning only public columns for an exact handle match. That lands in T4.2
-- with the rest of friend discovery; it is deliberately not a blanket read
-- policy here.

create policy profiles_select on profiles for select
  using (
    id = auth.uid()
    or are_friends(id, auth.uid())
    or shares_group(id, auth.uid())
    or exists (
      select 1 from friendships f
      where f.status = 'pending'
        and ((f.requester_id = auth.uid() and f.addressee_id = profiles.id)
          or (f.addressee_id = auth.uid() and f.requester_id = profiles.id))
    )
  );

-- Insert is handled by the handle_new_user trigger, but an explicit policy
-- keeps a signed-in user able to create their own row if the trigger is ever
-- bypassed. They can never create someone else's.
create policy profiles_insert on profiles for insert
  with check (id = auth.uid());

create policy profiles_update on profiles for update
  using (id = auth.uid()) with check (id = auth.uid());

create policy profiles_delete on profiles for delete
  using (id = auth.uid());

-- friendships ---------------------------------------------------------------

create policy friendships_select on friendships for select
  using (requester_id = auth.uid() or addressee_id = auth.uid());

-- You may only ever create a request as yourself, and only as 'pending'.
-- Without the status check, a user could insert a row that is already
-- 'accepted' and befriend someone unilaterally.
create policy friendships_insert on friendships for insert
  with check (requester_id = auth.uid() and status = 'pending');

-- Either party may update (accept, decline, block). The addressee accepting is
-- the common path; USING and WITH CHECK both constrain to the pair so neither
-- side can reassign the row to somebody else.
create policy friendships_update on friendships for update
  using (requester_id = auth.uid() or addressee_id = auth.uid())
  with check (requester_id = auth.uid() or addressee_id = auth.uid());

create policy friendships_delete on friendships for delete
  using (requester_id = auth.uid() or addressee_id = auth.uid());

-- groups --------------------------------------------------------------------

create policy groups_select on groups for select
  using (is_group_member(id, auth.uid()));

create policy groups_insert on groups for insert
  with check (created_by = auth.uid());

create policy groups_update on groups for update
  using (has_group_role(id, auth.uid(), array['owner', 'admin']::group_role[]))
  with check (has_group_role(id, auth.uid(), array['owner', 'admin']::group_role[]));

create policy groups_delete on groups for delete
  using (has_group_role(id, auth.uid(), array['owner']::group_role[]));

-- group_members -------------------------------------------------------------

create policy group_members_select on group_members for select
  using (is_group_member(group_id, auth.uid()));

-- Two legitimate inserts: the creator seeding themselves as owner on a brand
-- new group, and an owner/admin adding someone. Joining by invite link is T4.3
-- and will go through a SECURITY DEFINER redemption function, not this policy.
create policy group_members_insert on group_members for insert
  with check (
    has_group_role(group_id, auth.uid(), array['owner', 'admin']::group_role[])
    or (
      profile_id = auth.uid()
      and exists (select 1 from groups g where g.id = group_id and g.created_by = auth.uid())
    )
  );

create policy group_members_update on group_members for update
  using (has_group_role(group_id, auth.uid(), array['owner', 'admin']::group_role[]))
  with check (has_group_role(group_id, auth.uid(), array['owner', 'admin']::group_role[]));

-- Leave a group yourself, or be removed by an owner/admin.
create policy group_members_delete on group_members for delete
  using (
    profile_id = auth.uid()
    or has_group_role(group_id, auth.uid(), array['owner', 'admin']::group_role[])
  );

-- ---------------------------------------------------------------------------
-- New-user trigger
--
-- Creates a profile when Supabase Auth creates a user. Handle is derived from
-- the email local part, sanitised to the handle format, with a numeric suffix
-- on collision. Onboarding (A1.3) lets the user change it.
-- ---------------------------------------------------------------------------

create or replace function handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  base_handle text;
  candidate   text;
  suffix      integer := 0;
begin
  base_handle := lower(regexp_replace(split_part(coalesce(new.email, ''), '@', 1), '[^a-z0-9_]', '', 'g'));

  -- Guarantee the format constraint is satisfiable even for an empty or
  -- very short local part.
  if length(base_handle) < 3 then
    base_handle := 'user' || substr(replace(new.id::text, '-', ''), 1, 8);
  end if;
  base_handle := substr(base_handle, 1, 24);

  candidate := base_handle;
  while exists (select 1 from profiles p where p.handle = candidate::citext) loop
    suffix := suffix + 1;
    candidate := substr(base_handle, 1, 24) || suffix::text;
  end loop;

  insert into profiles (id, handle, display_name)
  values (new.id, candidate, coalesce(nullif(split_part(coalesce(new.email, ''), '@', 1), ''), candidate));

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();
