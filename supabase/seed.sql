-- Development seed data. Runs on `supabase db reset`.
--
-- Not test fixtures — the policy tests in supabase/tests/ build their own and
-- roll back. This is for having something to look at while building screens.
--
-- Inserting into auth.users fires handle_new_user(), so profiles are created by
-- the trigger rather than inserted here. That is deliberate: it means every
-- reset exercises the trigger, and a seed that stopped matching the trigger's
-- behaviour would be noticed.

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'alice@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'bob@example.com'),
  ('33333333-3333-3333-3333-333333333333', 'carol@example.com'),
  ('44444444-4444-4444-4444-444444444444', 'dave@example.com'),
  ('55555555-5555-5555-5555-555555555555', 'erin@example.com')
on conflict (id) do nothing;

-- Give the seeded profiles friendlier names and a spread of time zones, so the
-- cross-zone rendering work in T2/T3 has something real to exercise.
update profiles set display_name = 'Alice Nguyen',  time_zone = 'America/New_York'
  where id = '11111111-1111-1111-1111-111111111111';
update profiles set display_name = 'Bob Okafor',    time_zone = 'America/Los_Angeles'
  where id = '22222222-2222-2222-2222-222222222222';
update profiles set display_name = 'Carol Simmons', time_zone = 'Europe/London'
  where id = '33333333-3333-3333-3333-333333333333';
update profiles set display_name = 'Dave Ruiz',     time_zone = 'Asia/Kathmandu'
  where id = '44444444-4444-4444-4444-444444444444';
update profiles set display_name = 'Erin Walsh',    time_zone = 'Australia/Eucla'
  where id = '55555555-5555-5555-5555-555555555555';

-- Alice and Bob are friends. Carol is a stranger. Erin has asked Alice.
insert into friendships (requester_id, addressee_id, status, responded_at) values
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'accepted', now()),
  ('11111111-1111-1111-1111-111111111111', '44444444-4444-4444-4444-444444444444', 'accepted', now())
on conflict do nothing;

insert into friendships (requester_id, addressee_id, status) values
  ('55555555-5555-5555-5555-555555555555', '11111111-1111-1111-1111-111111111111', 'pending')
on conflict do nothing;

insert into groups (id, name, created_by) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Climbing',    '11111111-1111-1111-1111-111111111111'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'Sunday Roast','22222222-2222-2222-2222-222222222222')
on conflict (id) do nothing;

insert into group_members (group_id, profile_id, role) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'owner'),
  ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'member'),
  ('aaaaaaaa-0000-0000-0000-000000000001', '44444444-4444-4444-4444-444444444444', 'member'),
  ('aaaaaaaa-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'owner'),
  ('aaaaaaaa-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'member')
on conflict do nothing;
