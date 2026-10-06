\set ON_ERROR_STOP on
-- KUN LOKALT. ALDRI MOT SUPABASE.
-- Etterligner den delen av Supabase Storage som 008_sosialt.sql bruker:
-- storage.buckets, storage.objects (med RLS på) og storage.foldername().
-- Kjøres etter lokal/stub.sql og før 008.
create schema if not exists storage;
grant usage on schema storage to anon, authenticated, service_role;

create table if not exists storage.buckets (
  id                  text primary key,
  name                text not null unique,
  owner               uuid,
  public              boolean default false,
  file_size_limit     bigint,
  allowed_mime_types  text[],
  created_at          timestamptz default now(),
  updated_at          timestamptz default now()
);

create table if not exists storage.objects (
  id          uuid primary key default gen_random_uuid(),
  bucket_id   text references storage.buckets(id),
  name        text,
  owner       uuid default auth.uid(),
  metadata    jsonb,
  created_at  timestamptz default now(),
  updated_at  timestamptz default now(),
  unique (bucket_id, name)
);
alter table storage.objects enable row level security;
alter table storage.buckets enable row level security;
grant select, insert, update, delete on storage.objects to anon, authenticated, service_role;
grant select on storage.buckets to anon, authenticated, service_role;

-- Som i Supabase: mappene i stien, uten filnavnet.
create or replace function storage.foldername(name text)
returns text[]
language plpgsql
immutable
as $$
declare
  _parts text[];
begin
  select string_to_array(name, '/') into _parts;
  return _parts[1 : array_length(_parts, 1) - 1];
end
$$;
grant execute on function storage.foldername(text) to anon, authenticated, service_role;
