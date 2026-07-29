-- LOCAL TEST SCAFFOLDING ONLY. NOT A MIGRATION. NEVER RUN AGAINST SUPABASE.
--
-- Real Supabase provides the auth schema, auth.users, and auth.uid(). This file
-- recreates the minimum needed to apply migrations to a plain Postgres server,
-- so policies can be executed and tested in an environment without Docker.
--
-- The drift risk is real and worth naming: this shim is my approximation of
-- Supabase's behaviour, not Supabase's behaviour. If the two ever disagree, the
-- tests here will happily pass while production breaks. That is exactly why CI
-- also runs the genuine Supabase stack — treat that as the source of truth and
-- this as the fast local loop.
--
-- Known simplifications:
--   * auth.users has only the columns the trigger and FKs need.
--   * auth.uid() reads a session GUC instead of decoding a JWT.
--   * No auth.role(), no auth.jwt(), no RLS on auth.users itself.

create schema if not exists auth;

create table if not exists auth.users (
  id         uuid primary key default gen_random_uuid(),
  email      text unique,
  created_at timestamptz not null default now()
);

-- Supabase derives this from the request JWT. Here it reads a GUC that tests
-- set with set_config('request.jwt.claim.sub', <uuid>, true), which is the same
-- knob Supabase's own local tooling uses.
create or replace function auth.uid()
returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

-- Roles Supabase defines. Policies are written against the authenticated role,
-- and RLS is not enforced for superusers or table owners — so tests must run as
-- one of these, not as postgres, or every policy silently passes.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
end
$$;

grant usage on schema public to anon, authenticated;
grant usage on schema auth to anon, authenticated;
grant select on auth.users to authenticated;

-- DELIBERATELY NOT GRANTED HERE.
--
-- An earlier version of this shim did `alter default privileges ... grant all on
-- tables to anon, authenticated`, which made every local test pass while the
-- real thing failed with "permission denied for table profiles" on every query.
-- RLS decides which rows a role may see; table-level GRANTs decide whether it
-- may touch the table at all, and Supabase does not hand those out for free.
--
-- Migrations now grant explicitly, which is where that belongs. Keeping this
-- shim ungenerous is the point: it should be stingier than production, never
-- more permissive, so a missing grant fails locally instead of in CI.
