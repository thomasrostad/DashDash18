-- 035: seasons blir et view over competitions (gjennomføringsplanen steg 3, fase 22 trinn 5).
-- Godkjent og kjørt på test 12.10.2026.
--
-- Krever 001–054 (034 er kjørt). Bygger på 017 (competitions, competitions_sync_season,
-- competition_claim_main), 031 (events.competition_id i takt med season_id), 033
-- (competitions_sync_to_season: turneringen er kilden), 034 (activate_season med som_hovedturnering),
-- 038 (delete_tournament) og 052 (bets.competition_id i takt med season_id).
--
-- Bakgrunn (docs/fase-22-turnering-som-kjerne.md kap. 5 og 10, trinn 5): sesongen har vært en rad
-- i seasons speilet til en turneringsrad (competitions.kind = 'season', competitions.season_id =
-- seasons.id, unik). Etter 033 kan begge skrives, og triggerne holder dem like. Nå blir
-- turneringsraden den eneste kilden:
--
--   1. Tabellen seasons erstattes av et view med samme navn og kolonner:
--        select season_id as id, club_id, name, status, rules, created_at, updated_at
--          from competitions where season_id is not null
--      security_invoker: lesing går gjennom RLS på competitions (medlemmer av klubben, pluss
--      deltakere og stab i turneringen; før: bare medlemmer). Sesong-id-ene står, så kvelder,
--      veddemål og import beholder nøklene.
--   2. events.season_id og bets.season_id peker på competitions(season_id, club_id) (ny unik
--      nøkkel; season_id er unik fra før). Samme regler som før: kveldene stopper sletting
--      (restrict), veddemålene følger med (cascade).
--   3. Speilingen fjernes: competitions_sync_season (på tabellen) og competitions_sync_to_season
--      (på competitions). Det som var igjen av dem, at en aktiv sesong blir hovedturnering når
--      klubben ikke har en, gjør competitions_season_main (ny trigger på competitions).
--   4. Gamle bygg skriver fortsatt seasons (ny sesong, nytt navn, regler, avslutt, slett planlagt).
--      INSTEAD OF-triggere på viewet sender skrivingen videre til competitions med de samme
--      rettighetene som policyene på tabellen hadde:
--        insert: som seasons_insert (rettigheten «tournaments» i klubben, via RLS på competitions);
--                turneringsraden lages som competitions_sync_season gjorde (entry club,
--                hovedturnering når klubben ikke har en aktiv);
--        update: navn, status og regler, som seasons_update (via RLS på competitions). id,
--                klubb og opprettet kan ikke endres (42501);
--        delete: bare planlagte, som seasons_delete. Kvelder stopper slettingen (23503).
--      Ingen rad (ikke lov) gir 0 rader tilbake, slik RLS ga før. Den nye appen bruker bare
--      insert og delete på viewet (ny og slett planlagt sesong); alt annet leser og skriver den
--      i competitions og med RPC-er. Derfor kan 035 kjøres uten at min_ios_build stenger noen
--      ute (se «Når» under).
--   5. activate_season(sesong, som_hovedturnering) skriver competitions og svarer med raden fra
--      viewet (samme kolonner som før). Samme oppførsel som 034.
--   6. delete_tournament (038) sletter turneringsraden direkte (tok før sesongen, som tok raden).
--   7. Funksjonene som leser seasons (tavla_data, bet_rule, bet_points, create_bet,
--      private.round_rules_now) står uendret og leser viewet. De er security definer, så RLS
--      påvirker dem ikke.
--   8. Opprettet-tiden: turneringsrader med en annen created_at enn sesongen får sesongens, så
--      lista «nyeste først» er den samme før og etter.
--
-- Når: 035 er trygg for alle bygg, også de som leser seasons, fordi viewet har de samme
-- kolonnene og INSTEAD OF-triggerne tar skrivingen. Den forutsetter IKKE at min_ios_build
-- stenger gamle bygg ute. Det som kan merkes: en deltaker eller funksjonær i en klubbserie som
-- ikke er medlem av klubben, ser nå sesongraden (turneringsraden så de fra før).
--
-- Importen (Packages/DashImport) skriver sesongen med en sjekk i stedet for «on conflict», så
-- den virker både før og etter 035.
--
-- Én transaksjon, idempotent (andre kjøring hopper over flyttingen og lager det samme på nytt).
-- Kontrollblokk og rullebakke nederst.

