-- 034: turneringen som kjerne, trinn 4 (gjennomføringsplanen steg 1). IKKE KJØRT. Krever godkjenning.
--
-- Rydder bort reglene fra da en klubb bare hadde én sesong og én runde om gangen
-- (docs/fase-22-turnering-som-kjerne.md kap. 4, 5 og 6). Etter 034 kan en klubb
-- kjøre flere serier, flere spilledager samme dato og flere runder samtidig:
--
--   1. rounds_one_active_per_club fjernes. Regelen er nå rounds_one_active_per_event_wave
--      (031): høyst én aktiv runde per spilledag og pulje. Løse runder som før.
--   2. seasons_one_active_per_club fjernes. Høyst én aktiv HOVEDturnering per klubb
--      står (competitions_one_main_active, 017).
--   3. events_one_per_date fjernes. Høyst én spilledag per turnering og dato står
--      (events_one_per_date_per_competition, 031).
--   4. round_players.bay_no går opp til 99 (som round_start_groups.group_no).
--   5. activate_season(sesong, som_hovedturnering default true):
--        * som i dag (standard): den forrige aktive hovedturneringen avsluttes, og
--          serien tar over som hovedturnering. Golfgutu-flyten «ny sesong → aktiver»
--          er uendret;
--        * med false: serien blir aktiv ved siden av, og jakkeracet står
--          (svaret på åpent spørsmål 1 i 033).
--   6. activity.club_id blir valgfri, med krav om klubb eller turnering, og en
--      lesegren for den som kan se turneringen (private turneringer uten klubb).
--      Ingen hendelser lages uten klubb ennå; det kommer i steg 9. Push-køen
--      hopper over dem til steg 5.
--   7. create_bet uten kveld bruker hovedturneringen, ikke «en aktiv sesong».
--
-- Ikke med (flyttet i gjennomføringsplanen):
--   * ikke-medlemmer i klubbrunder: steg 4 (påmelding);
--   * push per turnering (push_queue.competition_id): steg 5 (varsler);
--   * app_config.min_ios_build settes for seg når bygget med steg 1 er ute (egen
--     setning nederst, kjøres etter at Thomas har bekreftet byggnummeret).
--
-- Trygt for dagens app: ingen kolonne fjernes, ingen policy strammes inn. Bygg som
-- antar «én aktiv runde per klubb» viser bare den første de finner.
--
-- Én transaksjon, idempotent. Kontrollblokk og rullebakke nederst.

begin;

-- ===========================================================================
-- 1–3. DE GAMLE UNIKE REGLENE
-- ===========================================================================
-- Erstatningene finnes fra før. Stopp hvis noen av dem mangler.
do $$
begin
  if not exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'rounds_one_active_per_event_wave')
     or not exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'events_one_per_date_per_competition')
     or not exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'competitions_one_main_active') then
    raise exception '034: erstatningsreglene fra 017/031 mangler';
  end if;
end $$;

drop index if exists public.rounds_one_active_per_club;
drop index if exists public.seasons_one_active_per_club;
alter table public.events drop constraint if exists events_one_per_date;


-- ===========================================================================
-- 4. BÅS OPP TIL 99
-- ===========================================================================
alter table public.round_players drop constraint if exists round_players_bay_no_check;
alter table public.round_players add constraint round_players_bay_no_check check (bay_no between 1 and 99);


-- ===========================================================================
-- 5. activate_season: bare hovedturneringen avsluttes
-- ===========================================================================
-- Den gamle signaturen (uuid) erstattes av (uuid, boolean default true), så
-- dagens kall med ett argument gir samme oppførsel som før.
drop function if exists public.activate_season(uuid);

create or replace function public.activate_season(p_season_id uuid, p_as_main boolean default true)
returns public.seasons
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_club   uuid;
  v_row    public.seasons;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  select s.club_id into v_club from public.seasons s where s.id = p_season_id;
  if not found then
    raise exception 'Fant ikke turneringen' using errcode = 'P0002';
  end if;

  -- Som hovedturnering: den forrige aktive hovedturneringen i klubben avsluttes.
  -- Andre aktive serier står.
  if p_as_main then
    update public.seasons s
       set status = 'finished'
     where s.club_id = v_club and s.status = 'active' and s.id <> p_season_id
       and exists (select 1 from public.competitions c where c.season_id = s.id and c.is_main);
  end if;

  update public.seasons s
     set status = 'active'
   where s.id = p_season_id
  returning s.* into v_row;

  -- Ingen rad: RLS stoppet skrivingen (ikke arrangør).
  if v_row.id is null then
    raise exception 'Bare arrangøren kan aktivere en turnering' using errcode = '42501';
  end if;
  -- Hovedturnering blir den av competitions_sync_season (033) når klubben ikke har
  -- en annen aktiv hovedturnering.
  return v_row;
end;
$$;
revoke all on function public.activate_season(uuid, boolean) from public, anon;
grant execute on function public.activate_season(uuid, boolean) to authenticated;


