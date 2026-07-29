-- Policy tests for the identity schema.
--
-- These run as the `authenticated` role, not as postgres. That matters: RLS is
-- not enforced for superusers or table owners, so a suite run as postgres passes
-- everything regardless of whether the policies are correct.
--
-- Style: each assertion raises on failure. A silent pass is the enemy here, so
-- the harness is deliberately verified against a known-bad assertion before it
-- is trusted (see `npm run db:test:selfcheck`).
--
-- Emphasis is on the negative cases. That a friend CAN read a profile is easy to
-- get right by accident; that a stranger CANNOT is the property with teeth.

\set ON_ERROR_STOP on

begin;

-- ---------------------------------------------------------------------------
-- Fixtures. Created as the owner, before we drop to `authenticated`.
-- ---------------------------------------------------------------------------

-- alice + bob are friends. carol is a stranger to both. dave shares a group
-- with alice but is not her friend. erin has a pending request to alice.
insert into auth.users (id, email) values
  ('a0000000-0000-4000-8000-000000000001', 'alice+policytest@example.com'),
  ('a0000000-0000-4000-8000-000000000002', 'bob+policytest@example.com'),
  ('a0000000-0000-4000-8000-000000000003', 'carol+policytest@example.com'),
  ('a0000000-0000-4000-8000-000000000004', 'dave+policytest@example.com'),
  ('a0000000-0000-4000-8000-000000000005', 'erin+policytest@example.com');

-- The trigger should have made a profile for each. Verify that before anything
-- else — if it did not fire, every later assertion is meaningless.
do $$
declare n integer;
begin
  select count(*) into n from profiles
   where id::text like 'a0000000-0000-4000-8000-00000000000%';
  if n <> 5 then
    raise exception 'TRIGGER: expected 5 profiles from auth.users inserts, found %', n;
  end if;
end
$$;

do $$
declare h citext;
begin
  select handle into h from profiles where id = 'a0000000-0000-4000-8000-000000000001';
  if h <> 'alicepolicytest' then
    raise exception 'TRIGGER: expected handle derived from email local part, got %', h;
  end if;
end
$$;

insert into friendships (requester_id, addressee_id, status, responded_at) values
  ('a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000002', 'accepted', now());

insert into friendships (requester_id, addressee_id, status) values
  ('a0000000-0000-4000-8000-000000000005', 'a0000000-0000-4000-8000-000000000001', 'pending');

insert into groups (id, name, created_by) values
  ('a0000000-0000-4000-8000-0000000000f1', 'Climbing', 'a0000000-0000-4000-8000-000000000001');

insert into group_members (group_id, profile_id, role) values
  ('a0000000-0000-4000-8000-0000000000f1', 'a0000000-0000-4000-8000-000000000001', 'owner'),
  ('a0000000-0000-4000-8000-0000000000f1', 'a0000000-0000-4000-8000-000000000004', 'member');

-- ---------------------------------------------------------------------------
-- Helper: run a count query as a given user and assert the result.
-- ---------------------------------------------------------------------------

create or replace function assert_count(
  as_user uuid,
  query   text,
  expected bigint,
  label   text
) returns void language plpgsql as $$
declare actual bigint;
begin
  perform set_config('request.jwt.claim.sub', as_user::text, true);
  execute query into actual;
  if actual is distinct from expected then
    raise exception '% — expected %, got %', label, expected, actual;
  end if;
end;
$$;

set role authenticated;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------

select assert_count(
  'a0000000-0000-4000-8000-000000000003',
  $q$ select count(*) from profiles where id = 'a0000000-0000-4000-8000-000000000001' $q$,
  0,
  'PROFILES: a stranger must not read another profile at all'
);

select assert_count(
  'a0000000-0000-4000-8000-000000000002',
  $q$ select count(*) from profiles where id = 'a0000000-0000-4000-8000-000000000001' $q$,
  1,
  'PROFILES: an accepted friend can read the profile'
);

select assert_count(
  'a0000000-0000-4000-8000-000000000001',
  $q$ select count(*) from profiles where id = 'a0000000-0000-4000-8000-000000000001' $q$,
  1,
  'PROFILES: you can always read your own profile'
);

select assert_count(
  'a0000000-0000-4000-8000-000000000004',
  $q$ select count(*) from profiles where id = 'a0000000-0000-4000-8000-000000000001' $q$,
  1,
  'PROFILES: sharing a group is enough to see a profile'
);

select assert_count(
  'a0000000-0000-4000-8000-000000000005',
  $q$ select count(*) from profiles where id = 'a0000000-0000-4000-8000-000000000001' $q$,
  1,
  'PROFILES: a pending request makes the other party visible'
);

