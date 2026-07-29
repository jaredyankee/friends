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

-- Supabase grants these automatically for tables created in public. Without the
-- equivalent here, every query fails on permissions before RLS is ever
-- consulted — which looks like a policy bug and is not one.
alter default privileges in schema public
  grant all on tables to anon, authenticated;
alter default privileges in schema public
  grant all on sequences to anon, authenticated;
alter default privileges in schema public
  grant execute on functions to anon, authenticated;
