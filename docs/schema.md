# Data model

The proposed Postgres schema for Friends, targeting Supabase. This is a design document — none of it
is migrated yet. Treat it as the plan to implement and revise, not as a description of a live
database.

Read `CLAUDE.md` → "Domain model" and "Time rules" first; the vocabulary and invariants there are
assumed throughout.

## Design principles

1. **Availability is derived, never stored.** Schedule items mark time as taken. Free time is what's
   left over. There is no `is_available` column anywhere, and there never should be.
2. **Visibility is enforced in the database.** Row-level security decides who sees a row; a view
   decides which *columns* they see. The client is a rendering layer, not a gatekeeper.
3. **Recurrence is a rule plus exceptions.** A recurring item is one row with an `RRULE`. Individual
   deviations are exception rows. Occurrences are generated at read time and never persisted.
4. **Every timestamp is `timestamptz`, every item carries its zone.** Recurrence expands in local
   wall-clock time. See "Recurrence and time" below.

## Enums

```sql
-- Ordered least- to most-revealing. The ordering is load-bearing: effective
-- visibility is the maximum over all grants, and enum comparison provides it.
create type visibility_level as enum ('hidden', 'busy', 'details');

create type friendship_status as enum ('pending', 'accepted', 'blocked');

create type group_role as enum ('owner', 'admin', 'member');

create type import_status as enum ('uploaded', 'parsing', 'needs_review', 'confirmed', 'failed');
```

## Tables

### `profiles`

One row per account, keyed to Supabase Auth. `auth.users` is not queried directly by app code.

```sql
create table profiles (
  id                  uuid primary key references auth.users (id) on delete cascade,
  handle              citext not null unique,
  display_name        text   not null,
  avatar_url          text,
  time_zone           text   not null default 'UTC',   -- IANA, e.g. 'America/New_York'
  theme_key           text   not null default 'default',
  color_scheme        text   not null default 'system'
                        check (color_scheme in ('system', 'light', 'dark')),
  -- Applied to new schedule items unless the user overrides per item.
  default_visibility  visibility_level not null default 'busy',
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
```

### `friendships`

Mutual and acceptance-based. Stored as a single row per pair, with direction preserved so a pending
request knows who asked.

```sql
create table friendships (
  id            uuid primary key default gen_random_uuid(),
  requester_id  uuid not null references profiles (id) on delete cascade,
  addressee_id  uuid not null references profiles (id) on delete cascade,
  status        friendship_status not null default 'pending',
  created_at    timestamptz not null default now(),
  responded_at  timestamptz,
  constraint friendship_not_self check (requester_id <> addressee_id)
);

-- One row per unordered pair, regardless of who asked first.
create unique index friendships_pair_uniq
  on friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));

create index friendships_requester_idx on friendships (requester_id) where status = 'accepted';
create index friendships_addressee_idx on friendships (addressee_id) where status = 'accepted';
```

### `groups` and `group_members`

```sql
create table groups (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (length(trim(name)) between 1 and 80),
  avatar_url  text,
  created_by  uuid not null references profiles (id) on delete restrict,
  created_at  timestamptz not null default now()
);

create table group_members (
  group_id    uuid not null references groups (id) on delete cascade,
  profile_id  uuid not null references profiles (id) on delete cascade,
  role        group_role not null default 'member',
  joined_at   timestamptz not null default now(),
  primary key (group_id, profile_id)
);

create index group_members_profile_idx on group_members (profile_id);
```

### `schedule_items`

The core table. One row per block of time, recurring or not.

```sql
create table schedule_items (
  id                  uuid primary key default gen_random_uuid(),
  owner_id            uuid not null references profiles (id) on delete cascade,

  -- Detail fields. Only exposed to viewers at the 'details' level.
  title               text,
  location            text,
  notes               text,

  -- The first (or only) occurrence, as an instant.
  starts_at           timestamptz not null,
  ends_at             timestamptz not null,
  -- IANA zone the item was authored in. Recurrence expands against this.
  time_zone           text not null,
  is_all_day          boolean not null default false,

  -- RFC 5545 rule, without the 'RRULE:' prefix. Null for a one-off item.
  rrule               text,
  -- Convenience bound for range queries; must agree with any UNTIL/COUNT in rrule.
  recurrence_until    timestamptz,

  default_visibility  visibility_level not null default 'busy',
  color_key           text not null default 'default',
  -- 'manual' | 'photo_import' | future integrations.
  source              text not null default 'manual',
  import_id           uuid references schedule_imports (id) on delete set null,

  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  constraint schedule_item_time_order check (ends_at > starts_at),
  constraint schedule_item_recurrence_bound
    check (recurrence_until is null or rrule is not null)
);

create index schedule_items_owner_range_idx
  on schedule_items (owner_id, starts_at, ends_at);
-- Recurring items must be scanned separately; their starts_at is only the first instance.
create index schedule_items_recurring_idx
  on schedule_items (owner_id, starts_at) where rrule is not null;
```