begin;

-- ===========================================================================
-- 1. FØR FLYTTINGEN: sesongene og turneringsradene er like
-- ===========================================================================
-- Bare når seasons fortsatt er en tabell. Stopper hvis en sesong mangler turneringsrad eller er
-- ulik den (navn, status, regler, klubb). 033 holder dem like; avvik betyr at noe er galt.
do $$
declare
  v_avvik integer;
begin
  if (select c.relkind from pg_class c where c.oid = to_regclass('public.seasons')) = 'r' then
    select count(*) into v_avvik
      from public.seasons s
      left join public.competitions c on c.season_id = s.id
     where c.id is null
        or c.club_id is distinct from s.club_id
        or (c.name, c.status, c.rules) is distinct from (s.name, s.status, s.rules)
        or c.kind <> 'season';
    if v_avvik > 0 then
      raise exception '035: % sesong(er) mangler turneringsrad eller er ulik den', v_avvik;
    end if;
    if exists (select 1 from public.competitions c
               where c.season_id is not null
                 and not exists (select 1 from public.seasons s where s.id = c.season_id)) then
      raise exception '035: turneringsrad med season_id uten sesong';
    end if;
    -- 8. Opprettet-tiden fra sesongen.
    update public.competitions c
       set created_at = s.created_at
      from public.seasons s
     where s.id = c.season_id and c.created_at is distinct from s.created_at;
  end if;
end $$;


-- ===========================================================================
-- 2. SPEILINGEN UT
-- ===========================================================================
drop trigger if exists competitions_sync_to_season on public.competitions;
drop function if exists public.competitions_sync_to_season();

-- activate_season svarer med radtypen public.seasons. Den lages på nytt under (punkt 6).
drop function if exists public.activate_season(uuid, boolean);

alter table public.events drop constraint if exists events_season_fk;
alter table public.bets drop constraint if exists bets_season_fk;
alter table public.competitions drop constraint if exists competitions_season_fk;

-- Ny nøkkel for kveldene og veddemålene: (season_id, club_id). season_id er unik fra før.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'competitions_season_club_key') then
    alter table public.competitions
      add constraint competitions_season_club_key unique (season_id, club_id);
  end if;
end $$;

-- Tabellen går (policyene, seasons_set_updated_at og competitions_sync_season følger med).
do $$
begin
  if (select c.relkind from pg_class c where c.oid = to_regclass('public.seasons')) = 'r' then
    drop table public.seasons;
  end if;
end $$;
drop function if exists public.competitions_sync_season();


-- ===========================================================================
-- 3. VIEWET
-- ===========================================================================
create or replace view public.seasons
  with (security_invoker = true)
as
  select c.season_id as id, c.club_id, c.name, c.status, c.rules, c.created_at, c.updated_at
    from public.competitions c
   where c.season_id is not null;

comment on view public.seasons is
  'Sesongene (035): turneringsradene med season_id. Lesing via RLS på competitions. '
  'Skriving fra gamle bygg går via INSTEAD OF-triggere til competitions.';

-- Standardverdiene fra tabellen, så insert uten id, status eller regler virker som før.
alter view public.seasons alter column id set default gen_random_uuid();
alter view public.seasons alter column status set default 'planned';
alter view public.seasons alter column rules set default '{"version": 1}'::jsonb;
alter view public.seasons alter column created_at set default now();
alter view public.seasons alter column updated_at set default now();

revoke all on public.seasons from public, anon;
grant select, insert, update, delete on public.seasons to authenticated;
grant all on public.seasons to service_role;


-- ===========================================================================
-- 4. KVELDENE OG VEDDEMÅLENE PEKER PÅ TURNERINGEN
-- ===========================================================================
alter table public.events
  add constraint events_season_fk foreign key (season_id, club_id)
  references public.competitions (season_id, club_id) on delete restrict;