-- ===========================================================================
-- 6. AKTIVITET UTEN KLUBB
-- ===========================================================================
alter table public.activity alter column club_id drop not null;
do $$
begin
  if not exists (select 1 from pg_constraint
                 where conrelid = 'public.activity'::regclass and conname = 'activity_club_or_competition') then
    alter table public.activity add constraint activity_club_or_competition
      check (club_id is not null or competition_id is not null);
  end if;
end $$;

-- Push-køen er per klubb til steg 5 (push per turnering). Hendelser uten klubb
-- går derfor ikke i køen ennå. Fra 010, bare første linje i kroppen er ny.
create or replace function public.push_enqueue_activity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.club_id is null then
    return null;
  end if;
  if new.round_id is not null
     and exists (select 1 from public.rounds r where r.id = new.round_id and r.status = 'draft') then
    return null;
  end if;
  insert into public.push_queue (club_id, activity_id)
  values (new.club_id, new.id)
  on conflict do nothing;
  return null;
end;
$$;
revoke all on function public.push_enqueue_activity() from public, anon, authenticated;

-- Lesing: som før for klubbens medlemmer. I tillegg: hendelser uten klubb i en
-- turnering du kan se, uten mottakerliste, og bare for runder du kan se.
drop policy if exists activity_select on public.activity;
create policy activity_select on public.activity
  for select to authenticated using (
    (club_id is not null
     and public.is_club_member(club_id)
     and (recipients is null
          or public.my_member_id(club_id) = any (recipients)
          or actor_member_id = public.my_member_id(club_id)
          or public.is_club_organizer(club_id))
     and (round_id is null or public.can_read_round(round_id)))
    or
    (club_id is null
     and competition_id is not null
     and recipients is null
     and public.can_read_competition(competition_id)
     and (round_id is null or public.can_read_round(round_id)))
  );
-- activity_insert er uendret: is_club_member(club_id), som er usann uten klubb.
-- Hendelser uten klubb lages bare av serveren (security definer), fra steg 9.