**`starts_at` on a recurring item is the anchor, not a bound.** Any range query that filters on
`starts_at <= range_end and ends_at >= range_start` will silently drop recurring items whose anchor
predates the range. Recurring items are selected by `owner_id` plus
`recurrence_until is null or recurrence_until >= range_start`, then expanded.

### `schedule_item_exceptions`

One-off deviations from a recurring item: a cancelled instance, or one that moved or changed detail.
The parent's `rrule` is never edited to express these.

```sql
create table schedule_item_exceptions (
  id                 uuid primary key default gen_random_uuid(),
  item_id            uuid not null references schedule_items (id) on delete cascade,
  -- The start instant the rule would have generated. The join key.
  original_start_at  timestamptz not null,

  is_cancelled       boolean not null default false,
  -- Overrides. Null means "inherit from the parent item".
  starts_at          timestamptz,
  ends_at            timestamptz,
  title              text,
  location           text,
  notes              text,

  created_at         timestamptz not null default now(),

  unique (item_id, original_start_at),
  constraint exception_time_order
    check (starts_at is null or ends_at is null or ends_at > starts_at)
);
```

### `schedule_item_shares`

Grants that *raise* an item's visibility for a specific group or individual, above the item's
`default_visibility`. Grants never lower — a `hidden` share row is meaningless and is rejected.

```sql
create table schedule_item_shares (
  id          uuid primary key default gen_random_uuid(),
  item_id     uuid not null references schedule_items (id) on delete cascade,
  group_id    uuid references groups (id) on delete cascade,
  profile_id  uuid references profiles (id) on delete cascade,
  level       visibility_level not null check (level <> 'hidden'),
  created_at  timestamptz not null default now(),

  constraint share_exactly_one_target check (num_nonnulls(group_id, profile_id) = 1)
);

create unique index shares_group_uniq on schedule_item_shares (item_id, group_id)
  where group_id is not null;
create unique index shares_profile_uniq on schedule_item_shares (item_id, profile_id)
  where profile_id is not null;
```

### `messages`

Per-group chat. Delivered live over Supabase Realtime.

```sql
create table messages (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references groups (id) on delete cascade,
  sender_id   uuid not null references profiles (id) on delete cascade,
  body        text not null check (length(body) between 1 and 4000),
  created_at  timestamptz not null default now(),
  edited_at   timestamptz,
  deleted_at  timestamptz
);

create index messages_group_created_idx on messages (group_id, created_at desc);
```

### `schedule_imports`

Tracks a photographed schedule from upload through user confirmation. Parsed shifts land in
`parsed_shifts` and are **not** written to `schedule_items` until the user confirms them.

```sql
create table schedule_imports (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid not null references profiles (id) on delete cascade,
  storage_path   text not null,             -- Supabase Storage object key
  status         import_status not null default 'uploaded',
  parsed_shifts  jsonb,                     -- proposal, pending review
  error_message  text,
  created_at     timestamptz not null default now(),
  confirmed_at   timestamptz
);

create index schedule_imports_owner_idx on schedule_imports (owner_id, created_at desc);
```

## Visibility resolution

Three helpers. All are `security definer` so RLS policies can call them without recursing into the
policies on the tables they read.

```sql
create or replace function are_friends(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from friendships f
    where f.status = 'accepted'
      and (   (f.requester_id = a and f.addressee_id = b)
           or (f.requester_id = b and f.addressee_id = a))
  );
$$;

create or replace function is_group_member(gid uuid, uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from group_members m where m.group_id = gid and m.profile_id = uid
  );
$$;

-- The single source of truth for "what may this viewer see of this item?"
create or replace function effective_visibility(item uuid, viewer uuid)
returns visibility_level language sql stable security definer set search_path = public as $$
  with it as (
    select owner_id, default_visibility from schedule_items where id = item
  ),
  levels as (
    -- Owners always see everything.
    select 'details'::visibility_level as level from it where it.owner_id = viewer
    union all
    -- The item's default applies to accepted friends.
    select it.default_visibility from it where are_friends(it.owner_id, viewer)
    union all
    -- Direct grants to this viewer.
    select s.level from schedule_item_shares s
      where s.item_id = item and s.profile_id = viewer
    union all
    -- Grants to any group this viewer belongs to.
    select s.level from schedule_item_shares s
      where s.item_id = item
        and s.group_id is not null
        and is_group_member(s.group_id, viewer)
  )
  -- Highest grant wins. No aggregate max() exists for enums, hence order/limit.
  select coalesce(
    (select level from levels order by level desc limit 1),
    'hidden'::visibility_level
  );
$$;
```

**Reading the rules:**

- A stranger — no friendship, no group, no direct grant — gets `hidden`.
- A friend gets the item's `default_visibility`, which may itself be `hidden`.
- A share grant raises the level for its target and nobody else.
- The owner always gets `details`.

## Row-level security

Enabled on every table. Policies below are the read path; write policies follow the same shape and
restrict mutation to the owner (or, for groups, to `owner`/`admin` roles).