alter table public.bets
  add constraint bets_season_fk foreign key (season_id, club_id)
  references public.competitions (season_id, club_id) on delete cascade;


-- ===========================================================================
-- 5. SKRIVING VIA VIEWET (gamle bygg, importen, ny og slett planlagt sesong)
-- ===========================================================================
-- Insert: security invoker, så RLS på competitions (competitions_insert = rettigheten
-- «tournaments», som seasons_insert) avgjør. guard_competitions slipper raden gjennom fordi den
-- lages fra en trigger (pg_trigger_depth() > 1), som competitions_sync_season gjorde.
create or replace function public.seasons_view_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.id := coalesce(new.id, gen_random_uuid());
  new.status := coalesce(new.status, 'planned');
  new.rules := coalesce(new.rules, '{"version": 1}'::jsonb);
  new.created_at := coalesce(new.created_at, now());
  insert into public.competitions (kind, name, club_id, season_id, status, entry, rules, is_main, created_at)
  values ('season', new.name, new.club_id, new.id, new.status, 'club', new.rules,
          not exists (select 1 from public.competitions o
                       where o.club_id = new.club_id and o.is_main and o.status = 'active'),
          new.created_at)
  returning updated_at into new.updated_at;
  return new;
end;
$$;
revoke all on function public.seasons_view_insert() from public, anon;

-- Update: navn, status og regler. RLS på competitions (competitions_update = rettigheten
-- «tournaments», som seasons_update). Stoppet av RLS: ingen rad tilbake.
create or replace function public.seasons_view_update()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if new.id is distinct from old.id or new.club_id is distinct from old.club_id
     or new.created_at is distinct from old.created_at then
    raise exception 'Sesongens id, klubb og opprettet-tid kan ikke endres' using errcode = '42501';
  end if;
  update public.competitions c
     set name = new.name, status = new.status, rules = new.rules
   where c.season_id = old.id
  returning c.id, c.updated_at into v_id, new.updated_at;
  if v_id is null then
    return null;
  end if;
  return new;
end;
$$;
revoke all on function public.seasons_view_update() from public, anon;

-- Delete: bare planlagte, for den med rettigheten «tournaments» (som seasons_delete). Security
-- definer fordi competitions_delete ikke lar noen slette en sesongrad direkte. Raden er alt
-- filtrert av lesingen (RLS på competitions) før triggeren kjøres. Server (uten innlogging,
-- service_role/postgres) slipper sjekken, som RLS slapp dem før. Kvelder stopper (23503).
create or replace function public.seasons_view_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if auth.uid() is not null
     and not (private.has_club_right(old.club_id, 'tournaments') and old.status = 'planned') then
    return null;
  end if;
  delete from public.competitions c where c.season_id = old.id returning c.id into v_id;
  if v_id is null then
    return null;
  end if;
  return old;
end;
$$;
revoke all on function public.seasons_view_delete() from public, anon, authenticated;

drop trigger if exists seasons_insert on public.seasons;
create trigger seasons_insert instead of insert on public.seasons
  for each row execute function public.seasons_view_insert();
drop trigger if exists seasons_update on public.seasons;
create trigger seasons_update instead of update on public.seasons
  for each row execute function public.seasons_view_update();
drop trigger if exists seasons_delete on public.seasons;
create trigger seasons_delete instead of delete on public.seasons
  for each row execute function public.seasons_view_delete();


-- ===========================================================================
-- 6. HOVEDTURNERINGEN OG activate_season
-- ===========================================================================
-- En sesong som blir aktiv, blir hovedturnering når klubben ikke har en aktiv (som
-- competitions_sync_season og competitions_sync_to_season gjorde). competition_claim_main gjør
-- ingenting når en annen er hovedturnering, så triggeren kan kjøres fra alle veier.
create or replace function public.competitions_season_main()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.competition_claim_main(new.id);
  return null;
end;
$$;
revoke all on function public.competitions_season_main() from public, anon, authenticated;