-- ===========================================================================
-- 7. create_bet: «den aktive sesongen» er hovedturneringen
-- ===========================================================================
-- Fra 026, bare oppslaget uten kveld er endret: med flere aktive serier ville
-- select … into tatt en tilfeldig av dem. Veddemål per turnering kommer i steg 11.
create or replace function public.create_bet(
  p_club_id    uuid,
  p_round_id   uuid,
  p_event_id   uuid,
  p_question   text,
  p_condition  jsonb,
  p_against    uuid,
  p_side       text,
  p_points     integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me      uuid;
  v_round   public.rounds%rowtype;
  v_event   uuid := p_event_id;
  v_season  uuid;
  v_bet     public.bets%rowtype;
  v_stake   uuid;
  v_ids     uuid[];
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  v_me := public.my_member_id(p_club_id);
  if v_me is null then
    raise exception 'Du er ikke aktivt medlem av klubben' using errcode = '42501';
  end if;
  if p_question is null or char_length(btrim(p_question)) not between 4 and 140 then
    raise exception 'Skriv en tydelig påstand (4–140 tegn)' using errcode = '22023';
  end if;
  if not public.bet_condition_valid(p_condition) then
    raise exception 'Ugyldig vilkår' using errcode = '22023';
  end if;
  if p_condition is not null and p_round_id is null then
    raise exception 'Et vilkår må gjelde en runde' using errcode = '22023';
  end if;

  if p_round_id is not null then
    select * into v_round from public.rounds r where r.id = p_round_id and r.club_id = p_club_id;
    if not found or not public.can_read_round(p_round_id) then
      raise exception 'Fant ikke runden' using errcode = 'P0002';
    end if;
    if v_round.status = 'locked' then
      raise exception 'Runden er låst' using errcode = '55000';
    end if;
    v_event := v_round.event_id;
  end if;
  if v_event is not null then
    select e.season_id into v_season from public.events e where e.id = v_event and e.club_id = p_club_id;
    if not found then
      raise exception 'Fant ikke kvelden' using errcode = 'P0002';
    end if;
  else
    -- 034: flere serier kan være aktive. Uten kveld gjelder hovedturneringen.
    select s.id into v_season
      from public.seasons s
      join public.competitions c on c.season_id = s.id
     where s.club_id = p_club_id and s.status = 'active' and c.is_main;
  end if;
  if v_season is null then
    raise exception 'Veddemål krever en aktiv turnering med kvelden i terminlista' using errcode = '55000';
  end if;

  if p_against is not null then
    if p_against = v_me then
      raise exception 'Du kan ikke utfordre deg selv' using errcode = '22023';
    end if;
    if not exists (select 1 from public.club_members m
                   where m.id = p_against and m.club_id = p_club_id and m.status = 'active') then
      raise exception 'Spilleren er ikke med i klubben' using errcode = '23503';
    end if;
  end if;
  if p_condition is not null then
    select coalesce(array_agg(x::uuid), '{}') into v_ids
    from (select p_condition ->> k as x from unnest(array['player', 'a', 'b']) k) s
    where x is not null and x <> '';
    if exists (select 1 from unnest(v_ids) u
               where not exists (select 1 from public.round_players rp
                                 where rp.round_id = p_round_id and rp.member_id = u)) then
      raise exception 'Vilkåret nevner noen som ikke er med i runden' using errcode = '23503';
    end if;
  end if;

  insert into public.bets (club_id, season_id, event_id, round_id, creator_id, against_id, question, condition)
  values (p_club_id, v_season, v_event, p_round_id, v_me, p_against, btrim(p_question), p_condition)
  returning * into v_bet;

  -- Sperra og tak gjelder også første innsats. Feiler den, rulles veddemålet tilbake.
  v_stake := public.bet_insert_stake(v_bet, v_me, p_side, p_points);

  insert into public.activity (club_id, kind, category, data, event_id, round_id)
  values (p_club_id, case when p_against is null then 'bet_created' else 'bet_challenge' end, 'bet',
          jsonb_build_object('bet_id', v_bet.id, 'question', v_bet.question, 'against', p_against,
                             'side', p_side, 'points', p_points),
          v_event, p_round_id);

  return jsonb_build_object('bet_id', v_bet.id, 'stake_id', v_stake);
end;
$$;
revoke all on function public.create_bet(uuid, uuid, uuid, text, jsonb, uuid, text, integer) from public, anon;
grant execute on function public.create_bet(uuid, uuid, uuid, text, jsonb, uuid, text, integer) to authenticated;


-- ===========================================================================
-- KONTROLL (kjøres i samme transaksjon; feiler ved avvik)
-- ===========================================================================
do $$
declare
  v_fail text := '';
begin
  -- 1. De gamle reglene er borte, erstatningene står.
  if exists (select 1 from pg_indexes where schemaname = 'public'
             and indexname in ('rounds_one_active_per_club', 'seasons_one_active_per_club')) then
    v_fail := v_fail || ' 1a';
  end if;
  if exists (select 1 from pg_constraint where conname = 'events_one_per_date') then
    v_fail := v_fail || ' 1b';
  end if;
  -- 2. Båsgrensen er 99.
  if not exists (select 1 from pg_constraint where conname = 'round_players_bay_no_check'
                 and pg_get_constraintdef(oid) like '%99%') then
    v_fail := v_fail || ' 2';
  end if;
  -- 3. activate_season finnes bare med den nye signaturen, og anon kan ikke kalle den.
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = 'activate_season'
               and pg_get_function_identity_arguments(p.oid) = 'p_season_id uuid') then
    v_fail := v_fail || ' 3a';
  end if;
  if has_function_privilege('anon', 'public.activate_season(uuid, boolean)', 'execute') then
    v_fail := v_fail || ' 3b';
  end if;
  -- 4. Ingen aktivitet uten klubb finnes ennå, og alle rader oppfyller kravet.
  if exists (select 1 from public.activity where club_id is null) then
    v_fail := v_fail || ' 4';
  end if;
  -- 5. Golfgutu: høyst én aktiv hovedturnering per klubb (uendret).
  if exists (select club_id from public.competitions where is_main and status = 'active'
             group by club_id having count(*) > 1) then
    v_fail := v_fail || ' 5';
  end if;
  if v_fail <> '' then
    raise exception '034 kontroll feilet:%', v_fail;
  end if;
  raise notice '034 kontroll: 5 av 5';
end $$;

commit;

-- ===========================================================================
-- ETTERPÅ, FOR SEG: minste appbygg (når bygget med steg 1 er ute)
-- ===========================================================================
-- update public.app_config set value = '{"build": NN}'::jsonb where key = 'min_ios_build';

-- ===========================================================================
-- RULLEBAKKE (bare hvis ingen klubb har brukt de nye mulighetene ennå)
-- ===========================================================================
-- begin;
-- drop policy if exists activity_select on public.activity;
-- create policy activity_select on public.activity
--   for select to authenticated using (
--     public.is_club_member(club_id)
--     and (recipients is null
--          or public.my_member_id(club_id) = any (recipients)
--          or actor_member_id = public.my_member_id(club_id)
--          or public.is_club_organizer(club_id))
--     and (round_id is null or public.can_read_round(round_id)));
-- alter table public.activity drop constraint if exists activity_club_or_competition;
-- alter table public.activity alter column club_id set not null;
-- drop function if exists public.activate_season(uuid, boolean);
-- (gjenopprett activate_season(uuid) fra 026_turnering_tekster.sql)
-- alter table public.round_players drop constraint if exists round_players_bay_no_check;
-- alter table public.round_players add constraint round_players_bay_no_check check (bay_no between 1 and 12);
-- alter table public.events add constraint events_one_per_date unique (club_id, event_date);
-- create unique index seasons_one_active_per_club on public.seasons (club_id) where status = 'active';
-- create unique index rounds_one_active_per_club on public.rounds (club_id) where status = 'active';
-- commit;
