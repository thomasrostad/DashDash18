-- 064: feilrapporter fra MetricKit (fase 17, lanseringssjekken 7.1: krasj og heng fra ekte brukere).
--
-- Hva:
--   * public.app_diagnostics: én rad per diagnose fra MetricKit (krasj, heng, CPU, disk,
--     oppstart). payload er Apples JSON (MXDiagnosticPayload.jsonRepresentation) med bare
--     den ene diagnosen, høyst ca. 200 kB. signature er en kort oppsummering (unntak eller
--     signal og øverste ramme i appen), høyst 300 tegn.
--   * Ingen persondata utover user_id (auth.uid(), null etter at kontoen er slettet).
--   * RLS på og ingen policyer: verken anon eller authenticated kan lese eller skrive
--     tabellen direkte. Bare service_role (SQL Editor) leser den.
--   * public.submit_diagnostics(p_items jsonb): appen sender opptil 20 rader per kall,
--     høyst 50 per bruker per døgn. Feltene og lengdene sjekkes, og én ugyldig rad avviser
--     hele kallet (appen beholder radene og prøver igjen senere). Gir antall rader lagt inn.
--
-- Bare additivt: lager nye objekter og endrer ingenting som finnes fra før.
-- Krever: ingenting utover Supabase (auth.users, auth.uid()).
--
-- Rullebakke nederst. Idempotent.

begin;

-- --- Tabellen -------------------------------------------------------------------
create table if not exists public.app_diagnostics (
  id           uuid primary key default gen_random_uuid(),
  created_at   timestamptz not null default now(),
  user_id      uuid default auth.uid() references auth.users (id) on delete set null,
  app_version  text check (char_length(app_version) <= 40),
  build        text check (char_length(build) <= 40),
  os_version   text check (char_length(os_version) <= 120),
  device_model text check (char_length(device_model) <= 60),
  kind         text not null check (kind in ('crash', 'hang', 'cpu', 'disk', 'launch')),
  signature    text check (char_length(signature) <= 300),
  payload      jsonb not null check (jsonb_typeof(payload) = 'object' and pg_column_size(payload) <= 204800),
  environment  text not null check (environment in ('test', 'prod'))
);

create index if not exists app_diagnostics_user_created_idx
  on public.app_diagnostics (user_id, created_at desc);
create index if not exists app_diagnostics_created_idx
  on public.app_diagnostics (created_at desc);

alter table public.app_diagnostics enable row level security;
-- Ingen policyer. Standardrettighetene i public gir anon og authenticated alt på nye tabeller;
-- de tas bort her også, så tabellen er stengt selv om RLS en dag slås av.
revoke all on table public.app_diagnostics from public, anon, authenticated;
grant all on table public.app_diagnostics to service_role;

-- --- Innsendingen ---------------------------------------------------------------
create or replace function public.submit_diagnostics(p_items jsonb)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := auth.uid();
  v_count integer;
  v_used  integer;
  v_item  jsonb;
  v_n     integer := 0;