drop trigger if exists competitions_season_main on public.competitions;
create trigger competitions_season_main
  after insert or update of status on public.competitions
  for each row when (new.season_id is not null and new.status = 'active')
  execute function public.competitions_season_main();

-- Som 034, men på competitions. Security invoker som før: RLS på competitions
-- (competitions_update = rettigheten «tournaments») stopper den som ikke er arrangør.
create or replace function public.activate_season(p_season_id uuid, p_as_main boolean default true)
returns public.seasons
language plpgsql
set search_path = ''
as $$
declare
  v_club   uuid;
  v_id     uuid;
  v_row    public.seasons;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select c.club_id into v_club from public.competitions c where c.season_id = p_season_id;
  if not found then
    raise exception 'Fant ikke turneringen' using errcode = 'P0002';
  end if;
  -- Som hovedturnering: den forrige aktive hovedturneringen i klubben avsluttes.
  -- Andre aktive serier står.
  if p_as_main then
    update public.competitions c
       set status = 'finished'
     where c.club_id = v_club and c.status = 'active' and c.season_id is not null
       and c.season_id <> p_season_id and c.is_main;
  end if;
  update public.competitions c
     set status = 'active'
   where c.season_id = p_season_id
  returning c.id into v_id;
  -- Ingen rad: RLS stoppet skrivingen (ikke arrangør).
  if v_id is null then
    raise exception 'Bare arrangøren kan aktivere en turnering' using errcode = '42501';
  end if;
  -- Hovedturnering blir den av competitions_season_main når klubben ikke har en annen.
  select * into v_row from public.seasons s where s.id = p_season_id;
  return v_row;
end;
$$;
revoke all on function public.activate_season(uuid, boolean) from public, anon;
grant execute on function public.activate_season(uuid, boolean) to authenticated;