```sql
alter table profiles                 enable row level security;
alter table friendships              enable row level security;
alter table groups                   enable row level security;
alter table group_members            enable row level security;
alter table schedule_items           enable row level security;
alter table schedule_item_exceptions enable row level security;
alter table schedule_item_shares     enable row level security;
alter table messages                 enable row level security;
alter table schedule_imports         enable row level security;

-- Schedule items: visible when the viewer's effective level is above 'hidden'.
create policy schedule_items_select on schedule_items for select
  using (effective_visibility(id, auth.uid()) > 'hidden');

create policy schedule_items_write on schedule_items for all
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

-- Exceptions inherit the parent's visibility.
create policy exceptions_select on schedule_item_exceptions for select
  using (effective_visibility(item_id, auth.uid()) > 'hidden');

-- Only the item's owner ever sees the grant list.
create policy shares_owner_only on schedule_item_shares for all
  using (exists (
    select 1 from schedule_items i where i.id = item_id and i.owner_id = auth.uid()
  ));

-- Messages: members of the group only.
create policy messages_select on messages for select
  using (is_group_member(group_id, auth.uid()));

create policy messages_insert on messages for insert
  with check (sender_id = auth.uid() and is_group_member(group_id, auth.uid()));

-- Imports are strictly private to the uploader.
create policy imports_owner_only on schedule_imports for all
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
```

## Column redaction

RLS controls *rows*. A viewer at `busy` can select the row but must not receive `title`, `location`,
or `notes`. That's a column concern, so all client reads of schedule data go through this view rather
than the base table:

```sql
create or replace view visible_schedule_items
with (security_invoker = true) as
select
  i.id,
  i.owner_id,
  i.starts_at,
  i.ends_at,
  i.time_zone,
  i.is_all_day,
  i.rrule,
  i.recurrence_until,
  i.color_key,
  effective_visibility(i.id, auth.uid()) as level,
  case when effective_visibility(i.id, auth.uid()) = 'details'
       then i.title    end as title,
  case when effective_visibility(i.id, auth.uid()) = 'details'
       then i.location end as location,
  case when effective_visibility(i.id, auth.uid()) = 'details'
       then i.notes    end as notes
from schedule_items i;
```

`security_invoker = true` matters — without it the view runs as its owner and bypasses RLS on the
base table entirely.

**Client code selects from `visible_schedule_items`, never from `schedule_items`,** except when the
owner is editing their own item.

## Recurrence and time

Expansion, in order:

1. Select candidate items: non-recurring ones overlapping the range, plus recurring ones whose
   `recurrence_until` is null or at/after the range start.
2. For each recurring item, convert `starts_at` into `time_zone` to get the local anchor.
3. Expand the `RRULE` **in that local zone** and convert each generated start back to UTC. Expanding
   in UTC shifts every occurrence by an hour across a DST boundary — this is the bug to watch for.
4. Apply exceptions by `original_start_at`: drop cancelled instances, apply field overrides to the
   rest.
5. Clip to the requested range.

Duration is carried from the parent (`ends_at - starts_at`) unless an exception overrides it.

Expansion lives in `packages/schedule-core` (see `docs/schedule-core.md`), mirrored by a SQL/Edge
implementation for server-side availability. If the two ever disagree, that's a bug — the package's
golden fixtures are plain JSON specifically so both implementations can be validated against the same
cases.

The columns above map onto the package's `CalendarEvent` directly: `starts_at`/`ends_at` → `start`/`end`,
`time_zone` → `timeZone`, `rrule` + `recurrence_until` + the exceptions table → `recurrence`, and
`title`/`location`/`notes` → `metadata`. Keep them aligned; a divergence here means a translation
layer nobody wanted.

## Availability

Computed per viewer, never stored, never cached across viewers.

```sql
-- Returns free windows shared by all of profile_ids, from the caller's viewpoint.
create or replace function group_availability(
  profile_ids  uuid[],
  range_start  timestamptz,
  range_end    timestamptz
) returns table (starts_at timestamptz, ends_at timestamptz, free_profile_ids uuid[])
```

The implementation expands occurrences for each profile (respecting the caller's effective visibility
— an occurrence that is `hidden` for the caller does not block time), unions them per person,
subtracts from the range, and intersects across people. Windows where `free_profile_ids` covers every
member get the all-clear highlight in the group calendar; partial windows drive the "who's free at
this time" detail sheet.

Two consequences worth stating plainly, because they are product behavior and not just
implementation detail:

- **Hiding an item means appearing free.** A viewer who cannot see an item will be offered that slot.
  The UI should say so when a user chooses `hidden`.
- **Availability differs per viewer.** Two members of the same group can see different free windows
  for the same third person, because they hold different grants. Don't build UI that implies a single
  objective answer.

## Open questions

- Should a group have its own visibility floor — e.g. "everyone in this group sees at least `busy`"
  — overriding a member's per-item default? Simplifies the mental model; costs some control.
- Do we need a materialized occurrence cache for large groups over long ranges, or is on-demand
  expansion fast enough? Measure before adding one; a cache reintroduces the invalidation problems
  this model is built to avoid.
- Message retention and whether `deleted_at` is a soft delete for moderation or a true tombstone.