begin
  if v_uid is null then
    raise exception 'submit_diagnostics: ikke innlogget' using errcode = '42501';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'submit_diagnostics: p_items må være en liste' using errcode = '22023';
  end if;
  v_count := jsonb_array_length(p_items);
  if v_count = 0 then
    return 0;
  end if;
  if v_count > 20 then
    raise exception 'submit_diagnostics: høyst 20 rader per kall' using errcode = '22023';
  end if;

  -- Ett kall om gangen per bruker, så grensen per døgn holder også ved samtidige kall.
  perform pg_advisory_xact_lock(hashtextextended('submit_diagnostics:' || v_uid::text, 0));
  select count(*) into v_used
    from public.app_diagnostics d
   where d.user_id = v_uid and d.created_at > now() - interval '1 day';
  if v_used + v_count > 50 then
    raise exception 'submit_diagnostics: høyst 50 rader per døgn' using errcode = '54000';
  end if;

  for v_item in select e from jsonb_array_elements(p_items) e loop
    if jsonb_typeof(v_item) <> 'object' then
      raise exception 'submit_diagnostics: hver rad må være et objekt' using errcode = '22023';
    end if;
    if coalesce(v_item->>'kind', '') not in ('crash', 'hang', 'cpu', 'disk', 'launch') then
      raise exception 'submit_diagnostics: ukjent kind' using errcode = '22023';
    end if;
    if coalesce(v_item->>'environment', '') not in ('test', 'prod') then
      raise exception 'submit_diagnostics: ukjent environment' using errcode = '22023';
    end if;
    if jsonb_typeof(v_item->'payload') is distinct from 'object'
       or octet_length((v_item->'payload')::text) > 200000 then
      raise exception 'submit_diagnostics: payload mangler eller er for stor' using errcode = '22023';
    end if;
    if char_length(v_item->>'signature') > 300
       or char_length(v_item->>'app_version') > 40
       or char_length(v_item->>'build') > 40
       or char_length(v_item->>'os_version') > 120
       or char_length(v_item->>'device_model') > 60 then
      raise exception 'submit_diagnostics: et felt er for langt' using errcode = '22023';
    end if;

    insert into public.app_diagnostics
      (user_id, app_version, build, os_version, device_model, kind, signature, payload, environment)
    values
      (v_uid, v_item->>'app_version', v_item->>'build', v_item->>'os_version', v_item->>'device_model',
       v_item->>'kind', v_item->>'signature', v_item->'payload', v_item->>'environment');
    v_n := v_n + 1;
  end loop;

  return v_n;
end;
$$;
-- Anon-fella (sql/README.md): revoke etter create or replace.
revoke all on function public.submit_diagnostics(jsonb) from public, anon;
grant execute on function public.submit_diagnostics(jsonb) to authenticated;

-- --- Kontroll -------------------------------------------------------------------
do $$
begin
  if to_regclass('public.app_diagnostics') is null then
    raise exception '064: tabellen app_diagnostics mangler';
  end if;
  if not (select c.relrowsecurity from pg_class c where c.oid = 'public.app_diagnostics'::regclass) then
    raise exception '064: RLS er ikke på for app_diagnostics';
  end if;
  if exists (select 1 from pg_policy where polrelid = 'public.app_diagnostics'::regclass) then
    raise exception '064: app_diagnostics skal ikke ha policyer';
  end if;
  if has_table_privilege('anon', 'public.app_diagnostics', 'select')
     or has_table_privilege('authenticated', 'public.app_diagnostics', 'select')
     or has_table_privilege('anon', 'public.app_diagnostics', 'insert')
     or has_table_privilege('authenticated', 'public.app_diagnostics', 'insert') then
    raise exception '064: anon eller authenticated har rettigheter på app_diagnostics';
  end if;
  if has_function_privilege('anon', 'public.submit_diagnostics(jsonb)', 'execute') then
    raise exception '064: anon kan kjøre submit_diagnostics';
  end if;
  if not has_function_privilege('authenticated', 'public.submit_diagnostics(jsonb)', 'execute') then
    raise exception '064: authenticated kan ikke kjøre submit_diagnostics';
  end if;
  raise notice '064 kontroll: 6 av 6';
end $$;

commit;

-- KONTROLL ETTERPÅ (bare lesing)
-- 1) Anon-fella. Forventet: anon_kan = false, auth_kan = true.
-- select has_function_privilege('anon', 'public.submit_diagnostics(jsonb)', 'execute') as anon_kan,
--        has_function_privilege('authenticated', 'public.submit_diagnostics(jsonb)', 'execute') as auth_kan;
-- 2) De siste feilrapportene (som postgres i SQL Editor):
-- select created_at, environment, kind, app_version, build, os_version, device_model, signature
--   from public.app_diagnostics order by created_at desc limit 50;
-- 3) Oftest siste 7 dager:
-- select kind, signature, count(*) as antall, count(distinct user_id) as brukere, max(app_version) as siste_versjon
--   from public.app_diagnostics where created_at > now() - interval '7 days'
--  group by kind, signature order by antall desc limit 20;

-- RULLEBAKKE
-- begin;
-- drop function if exists public.submit_diagnostics(jsonb);
-- drop table if exists public.app_diagnostics;
-- commit;