-- ===========================================================================
-- 7. delete_tournament (038): turneringsraden slettes direkte
-- ===========================================================================
create or replace function public.delete_tournament(p_competition_id uuid, p_confirm_name text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_comp    public.competitions%rowtype;
  v_events  uuid[];
  n_rounds  integer := 0;
  n_events  integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select * into v_comp from public.competitions c where c.id = p_competition_id for update;
  if not found then
    raise exception 'Fant ingen turnering å slette. Er den alt borte?' using errcode = 'P0002';
  end if;
  if not public.is_competition_admin(p_competition_id) then
    raise exception 'Bare arrangøren kan slette turneringen' using errcode = '42501';
  end if;
  if lower(btrim(coalesce(p_confirm_name, ''))) <> lower(btrim(v_comp.name)) then
    raise exception 'Skriv navnet på turneringen for å slette den' using errcode = '22023';
  end if;
  -- Kveldene/spilledagene som hører til turneringen (sesongen eller turneringsraden).
  select coalesce(array_agg(e.id), '{}') into v_events
    from public.events e
   where e.competition_id = p_competition_id
      or (v_comp.season_id is not null and e.season_id = v_comp.season_id);
  delete from public.rounds r where r.event_id = any (v_events);
  get diagnostics n_rounds = row_count;
  delete from public.events e where e.id = any (v_events);
  get diagnostics n_events = row_count;
  -- 035: sesongen er turneringsraden. Veddemålene følger med (bets_season_fk, cascade).
  delete from public.competitions c where c.id = p_competition_id;
  return jsonb_build_object('name', v_comp.name, 'rounds', n_rounds, 'events', n_events);
end;
$$;
revoke all on function public.delete_tournament(uuid, text) from public, anon;
grant execute on function public.delete_tournament(uuid, text) to authenticated;


-- ===========================================================================
-- KONTROLL (kjøres i samme transaksjon; feiler ved avvik)
-- ===========================================================================
do $$
declare
  v_fail text := '';
  v_n    integer := 0;
begin
  -- 1. seasons er et view med security_invoker og de sju kolonnene i samme rekkefølge.
  if (select c.relkind from pg_class c where c.oid = 'public.seasons'::regclass) <> 'v'
     or not exists (select 1 from pg_class c where c.oid = 'public.seasons'::regclass
                    and 'security_invoker=true' = any (c.reloptions)) then
    v_fail := v_fail || ' 1a';
  end if;
  if (select string_agg(a.attname, ',' order by a.attnum) from pg_attribute a
       where a.attrelid = 'public.seasons'::regclass and a.attnum > 0 and not a.attisdropped)
     <> 'id,club_id,name,status,rules,created_at,updated_at' then
    v_fail := v_fail || ' 1b';
  end if;
  v_n := v_n + 1;
  -- 2. Én sesongrad per turneringsrad med season_id, og ingen dobbel id.
  if (select count(*) from public.seasons) <> (select count(*) from public.competitions where season_id is not null)
     or exists (select id from public.seasons group by id having count(*) > 1) then
    v_fail := v_fail || ' 2';
  end if;
  v_n := v_n + 1;
  -- 3. Kveldene og veddemålene peker på competitions, og alle rader har en sesong.
  if not exists (select 1 from pg_constraint where conname = 'events_season_fk'
                 and confrelid = 'public.competitions'::regclass and confdeltype = 'r')
     or not exists (select 1 from pg_constraint where conname = 'bets_season_fk'
                    and confrelid = 'public.competitions'::regclass and confdeltype = 'c') then
    v_fail := v_fail || ' 3a';
  end if;
  if exists (select 1 from public.events e where e.season_id is not null
             and not exists (select 1 from public.seasons s where s.id = e.season_id and s.club_id = e.club_id))
     or exists (select 1 from public.bets b where b.season_id is not null
                and not exists (select 1 from public.seasons s where s.id = b.season_id and s.club_id = b.club_id)) then
    v_fail := v_fail || ' 3b';
  end if;
  v_n := v_n + 1;
  -- 4. Kveldenes season_id og competition_id er fortsatt i takt (031).
  if exists (select 1 from public.events e join public.competitions c on c.season_id = e.season_id
             where e.competition_id is distinct from c.id) then
    v_fail := v_fail || ' 4';
  end if;
  v_n := v_n + 1;
  -- 5. Speilingen er borte, de nye triggerne står.
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname in ('competitions_sync_season', 'competitions_sync_to_season'))
     or (select count(*) from pg_trigger t where t.tgrelid = 'public.seasons'::regclass
          and t.tgname in ('seasons_insert', 'seasons_update', 'seasons_delete')) <> 3
     or not exists (select 1 from pg_trigger t where t.tgrelid = 'public.competitions'::regclass
                    and t.tgname = 'competitions_season_main') then
    v_fail := v_fail || ' 5';
  end if;
  v_n := v_n + 1;
  -- 6. Ingen funksjon i public eller private skriver til seasons uten å gå via viewet
  --    (de som leser, er de kjente).
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname in ('public', 'private')
               and p.prosrc ~* '(insert\s+into|update|delete\s+from)\s+public\.seasons\M') then
    v_fail := v_fail || ' 6';
  end if;
  v_n := v_n + 1;
  -- 7. anon kan ikke lese viewet eller kalle funksjonene.
  if has_table_privilege('anon', 'public.seasons', 'select')
     or has_function_privilege('anon', 'public.activate_season(uuid, boolean)', 'execute')
     or has_function_privilege('anon', 'public.delete_tournament(uuid, text)', 'execute') then
    v_fail := v_fail || ' 7';
  end if;
  v_n := v_n + 1;
  -- 8. Høyst én aktiv hovedturnering per klubb (uendret).
  if exists (select club_id from public.competitions where is_main and status = 'active'
             group by club_id having count(*) > 1) then
    v_fail := v_fail || ' 8';
  end if;
  v_n := v_n + 1;
  -- 9. Sesongradene er turneringer av typen season med klubb.
  if exists (select 1 from public.competitions c where c.season_id is not null
             and (c.kind <> 'season' or c.club_id is null)) then
    v_fail := v_fail || ' 9';
  end if;
  v_n := v_n + 1;
  -- 10. authenticated kan lese og skrive viewet (gamle bygg).
  if not (has_table_privilege('authenticated', 'public.seasons', 'select')
          and has_table_privilege('authenticated', 'public.seasons', 'insert')
          and has_table_privilege('authenticated', 'public.seasons', 'update')
          and has_table_privilege('authenticated', 'public.seasons', 'delete')) then
    v_fail := v_fail || ' 10';
  end if;
  v_n := v_n + 1;
  if v_fail <> '' then
    raise exception '035 kontroll feilet:%', v_fail;
  end if;
  raise notice '035 kontroll: % av 10', v_n;