-- The scraping case: a stranger enumerating the whole table sees only self.
select assert_count(
  'a0000000-0000-4000-8000-000000000003',
  $q$ select count(*) from profiles $q$,
  1,
  'PROFILES: a stranger enumerating profiles sees only their own'
);

-- ---------------------------------------------------------------------------
-- friendships
-- ---------------------------------------------------------------------------

select assert_count(
  'a0000000-0000-4000-8000-000000000003',
  $q$ select count(*) from friendships $q$,
  0,
  'FRIENDSHIPS: an uninvolved user sees no friendship rows'
);

select assert_count(
  'a0000000-0000-4000-8000-000000000001',
  $q$ select count(*) from friendships $q$,
  2,
  'FRIENDSHIPS: a party sees rows they are part of'
);

-- Forging a friendship on someone else's behalf must fail.
do $$
begin
  perform set_config('request.jwt.claim.sub', 'a0000000-0000-4000-8000-000000000003', true);
  begin
    insert into friendships (requester_id, addressee_id, status)
    values ('a0000000-0000-4000-8000-000000000001',
            'a0000000-0000-4000-8000-000000000003', 'pending');
    raise exception 'FRIENDSHIPS: carol forged a request as alice — insert policy is broken';
  exception
    when insufficient_privilege then null;  -- expected
  end;
end
$$;

-- Self-accepting must fail: inserting an already-accepted row would let anyone
-- befriend anyone unilaterally.
do $$
begin
  perform set_config('request.jwt.claim.sub', 'a0000000-0000-4000-8000-000000000003', true);
  begin
    insert into friendships (requester_id, addressee_id, status)
    values ('a0000000-0000-4000-8000-000000000003',
            'a0000000-0000-4000-8000-000000000001', 'accepted');
    raise exception 'FRIENDSHIPS: carol inserted a pre-accepted friendship — status check is broken';
  exception
    when insufficient_privilege then null;  -- expected
  end;
end
$$;

-- ---------------------------------------------------------------------------
-- groups and membership
-- ---------------------------------------------------------------------------

select assert_count(
  'a0000000-0000-4000-8000-000000000003',
  $q$ select count(*) from groups $q$,
  0,
  'GROUPS: a non-member cannot see the group'
);

select assert_count(
  'a0000000-0000-4000-8000-000000000004',
  $q$ select count(*) from groups $q$,
  1,
  'GROUPS: a member can see their group'
);

select assert_count(
  'a0000000-0000-4000-8000-000000000003',
  $q$ select count(*) from group_members $q$,
  0,
  'GROUP_MEMBERS: a non-member cannot enumerate membership'
);

select assert_count(
  'a0000000-0000-4000-8000-000000000004',
  $q$ select count(*) from group_members $q$,
  2,
  'GROUP_MEMBERS: a member sees the roster'
);

-- A plain member must not be able to add people.
do $$
begin
  perform set_config('request.jwt.claim.sub', 'a0000000-0000-4000-8000-000000000004', true);
  begin
    insert into group_members (group_id, profile_id)
    values ('a0000000-0000-4000-8000-0000000000f1',
            'a0000000-0000-4000-8000-000000000003');
    raise exception 'GROUP_MEMBERS: a plain member added someone — insert policy is broken';
  exception
    when insufficient_privilege then null;  -- expected
  end;
end
$$;

-- A member can remove themselves.
--
-- Verified from the owner's side on purpose. Counting as dave after he leaves
-- returns 0 — not because the delete over-reached, but because the select policy
-- requires membership and he no longer has any. That is correct behaviour and an
-- easy way to write a test that fails for the wrong reason.
do $$
begin
  perform set_config('request.jwt.claim.sub', 'a0000000-0000-4000-8000-000000000004', true);
  delete from group_members
   where group_id = 'a0000000-0000-4000-8000-0000000000f1'
     and profile_id = 'a0000000-0000-4000-8000-000000000004';
end
$$;

select assert_count(
  'a0000000-0000-4000-8000-000000000001',
  $q$ select count(*) from group_members
       where group_id = 'a0000000-0000-4000-8000-0000000000f1' $q$,
  1,
  'GROUP_MEMBERS: after dave leaves, the owner sees only themselves'
);

select assert_count(
  'a0000000-0000-4000-8000-000000000004',
  $q$ select count(*) from group_members $q$,
  0,
  'GROUP_MEMBERS: having left, dave can no longer see the roster'
);

reset role;

rollback;

\echo 'ALL POLICY TESTS PASSED'
