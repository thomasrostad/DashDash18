\set ON_ERROR_STOP on
-- KUN LOKALT. ALDRI MOT SUPABASE.
-- Etterligner det Supabase har fra før (rollene anon/authenticated/service_role,
-- auth.users, auth.uid(), standardrettighetene i public og publikasjonen
-- supabase_realtime), så migreringen og rolleprøven kan kjøres i en tom,
-- lokal Postgres. auth.uid() leser request.jwt.claim.sub, som i Supabase.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin bypassrls; end if;
end $$;
create schema auth;
create table auth.users (id uuid primary key);
create function auth.uid() returns uuid language sql stable as
$$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;
grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
create publication supabase_realtime;