end $$;

notify pgrst, 'reload schema';

commit;

-- ===========================================================================
-- RULLEBAKKE (tabellen lages på nytt fra turneringsradene; id-ene står)
-- ===========================================================================
-- begin;
-- drop trigger if exists competitions_season_main on public.competitions;
-- drop function if exists public.competitions_season_main();
-- drop function if exists public.activate_season(uuid, boolean);
-- alter table public.events drop constraint if exists events_season_fk;
-- alter table public.bets drop constraint if exists bets_season_fk;
-- drop view if exists public.seasons;
-- drop function if exists public.seasons_view_insert();
-- drop function if exists public.seasons_view_update();
-- drop function if exists public.seasons_view_delete();
-- create table public.seasons (
--   id         uuid primary key default gen_random_uuid(),
--   club_id    uuid not null references public.clubs(id) on delete cascade,
--   name       text not null check (char_length(btrim(name)) between 1 and 60),
--   status     text not null default 'planned' check (status in ('planned', 'active', 'finished')),
--   rules      jsonb not null default '{"version": 1}'::jsonb,
--   created_at timestamptz not null default now(),
--   updated_at timestamptz not null default now(),
--   constraint seasons_id_club_key unique (id, club_id),
--   constraint seasons_rules_shape check (jsonb_typeof(rules) = 'object'
--     and case when jsonb_typeof(rules -> 'version') = 'number' then (rules -> 'version')::numeric >= 1 else false end
--     and pg_column_size(rules) <= 65536)
-- );
-- create index seasons_club_idx on public.seasons (club_id);
-- insert into public.seasons (id, club_id, name, status, rules, created_at, updated_at)
--   select season_id, club_id, name, status, rules, created_at, updated_at
--     from public.competitions where season_id is not null;
-- alter table public.seasons enable row level security;
-- create policy seasons_select on public.seasons for select to authenticated using (public.is_club_member(club_id));
-- create policy seasons_insert on public.seasons for insert to authenticated
--   with check (private.has_club_right(club_id, 'tournaments'));
-- create policy seasons_update on public.seasons for update to authenticated
--   using (private.has_club_right(club_id, 'tournaments')) with check (private.has_club_right(club_id, 'tournaments'));
-- create policy seasons_delete on public.seasons for delete to authenticated
--   using (private.has_club_right(club_id, 'tournaments') and status = 'planned');
-- revoke all on public.seasons from public, anon;
-- grant select, insert, update, delete on public.seasons to authenticated;
-- create trigger seasons_set_updated_at before update on public.seasons
--   for each row execute function public.set_updated_at();
-- alter table public.competitions add constraint competitions_season_fk foreign key (season_id, club_id)
--   references public.seasons (id, club_id) on delete cascade;
-- alter table public.events add constraint events_season_fk foreign key (season_id, club_id)
--   references public.seasons (id, club_id) on delete restrict;
-- alter table public.bets add constraint bets_season_fk foreign key (season_id, club_id)
--   references public.seasons (id, club_id) on delete cascade;
-- alter table public.competitions drop constraint if exists competitions_season_club_key;
-- (gjenopprett competitions_sync_season og triggeren på seasons fra 033_turnering_kjerne_trinn3.sql,
--  competitions_sync_to_season og triggeren på competitions fra 033, activate_season(uuid, boolean)
--  fra 034_turnering_kjerne_trinn4.sql, og delete_tournament fra 038_slett_turnering.sql)
-- notify pgrst, 'reload schema';
-- commit;
