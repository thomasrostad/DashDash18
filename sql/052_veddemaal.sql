-- 052: veddemål overalt (gjennomføringsplanen steg 11). Godkjent og kjørt på test 12.10.2026.
--
-- Krever 001–051 (012 veddemål, 031–034 turneringer, 044 rettigheter og private-skjemaet,
-- 047 bets_guard_playoff, 048 rounds.rules_snapshot). Rører ikke runde-oppsettet (set_round_setup,
-- start_round, round_competitions).
--
-- Beslutningene (Thomas 11.10.2026, docs/vedd-per-turnering.md «Svar fra Thomas»):
--   * Veddemål er AV som standard og slås på per turnering i innstillingene. For enkeltrunder
--     velges det i oppsettet.
--   * Med i liga, cup, morro, private turneringer uten klubb (profiler) og løse runder.
--   * Poengbanken følger der veddemålene er slått på: én per turnering, én per runde for enkeltrunder.
--   * Oppgjøret gjøres av serveren med regelmotoren i TypeScript når runden låses.
--
-- Hva fila gjør:
--   1. NØKKELEN: bets.competition_id (→ competitions, cascade) og bets.round_scope (→ rounds,
--      cascade; banken til en enkeltrunde). Nøyaktig én av dem (bets_one_scope). Alle veddemål fra
--      før får competition_id fra sesongens speilede turneringsrad. season_id står for gamle bygg og
--      fylles fortsatt når turneringen er en sesong (trigger), så gamle bygg ser de nye veddemålene
--      i hovedturneringen. bets.club_id og season_id kan være tomme (turnering uten klubb, løs runde).
--      Enkle fremmednøkler ved siden av de sammensatte (round_id → rounds, bet_stakes.bet_id → bets),
--      fordi en sammensatt nøkkel med tom club_id ikke sjekkes.
--   2. PÅ OG AV: competitions.bets_enabled og rounds.bets_enabled (boolean, standard false). Egne
--      kolonner, ikke i rules: rules er regelsettet (tall motoren leser, skrevet i sin helhet av
--      «Tilpass reglene» og web-admin, også av gamle bygg som ikke kjenner flagget), mens på/av er en
--      innstilling som RPC-ene og RLS må lese billig, og en løs runde har ikke noe regelsett.
--      Tallene (startbeholdning, tak, forsprang, desimaler) står fortsatt i rules->'bets' (BetRules).
--      Etterfylling: turneringer som har veddemål i dag, og hovedturneringen (is_main) i klubber som
--      har veddemål, får true. En ny sesong (speilet turnering) arver true når klubben har en sesong
--      med veddemål på, så gamle bygg ikke mister Vedd ved sesongskifte.
--      Slås av og på med bets_set_enabled(turnering | runde, på): turneringens admin (rettigheten
--      tournaments, eier eller arrangør i staben) eller money; runden: is_round_organizer.
--      Av betyr: ingen nye veddemål. De som finnes, står, tar innsatser og gjøres opp som før.
--   3. PERSONER: bets.creator_profile_id, against_profile_id, resolved_by_profile og
--      bet_stakes.profile_id ved siden av medlemskolonnene (docs/vedd-per-turnering.md B).
--      bet_stakes: høyst én av member_id og profile_id, og nøyaktig én når innsatsen lages (trigger).
--      bet_stakes.person_key = den som satset (member_id eller profile_id) og blir stående når en
--      konto slettes (profile_id → null), så banken til de andre ikke endres.
--      Hvem er «deltaker» (private.bet_people):
--        klubbturnering: aktive medlemmer (entry = club), ellers påmeldte (competition_participants)
--        som medlem i klubben; påmeldte uten medlemskap i klubben som profil.
--        turnering uten klubb: påmeldte, alltid som profil.
--        enkeltrunde: klubbrunde: spillerne i runden (medlemmer); løs runde: deltakerne med profil.
--   4. BANKEN: bet_points_for(turnering, runde, medlem, profil) med samme regnestykke som 012
--      (hele poeng, resten til største innsats, så laveste person). Beløpene fra turneringens
--      rules->'bets' (runde: rounds.rules_snapshot->'bets'), ellers Golfgutu (1000). Appen spør med
--      bet_bank(turnering, runde, medlem = null, profil = null): uten person gjelder den som spør.
--      Gamle bet_points(sesong, medlem) står og gir samme tall for veddemålene fra før.
--   5. RPC-ER: create_bet_v2(turnering, runde, påstand, vilkår, mot medlem, mot profil, side, poeng).
--      Turnering: den som kan lese den (can_read_competition); runden må høre til turneringen
--      (kveld, competition_rounds, sesong). Runde alene: banken er rundens (round_scope), krever
--      rounds.bets_enabled. Bare deltakere kan vedde og bare når det er slått på.
--      place_bet_stake og resolve_bet tåler profiler (samme signatur). create_bet (gammel) er urørt;
--      triggeren fyller turneringen og stopper den når veddemål er av. bet_insert_stake (gammel)
--      kaller den nye.
--   6. OPPGJØR PÅ SERVEREN: bet_settle_queue(round_id). Når en runde låses og har åpne veddemål med
--      vilkår, legges den i køen (trigger), og låste runder med åpne veddemål legges inn nå.
--      Bare service_role: bet_settle_jobs(antall) henter jobbene med rundens rådata (samme form som
--      tavla_data) og veddemålene med regelsett; Edge Function bet-settle regner med motoren i
--      TypeScript og kaller settle_round_bets(runde, [{bet_id, verdict}]) eller bet_settle_failed.
--      settle_round_bets avgjør bare åpne veddemål med vilkår i en låst runde, void bare for hull,
--      slår og match (som settle_bet), skriver bet_resolved (auto) og merker jobben ferdig.
--      Arrangørens telefon (settle_bet, mark_bets_closed) virker som før for gamle bygg.
--
-- Én transaksjon. Kan kjøres flere ganger. Kontroll nederst (feiler ved avvik). Rullebakke nederst.

begin;

-- ===========================================================================
-- 1. KOLONNENE
-- ===========================================================================

alter table public.competitions add column if not exists bets_enabled boolean not null default false;
alter table public.rounds       add column if not exists bets_enabled boolean not null default false;
comment on column public.competitions.bets_enabled is
  'Veddemål i turneringen (052). Av som standard. Tallene står i rules->bets.';
comment on column public.rounds.bets_enabled is
  'Veddemål med egen bank i denne runden (052, enkeltrunder). Av som standard.';

alter table public.bets add column if not exists competition_id uuid;
alter table public.bets add column if not exists round_scope uuid;
alter table public.bets add column if not exists creator_profile_id uuid;
alter table public.bets add column if not exists against_profile_id uuid;
alter table public.bets add column if not exists resolved_by_profile uuid;
alter table public.bets alter column club_id drop not null;
alter table public.bets alter column season_id drop not null;

alter table public.bet_stakes add column if not exists profile_id uuid;
alter table public.bet_stakes add column if not exists person_key uuid;
alter table public.bet_stakes alter column member_id drop not null;
alter table public.bet_stakes alter column club_id drop not null;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'bets_competition_id_fkey' and conrelid = 'public.bets'::regclass) then
    alter table public.bets add constraint bets_competition_id_fkey
      foreign key (competition_id) references public.competitions (id) on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'bets_round_scope_fkey' and conrelid = 'public.bets'::regclass) then
    alter table public.bets add constraint bets_round_scope_fkey
      foreign key (round_scope) references public.rounds (id) on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'bets_round_id_fkey' and conrelid = 'public.bets'::regclass) then
    alter table public.bets add constraint bets_round_id_fkey
      foreign key (round_id) references public.rounds (id) on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'bets_creator_profile_fkey' and conrelid = 'public.bets'::regclass) then
    alter table public.bets add constraint bets_creator_profile_fkey
      foreign key (creator_profile_id) references public.profiles (id) on delete set null;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'bets_against_profile_fkey' and conrelid = 'public.bets'::regclass) then
    alter table public.bets add constraint bets_against_profile_fkey
      foreign key (against_profile_id) references public.profiles (id) on delete set null;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'bets_resolved_by_profile_fkey' and conrelid = 'public.bets'::regclass) then
    alter table public.bets add constraint bets_resolved_by_profile_fkey
      foreign key (resolved_by_profile) references public.profiles (id) on delete set null;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'bets_creator_one' and conrelid = 'public.bets'::regclass) then
    alter table public.bets add constraint bets_creator_one check (num_nonnulls(creator_id, creator_profile_id) <= 1);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'bets_against_one' and conrelid = 'public.bets'::regclass) then
    alter table public.bets add constraint bets_against_one check (num_nonnulls(against_id, against_profile_id) <= 1);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'bets_resolved_by_one' and conrelid = 'public.bets'::regclass) then
    alter table public.bets add constraint bets_resolved_by_one check (num_nonnulls(resolved_by, resolved_by_profile) <= 1);
  end if;

  if not exists (select 1 from pg_constraint where conname = 'bet_stakes_bet_id_fkey' and conrelid = 'public.bet_stakes'::regclass) then
    alter table public.bet_stakes add constraint bet_stakes_bet_id_fkey
      foreign key (bet_id) references public.bets (id) on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'bet_stakes_profile_fkey' and conrelid = 'public.bet_stakes'::regclass) then
    alter table public.bet_stakes add constraint bet_stakes_profile_fkey
      foreign key (profile_id) references public.profiles (id) on delete set null;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'bet_stakes_one_person' and conrelid = 'public.bet_stakes'::regclass) then
    alter table public.bet_stakes add constraint bet_stakes_one_person check (num_nonnulls(member_id, profile_id) <= 1);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'bet_stakes_member_needs_club' and conrelid = 'public.bet_stakes'::regclass) then
    alter table public.bet_stakes add constraint bet_stakes_member_needs_club check (member_id is null or club_id is not null);
  end if;
end $$;

-- --- Etterfylling ------------------------------------------------------------------
-- Alle veddemål fra før gjelder en sesong; turneringsraden er sesongens speil (031).
update public.bets b
   set competition_id = c.id
  from public.competitions c
 where b.competition_id is null and b.round_scope is null
   and c.season_id = b.season_id;

update public.bet_stakes s set person_key = s.member_id where s.person_key is null;

do $$
begin
  if exists (select 1 from public.bets where competition_id is null and round_scope is null) then
    raise exception '052: veddemål uten turnering etter etterfyllingen (sesong uten speilet turneringsrad)';
  end if;
  if exists (select 1 from public.bet_stakes where person_key is null) then
    raise exception '052: innsats uten person etter etterfyllingen';
  end if;
end $$;

alter table public.bet_stakes alter column person_key set not null;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'bets_one_scope' and conrelid = 'public.bets'::regclass) then
    alter table public.bets add constraint bets_one_scope check (num_nonnulls(competition_id, round_scope) = 1);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'bets_scope_round' and conrelid = 'public.bets'::regclass) then
    alter table public.bets add constraint bets_scope_round check (round_scope is null or round_id = round_scope);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'bet_stakes_person_key' and conrelid = 'public.bet_stakes'::regclass) then
    alter table public.bet_stakes add constraint bet_stakes_person_key
      check (person_key = coalesce(member_id, profile_id) or (member_id is null and profile_id is null));
  end if;
end $$;

create index if not exists bets_competition_idx on public.bets (competition_id, created_at desc) where competition_id is not null;
create index if not exists bets_round_scope_idx on public.bets (round_scope) where round_scope is not null;
create index if not exists bet_stakes_person_idx on public.bet_stakes (person_key);
create index if not exists bet_stakes_profile_idx on public.bet_stakes (profile_id) where profile_id is not null;

-- På for turneringene som har veddemål i dag, og hovedturneringen i klubber som bruker veddemål.
update public.competitions c
   set bets_enabled = true
 where not c.bets_enabled
   and (   exists (select 1 from public.bets b where b.competition_id = c.id)
        or (c.is_main and c.club_id is not null
            and exists (select 1 from public.bets b where b.club_id = c.club_id)));


-- ===========================================================================
-- 2. HJELPERE (private)
-- ===========================================================================

-- --- En regelverdi fra et rules->'bets'-objekt (samme regel som 012 bet_rule) ------------
create or replace function private.bet_rule_value(p_bets jsonb, p_key text, p_default integer)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case
    when p_bets ? p_key
      then case when jsonb_typeof(p_bets -> p_key) = 'number'
                then (p_bets ->> p_key)::numeric::integer end
    else p_default
  end;
$$;
revoke all on function private.bet_rule_value(jsonb, text, integer) from public, anon, authenticated;

-- --- rules->'bets' for banken: turneringens regelsett, ellers rundens øyeblikksbilde ------
create or replace function private.bet_scope_bets_rules(p_competition_id uuid, p_round_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_competition_id is not null then (select c.rules -> 'bets' from public.competitions c where c.id = p_competition_id)
    else (select r.rules_snapshot -> 'bets' from public.rounds r where r.id = p_round_id)
  end;
$$;
revoke all on function private.bet_scope_bets_rules(uuid, uuid) from public, anon, authenticated;

create or replace function private.bet_scope_rule(p_competition_id uuid, p_round_id uuid, p_key text, p_default integer)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select private.bet_rule_value(private.bet_scope_bets_rules(p_competition_id, p_round_id), p_key, p_default);
$$;
revoke all on function private.bet_scope_rule(uuid, uuid, text, integer) from public, anon, authenticated;

-- --- Hele regelsettet for oppgjøret (motoren dekoder det; tomt = Golfgutu) ------------------
create or replace function private.bet_scope_ruleset(p_competition_id uuid, p_round_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_competition_id is not null then (select c.rules from public.competitions c where c.id = p_competition_id)
    else (select r.rules_snapshot from public.rounds r where r.id = p_round_id)
  end;
$$;
revoke all on function private.bet_scope_ruleset(uuid, uuid) from public, anon, authenticated;

-- --- Deltakerne i en bank (turnering eller runde) -------------------------------------
-- Én rad per person: member_id (klubbmedlem) eller profile_id (profil), og innloggingen.
create or replace function private.bet_people(p_competition_id uuid, p_round_id uuid)
returns table (member_id uuid, profile_id uuid, user_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  with c as (select * from public.competitions where id = p_competition_id),
  r as (select * from public.rounds where id = p_round_id and p_competition_id is null),
  cp as (
    select p.member_id, p.profile_id from public.competition_participants p
     where p.competition_id = p_competition_id and p.status = 'active'
  ),
  people as (
    -- Klubbturnering: medlemmene i klubben (alle ved entry = club, ellers de påmeldte).
    select m.id as member_id, null::uuid as profile_id, m.user_id
      from c join public.club_members m on m.club_id = c.club_id and m.status = 'active'
     where c.club_id is not null
       and (   c.entry = 'club'
            or exists (select 1 from cp where cp.member_id = m.id)
            or (m.user_id is not null and exists (select 1 from cp where cp.profile_id = m.user_id)))
    union
    -- Påmeldte som ikke er aktive medlemmer i turneringens klubb: som profil.
    select null::uuid, x.uid, x.uid
      from c, (select coalesce(cp.profile_id, m2.user_id) as uid
                 from cp left join public.club_members m2 on m2.id = cp.member_id) x
     where x.uid is not null
       and not (c.club_id is not null
                and exists (select 1 from public.club_members m3
                             where m3.club_id = c.club_id and m3.status = 'active' and m3.user_id = x.uid))
    union
    -- Klubbrunde: spillerne i runden.
    select m.id, null::uuid, m.user_id
      from r join public.round_players rp on rp.round_id = r.id
             join public.club_members m on m.id = rp.member_id and m.club_id = r.club_id
     where r.club_id is not null and m.status = 'active'
    union
    -- Løs runde: deltakerne med profil.
    select null::uuid, pa.profile_id, pa.profile_id
      from r join public.round_participants pa on pa.round_id = r.id
     where r.club_id is null and pa.profile_id is not null
  )
  select distinct member_id, profile_id, user_id from people;
$$;
revoke all on function private.bet_people(uuid, uuid) from public, anon, authenticated;

-- --- Den som spør, som person i banken (medlem foran profil). Tom = ikke deltaker. ----------
create or replace function private.bet_me(p_competition_id uuid, p_round_id uuid,
                                          out member_id uuid, out profile_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  select p.member_id, p.profile_id
    from private.bet_people(p_competition_id, p_round_id) p
   where auth.uid() is not null and p.user_id = auth.uid()
   order by p.member_id is null
   limit 1;
$$;
revoke all on function private.bet_me(uuid, uuid) from public, anon, authenticated;

-- --- Hører runden til turneringen? ------------------------------------------------------
create or replace function private.round_in_competition(p_round_id uuid, p_competition_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.competition_rounds cr
                  where cr.round_id = p_round_id and cr.competition_id = p_competition_id)
      or exists (select 1 from public.rounds r join public.events e on e.id = r.event_id
                   join public.competitions c on c.id = p_competition_id
                  where r.id = p_round_id
                    and (e.competition_id = c.id or (c.season_id is not null and e.season_id = c.season_id)));
$$;
revoke all on function private.round_in_competition(uuid, uuid) from public, anon, authenticated;

-- --- Kan den som spør se veddemålet (samme som lesepolicyen)? ------------------------------
create or replace function private.bet_visible(p_bet public.bets)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (   (p_bet.club_id is not null and public.is_club_member(p_bet.club_id))
          or (p_bet.competition_id is not null and public.can_read_competition(p_bet.competition_id))
          or (p_bet.round_scope is not null and public.can_read_round(p_bet.round_scope)))
     and (p_bet.round_id is null or public.can_read_round(p_bet.round_id));
$$;
revoke all on function private.bet_visible(public.bets) from public, anon, authenticated;


-- ===========================================================================
-- 3. TRIGGERE
-- ===========================================================================

-- --- bets: fyll turneringen og sesongen, sjekk klubben og at veddemål er på ----------------
-- Gjelder alle veier inn (create_bet fra gamle bygg og create_bet_v2).
create or replace function private.bets_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_c public.competitions%rowtype;
  v_r public.rounds%rowtype;
begin
  if new.competition_id is null and new.round_scope is null and new.season_id is not null then
    select c.id into new.competition_id from public.competitions c where c.season_id = new.season_id;
  end if;
  if new.competition_id is not null then
    select * into v_c from public.competitions c where c.id = new.competition_id;
    if not found then
      raise exception 'Fant ikke turneringen' using errcode = 'P0002';
    end if;
    if v_c.club_id is distinct from new.club_id then
      raise exception 'Veddemålet må høre til turneringens klubb' using errcode = '22023';
    end if;
    if new.season_id is null then
      new.season_id := v_c.season_id;
    end if;
    if not v_c.bets_enabled then
      raise exception 'Veddemål er ikke slått på i turneringen' using errcode = '55000';
    end if;
  elsif new.round_scope is not null then
    select * into v_r from public.rounds r where r.id = new.round_scope;
    if not found then
      raise exception 'Fant ikke runden' using errcode = 'P0002';
    end if;
    if v_r.club_id is distinct from new.club_id then
      raise exception 'Veddemålet må høre til rundens klubb' using errcode = '22023';
    end if;
    new.round_id := coalesce(new.round_id, new.round_scope);
    if not v_r.bets_enabled then
      raise exception 'Veddemål er ikke slått på i runden' using errcode = '55000';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.bets_before_insert() from public, anon, authenticated;

drop trigger if exists bets_before_insert on public.bets;
create trigger bets_before_insert
  before insert on public.bets
  for each row execute function private.bets_before_insert();

-- --- bet_stakes: nøyaktig én person når innsatsen lages (begge tomme = slettet konto senere) ----
create or replace function private.bet_stakes_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if num_nonnulls(new.member_id, new.profile_id) <> 1 then
    raise exception 'En innsats må ha nøyaktig én av medlem og profil' using errcode = '23514';
  end if;
  new.person_key := coalesce(new.member_id, new.profile_id);
  return new;
end;
$$;
revoke all on function private.bet_stakes_before_insert() from public, anon, authenticated;

drop trigger if exists bet_stakes_before_insert on public.bet_stakes;
create trigger bet_stakes_before_insert
  before insert on public.bet_stakes
  for each row execute function private.bet_stakes_before_insert();

-- --- competitions: en ny sesong arver «på» når klubben har en sesong med veddemål på -------
create or replace function private.competitions_bets_inherit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.season_id is not null and new.club_id is not null and not new.bets_enabled
     and exists (select 1 from public.competitions c
                  where c.club_id = new.club_id and c.season_id is not null and c.bets_enabled) then
    new.bets_enabled := true;
  end if;
  return new;
end;
$$;
revoke all on function private.competitions_bets_inherit() from public, anon, authenticated;

drop trigger if exists competitions_bets_inherit on public.competitions;
create trigger competitions_bets_inherit
  before insert on public.competitions
  for each row execute function private.competitions_bets_inherit();


-- ===========================================================================
-- 4. BANKEN
-- ===========================================================================

-- --- bet_points_for: netto, stående og ledig for én person i én bank -----------------------
-- Samme regnestykke som 012 (bet_points_for(sesong, medlem)), per person (person_key).
create or replace function public.bet_points_for(p_competition_id uuid, p_round_id uuid,
                                                 p_member_id uuid, p_profile_id uuid)
returns table (net numeric, at_stake numeric, balance numeric, available numeric)
language sql
stable
security definer
set search_path = ''
as $$
  with me as (select coalesce(p_member_id, p_profile_id) as key),
  scope as (
    select b.id, b.status, b.resolution from public.bets b
     where (p_competition_id is not null and b.competition_id = p_competition_id)
        or (p_competition_id is null and b.round_scope = p_round_id)
  ),
  d as (
    select greatest(0, least(2, coalesce(private.bet_scope_rule(p_competition_id, p_round_id, 'payoutDecimals', 0), 0))) as decimals
  ),
  sc as (select d.decimals, (10 ^ d.decimals)::bigint as scale from d),
  b as (select id, resolution from scope where status = 'resolved'),
  per as (
    select s.bet_id, s.person_key, sum(s.points)::bigint as pts, bool_and(s.side = b.resolution) as won
      from public.bet_stakes s join b on b.id = s.bet_id
     group by s.bet_id, s.person_key
  ),
  pools as (
    select bet_id,
           coalesce(sum(pts) filter (where won), 0)::bigint as win,
           coalesce(sum(pts) filter (where not won), 0)::bigint as lose
      from per group by bet_id
  ),
  w as (
    select p.bet_id, p.person_key, p.pts,
           (2 * p.pts * pl.lose * sc.scale + pl.win) / (2 * pl.win) as units,
           pl.lose * sc.scale as total
      from per p join pools pl on pl.bet_id = p.bet_id cross join sc
     where p.won and pl.win > 0 and pl.lose > 0
  ),
  r as (
    select w.person_key, w.units,
           w.total - sum(w.units) over (partition by w.bet_id) as rest,
           row_number() over (partition by w.bet_id order by w.pts desc, w.person_key) as rn
      from w
  ),
  mine as (
    select round((r.units + case when r.rn <= abs(r.rest) then sign(r.rest)::bigint else 0 end)::numeric / sc.scale,
                 sc.decimals) as amount
      from r cross join sc cross join me
     where r.person_key = me.key
    union all
    select -p.pts::numeric
      from per p join pools pl on pl.bet_id = p.bet_id cross join me
     where p.person_key = me.key and not p.won and pl.win > 0 and pl.lose > 0
  ),
  n as (select coalesce(sum(amount), 0)::numeric as net from mine),
  st as (
    select coalesce(sum(s.points), 0)::numeric as at_stake
      from public.bet_stakes s join scope o on o.id = s.bet_id cross join me
     where o.status = 'open' and s.person_key = me.key
  ),
  bank as (select private.bet_scope_rule(p_competition_id, p_round_id, 'startingPoints', 1000) as start)
  select n.net, st.at_stake, bank.start + n.net, bank.start + n.net - st.at_stake
    from n, st, bank;
$$;
revoke all on function public.bet_points_for(uuid, uuid, uuid, uuid) from public, anon, authenticated;

-- --- bet_bank: det appen spør om. Uten person: den som spør. -------------------------------
create or replace function public.bet_bank(p_competition_id uuid, p_round_id uuid,
                                           p_member_id uuid default null, p_profile_id uuid default null)
returns table (net numeric, at_stake numeric, balance numeric, available numeric)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_member  uuid := p_member_id;
  v_profile uuid := p_profile_id;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if num_nonnulls(p_competition_id, p_round_id) <> 1 then
    raise exception 'Velg turnering eller runde' using errcode = '22023';
  end if;
  if (p_competition_id is not null and not public.can_read_competition(p_competition_id))
     or (p_round_id is not null and not public.can_read_round(p_round_id)) then
    raise exception 'Fant ikke banken' using errcode = 'P0002';
  end if;
  if v_member is null and v_profile is null then
    select m.member_id, m.profile_id into v_member, v_profile from private.bet_me(p_competition_id, p_round_id) m;
    if v_member is null and v_profile is null then
      raise exception 'Du er ikke med her' using errcode = 'P0002';
    end if;
  elsif v_member is not null and v_profile is not null then
    raise exception 'Velg medlem eller profil' using errcode = '22023';
  end if;
  return query select * from public.bet_points_for(p_competition_id, p_round_id, v_member, v_profile);
end;
$$;
revoke all on function public.bet_bank(uuid, uuid, uuid, uuid) from public, anon;
grant execute on function public.bet_bank(uuid, uuid, uuid, uuid) to authenticated;


-- ===========================================================================
-- 5. INNSATSEN OG SPERRA
-- ===========================================================================

-- --- bet_accepts_stakes: som 012, men forspranget fra bankens regelsett --------------------
create or replace function public.bet_accepts_stakes(p_bet_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_bet     public.bets%rowtype;
  v_status  text;
  v_open    integer;
  v_members uuid[];
begin
  select * into v_bet from public.bets where id = p_bet_id;
  if not found or v_bet.status <> 'open' or v_bet.closed_at is not null then
    return false;
  end if;
  if v_bet.condition is null then
    return true;
  end if;
  select r.status into v_status from public.rounds r where r.id = v_bet.round_id;
  if v_status is null then
    return true;
  end if;
  if v_status = 'locked' then
    return false;
  end if;
  if v_bet.condition ->> 'kind' in ('birdie', 'par', 'hole') then
    select coalesce(array_agg(x::uuid), '{}') into v_members
    from (select v_bet.condition ->> k as x from unnest(array['player', 'a', 'b']) k) s
    where x is not null and x <> '';
    v_open := public.bet_first_open_hole(v_bet.round_id, v_members,
                coalesce(private.bet_scope_rule(v_bet.competition_id, v_bet.round_scope, 'lockAheadHoles', 1), 1));
    return v_open is not null and (v_bet.condition ->> 'hole')::integer >= v_open;
  end if;
  return not exists (select 1 from public.hole_scores hs where hs.round_id = v_bet.round_id);
end;
$$;
revoke all on function public.bet_accepts_stakes(uuid) from public, anon;
grant execute on function public.bet_accepts_stakes(uuid) to authenticated;

-- --- private.bet_add_stake: én innsats med alle sjekkene (medlem eller profil) --------------
-- Låser personens bank (turnering eller runde), så to innsatser samtidig ikke bruker de samme
-- ledige poengene.
create or replace function private.bet_add_stake(p_bet public.bets, p_member_id uuid, p_profile_id uuid,
                                                 p_side text, p_points integer)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key  uuid := coalesce(p_member_id, p_profile_id);
  v_max  integer;
  v_mine integer;
  v_side text;
  v_free numeric;
  v_id   uuid;
begin
  if num_nonnulls(p_member_id, p_profile_id) <> 1 then
    raise exception 'Bare deltakerne kan vedde' using errcode = '42501';
  end if;
  if p_side is null or p_side not in ('yes', 'no') then
    raise exception 'Velg JA eller NEI' using errcode = '22023';
  end if;
  if p_points is null or p_points < 1 then
    raise exception 'Innsatsen må være minst 1 poeng' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'bet_bank:' || coalesce(p_bet.competition_id, p_bet.round_scope) || ':' || v_key, 0));

  if not public.bet_accepts_stakes(p_bet.id) then
    raise exception 'Veddemålet tar ikke imot innsatser nå: utfallet har begynt å bli kjent'
      using errcode = '55000';
  end if;

  select coalesce(sum(s.points), 0), min(s.side) into v_mine, v_side
    from public.bet_stakes s where s.bet_id = p_bet.id and s.person_key = v_key;
  if v_side is not null and v_side <> p_side then
    raise exception 'Du har alt satset på den andre siden' using errcode = '22023';
  end if;
  v_max := coalesce(private.bet_scope_rule(p_bet.competition_id, p_bet.round_scope, 'maxStakePerBet', 200), 200);
  if v_mine + p_points > v_max then
    raise exception 'Maks % poeng per veddemål. Du har % på det fra før.', v_max, v_mine
      using errcode = '22023';
  end if;
  select available into v_free
    from public.bet_points_for(p_bet.competition_id, p_bet.round_scope, p_member_id, p_profile_id);
  if v_free is not null and p_points > v_free then
    raise exception 'Du har % ledige poeng', greatest(v_free, 0)::integer using errcode = '22023';
  end if;

  insert into public.bet_stakes (bet_id, club_id, member_id, profile_id, person_key, side, points)
  values (p_bet.id, p_bet.club_id, p_member_id, p_profile_id, v_key, p_side, p_points)
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function private.bet_add_stake(public.bets, uuid, uuid, text, integer) from public, anon, authenticated;

-- --- bet_insert_stake (012): gamle create_bet kaller den; nå med den nye banken -------------
create or replace function public.bet_insert_stake(p_bet public.bets, p_member_id uuid, p_side text, p_points integer)
returns uuid
language sql
security definer
set search_path = ''
as $$
  select private.bet_add_stake(p_bet, p_member_id, null, p_side, p_points);
$$;
revoke all on function public.bet_insert_stake(public.bets, uuid, text, integer) from public, anon, authenticated;


-- ===========================================================================
-- 6. RPC-ENE FOR APPEN
-- ===========================================================================

-- --- bets_set_enabled: slå veddemål på eller av i en turnering eller en runde ----------------
create or replace function public.bets_set_enabled(p_competition_id uuid, p_round_id uuid, p_enabled boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_club uuid;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if num_nonnulls(p_competition_id, p_round_id) <> 1 or p_enabled is null then
    raise exception 'Velg turnering eller runde, og på eller av' using errcode = '22023';
  end if;
  if p_competition_id is not null then
    select c.club_id into v_club from public.competitions c where c.id = p_competition_id;
    if not found or not public.can_read_competition(p_competition_id) then
      raise exception 'Fant ikke turneringen' using errcode = 'P0002';
    end if;
    if not (public.is_competition_admin(p_competition_id)
            or (v_club is not null and private.has_club_right(v_club, 'money'))) then
      raise exception 'Bare arrangøren slår veddemål av og på' using errcode = '42501';
    end if;
    update public.competitions set bets_enabled = p_enabled
     where id = p_competition_id and bets_enabled is distinct from p_enabled;
  else
    if not exists (select 1 from public.rounds r where r.id = p_round_id) or not public.can_read_round(p_round_id) then
      raise exception 'Fant ikke runden' using errcode = 'P0002';
    end if;
    if not public.is_round_organizer(p_round_id) then
      raise exception 'Bare arrangøren slår veddemål av og på' using errcode = '42501';
    end if;
    update public.rounds set bets_enabled = p_enabled
     where id = p_round_id and bets_enabled is distinct from p_enabled;
  end if;
  return p_enabled;
end;
$$;
revoke all on function public.bets_set_enabled(uuid, uuid, boolean) from public, anon;
grant execute on function public.bets_set_enabled(uuid, uuid, boolean) to authenticated;

-- --- create_bet_v2: veddemålet og din første innsats i en turnering eller en runde ----------
-- p_competition_id: turneringens bank (runden, om gitt, må høre til turneringen). Uten turnering:
-- rundens egen bank (enkeltrunde). Mot: et medlem eller en profil i samme bank.
create or replace function public.create_bet_v2(
  p_competition_id  uuid,
  p_round_id        uuid,
  p_question        text,
  p_condition       jsonb,
  p_against_member  uuid,
  p_against_profile uuid,
  p_side            text,
  p_points          integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_c       public.competitions%rowtype;
  v_round   public.rounds%rowtype;
  v_club    uuid;
  v_event   uuid;
  v_member  uuid;
  v_profile uuid;
  v_bet     public.bets%rowtype;
  v_stake   uuid;
  v_ids     uuid[];
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
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
  if p_competition_id is null and p_round_id is null then
    raise exception 'Velg turnering eller runde' using errcode = '22023';
  end if;
  if p_against_member is not null and p_against_profile is not null then
    raise exception 'Velg én du vedder mot' using errcode = '22023';
  end if;

  if p_round_id is not null then
    select * into v_round from public.rounds r where r.id = p_round_id;
    if not found or not public.can_read_round(p_round_id) then
      raise exception 'Fant ikke runden' using errcode = 'P0002';
    end if;
    if v_round.status = 'locked' then
      raise exception 'Runden er låst' using errcode = '55000';
    end if;
    v_event := v_round.event_id;
  end if;

  if p_competition_id is not null then
    select * into v_c from public.competitions c where c.id = p_competition_id;
    if not found or not public.can_read_competition(p_competition_id) then
      raise exception 'Fant ikke turneringen' using errcode = 'P0002';
    end if;
    if p_round_id is not null and not private.round_in_competition(p_round_id, p_competition_id) then
      raise exception 'Runden hører ikke til turneringen' using errcode = '22023';
    end if;
    if not v_c.bets_enabled then
      raise exception 'Veddemål er ikke slått på i turneringen' using errcode = '55000';
    end if;
    v_club := v_c.club_id;
    if v_club is null then
      v_event := null;   -- en kveld hører alltid til en klubb
    end if;
  else
    if not v_round.bets_enabled then
      raise exception 'Veddemål er ikke slått på i runden' using errcode = '55000';
    end if;
    v_club := v_round.club_id;
  end if;

  select m.member_id, m.profile_id into v_member, v_profile
    from private.bet_me(p_competition_id, case when p_competition_id is null then p_round_id end) m;
  if v_member is null and v_profile is null then
    raise exception 'Bare deltakerne kan vedde' using errcode = '42501';
  end if;

  if p_against_member is not null or p_against_profile is not null then
    if p_against_member = v_member or p_against_profile = v_profile
       or p_against_profile = auth.uid() then
      raise exception 'Du kan ikke utfordre deg selv' using errcode = '22023';
    end if;
    if not exists (select 1 from private.bet_people(p_competition_id, case when p_competition_id is null then p_round_id end) p
                    where (p_against_member is not null and p.member_id = p_against_member)
                       or (p_against_profile is not null and p.profile_id = p_against_profile)) then
      raise exception 'Spilleren er ikke med her' using errcode = '23503';
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

  insert into public.bets (club_id, competition_id, round_scope, event_id, round_id,
                           creator_id, creator_profile_id, against_id, against_profile_id, question, condition)
  values (v_club, p_competition_id, case when p_competition_id is null then p_round_id end, v_event, p_round_id,
          v_member, v_profile, p_against_member, p_against_profile, btrim(p_question), p_condition)
  returning * into v_bet;

  v_stake := private.bet_add_stake(v_bet, v_member, v_profile, p_side, p_points);

  -- Aktivitet (og push) når det finnes en klubb eller turnering å legge den i.
  if v_bet.club_id is not null or v_bet.competition_id is not null then
    insert into public.activity (club_id, competition_id, kind, category, data, event_id, round_id)
    values (v_bet.club_id, v_bet.competition_id,
            case when num_nonnulls(p_against_member, p_against_profile) = 0 then 'bet_created' else 'bet_challenge' end,
            'bet',
            jsonb_strip_nulls(jsonb_build_object('bet_id', v_bet.id, 'question', v_bet.question,
                                                 'against', p_against_member, 'against_profile', p_against_profile,
                                                 'side', p_side, 'points', p_points)),
            v_bet.event_id, v_bet.round_id);
  end if;

  return jsonb_build_object('bet_id', v_bet.id, 'stake_id', v_stake,
                            'competition_id', v_bet.competition_id, 'round_scope', v_bet.round_scope);
end;
$$;
revoke all on function public.create_bet_v2(uuid, uuid, text, jsonb, uuid, uuid, text, integer) from public, anon;
grant execute on function public.create_bet_v2(uuid, uuid, text, jsonb, uuid, uuid, text, integer) to authenticated;

-- --- place_bet_stake (012): samme signatur, nå for alle deltakerne i banken -----------------
create or replace function public.place_bet_stake(p_bet_id uuid, p_side text, p_points integer)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_bet     public.bets%rowtype;
  v_member  uuid;
  v_profile uuid;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select * into v_bet from public.bets b where b.id = p_bet_id for update;
  if not found or not private.bet_visible(v_bet) then
    raise exception 'Fant ikke veddemålet' using errcode = 'P0002';
  end if;
  select m.member_id, m.profile_id into v_member, v_profile
    from private.bet_me(v_bet.competition_id, v_bet.round_scope) m;
  return private.bet_add_stake(v_bet, v_member, v_profile, p_side, p_points);
end;
$$;
revoke all on function public.place_bet_stake(uuid, text, integer) from public, anon;
grant execute on function public.place_bet_stake(uuid, text, integer) to authenticated;

-- --- resolve_bet (044): samme signatur. Uten klubb: turneringens admin eller rundens eier ----
create or replace function public.resolve_bet(p_bet_id uuid, p_resolution text)
returns public.bets
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_bet  public.bets%rowtype;
  v_me   uuid;
  v_ok   boolean;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if p_resolution is null or p_resolution not in ('yes', 'no', 'void') then
    raise exception 'Utfallet må være yes, no eller void' using errcode = '22023';
  end if;
  select * into v_bet from public.bets b where b.id = p_bet_id for update;
  if not found or not private.bet_visible(v_bet) then
    raise exception 'Fant ikke veddemålet' using errcode = 'P0002';
  end if;
  v_ok := case
            when v_bet.club_id is not null then private.has_club_right(v_bet.club_id, 'money')
            when v_bet.competition_id is not null then public.is_competition_admin(v_bet.competition_id)
            else public.is_round_organizer(v_bet.round_scope)
          end;
  if not coalesce(v_ok, false) then
    raise exception 'Bare arrangøren avgjør veddemål' using errcode = '42501';
  end if;
  if v_bet.status <> 'open' then
    raise exception 'Veddemålet er alt avgjort' using errcode = '55000';
  end if;
  v_me := case when v_bet.club_id is not null then public.my_member_id(v_bet.club_id) end;
  if exists (select 1 from public.bet_stakes s
              where s.bet_id = p_bet_id
                and ((v_me is not null and s.member_id = v_me) or s.profile_id = auth.uid())) then
    raise exception 'Du har satset på dette veddemålet og kan ikke avgjøre det. En annen arrangør må gjøre det.'
      using errcode = '55000';
  end if;

  update public.bets b
     set status              = case when p_resolution = 'void' then 'void' else 'resolved' end,
         resolution          = case when p_resolution = 'void' then null else p_resolution end,
         resolved_by         = v_me,
         resolved_by_profile = case when v_me is null then auth.uid() end,
         resolved_at         = now(),
         closed_at           = coalesce(b.closed_at, now())
   where b.id = p_bet_id
  returning * into v_bet;

  if v_bet.club_id is not null or v_bet.competition_id is not null then
    insert into public.activity (club_id, competition_id, kind, category, data, event_id, round_id)
    values (v_bet.club_id, v_bet.competition_id, 'bet_resolved', 'bet',
            jsonb_build_object('bet_id', v_bet.id, 'question', v_bet.question, 'resolution', p_resolution),
            v_bet.event_id, v_bet.round_id);
  end if;
  return v_bet;
end;
$$;
revoke all on function public.resolve_bet(uuid, text) from public, anon;
grant execute on function public.resolve_bet(uuid, text) to authenticated, service_role;


-- ===========================================================================
-- 7. LESING (RLS)
-- ===========================================================================
drop policy if exists bets_select on public.bets;
create policy bets_select on public.bets
  for select to authenticated
  using (
    (   (club_id is not null and public.is_club_member(club_id))
     or (competition_id is not null and public.can_read_competition(competition_id))
     or (round_scope is not null and public.can_read_round(round_scope)))
    and (round_id is null or public.can_read_round(round_id))
  );
-- bet_stakes_select (012) står: en innsats ses når veddemålet ses.


-- ===========================================================================
-- 8. OPPGJØR PÅ SERVEREN
-- ===========================================================================

create table if not exists public.bet_settle_queue (
  round_id    uuid primary key references public.rounds (id) on delete cascade,
  enqueued_at timestamptz not null default now(),
  claimed_at  timestamptz,
  attempts    integer not null default 0,
  last_error  text check (last_error is null or char_length(last_error) <= 500),
  done_at     timestamptz
);
comment on table public.bet_settle_queue is
  'Låste runder med åpne veddemål med vilkår (052). Bare service_role (Edge Function bet-settle).';
create index if not exists bet_settle_queue_pending_idx on public.bet_settle_queue (enqueued_at) where done_at is null;
alter table public.bet_settle_queue enable row level security;
revoke all on table public.bet_settle_queue from public, anon, authenticated;
grant all on table public.bet_settle_queue to service_role;

-- --- Køen: runden låses (og har åpne veddemål med vilkår) ----------------------------------
create or replace function private.bet_settle_enqueue()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'locked' and old.status is distinct from 'locked'
     and exists (select 1 from public.bets b
                  where b.round_id = new.id and b.status = 'open' and b.condition is not null) then
    insert into public.bet_settle_queue (round_id) values (new.id)
    on conflict (round_id) do update
      set enqueued_at = now(), claimed_at = null, attempts = 0, last_error = null, done_at = null;
  end if;
  return null;
end;
$$;
revoke all on function private.bet_settle_enqueue() from public, anon, authenticated;

drop trigger if exists rounds_bet_settle_enqueue on public.rounds;
create trigger rounds_bet_settle_enqueue
  after update of status on public.rounds
  for each row when (new.status = 'locked' and old.status is distinct from 'locked')
  execute function private.bet_settle_enqueue();

-- Runder som alt er låst med åpne veddemål med vilkår.
insert into public.bet_settle_queue (round_id)
select distinct b.round_id
  from public.bets b join public.rounds r on r.id = b.round_id
 where r.status = 'locked' and b.status = 'open' and b.condition is not null
on conflict (round_id) do nothing;

-- --- bet_settle_jobs: henter og reserverer jobbene, med rådata og veddemål -----------------
-- data har samme form som tavla_data (én runde), så motoren i TypeScript kan bruke
-- decodeTavlaData/makeSnapshot. Hvert veddemål har sitt regelsett (turneringens eller rundens).
-- En jobb som ikke er ferdig, kan hentes igjen etter fem minutter, høyst fem forsøk.
create or replace function public.bet_settle_jobs(p_limit integer default 10)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ids uuid[];
  v_out jsonb := '[]';
  v_r   uuid;
  v_courses uuid[];
begin
  -- Runder som ikke lenger er låst (låst opp igjen): ferdig nå, kommer tilbake ved neste låsing.
  update public.bet_settle_queue q set done_at = now(), claimed_at = null
   where q.done_at is null
     and not exists (select 1 from public.rounds r where r.id = q.round_id and r.status = 'locked');

  with picked as (
    select q.round_id from public.bet_settle_queue q
     where q.done_at is null and q.attempts < 5
       and (q.claimed_at is null or q.claimed_at < now() - interval '5 minutes')
     order by q.enqueued_at, q.round_id
     limit greatest(1, least(coalesce(p_limit, 10), 50))
     for update skip locked
  ),
  upd as (
    update public.bet_settle_queue q
       set claimed_at = now(), attempts = q.attempts + 1
      from picked where q.round_id = picked.round_id
    returning q.round_id, q.enqueued_at
  )
  select coalesce(array_agg(upd.round_id order by upd.enqueued_at, upd.round_id), '{}') into v_ids from upd;

  foreach v_r in array v_ids loop
    select coalesce(array_agg(r.course_id), '{}') into v_courses
      from public.rounds r where r.id = v_r and r.course_id is not null;
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'round_id', v_r,
      'attempts', (select q.attempts from public.bet_settle_queue q where q.round_id = v_r),
      'data', jsonb_build_object(
        'events', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
            select e.id, e.club_id, e.season_id, e.event_date, e.start_time, e.venue, e.note
              from public.events e join public.rounds r on r.event_id = e.id where r.id = v_r) x),
        'members', '[]'::jsonb,
        'rounds', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
            select r.id, r.club_id, r.event_id, r.course_id, r.round_no, r.name, r.status, r.hole_count,
                   r.first_hole, r.tee_time, r.format, r.handicap_allowance, r.external_handicap, r.weight,
                   r.ld_enabled, r.ld_hole_index, r.kp_enabled, r.kp_hole_index, r.cut_rule, r.cut_after,
                   r.par_confirmed_by, r.par_confirmed_at, r.started_at, r.locked_at, r.venue,
                   r.tee_id, r.tee_name, r.course_rating, r.slope_rating, r.tee_par,
                   r.counts, r.points_table, r.hide_last_holes, r.kind, r.playoff_for, r.playoff_holes,
                   r.rules_snapshot, r.holes_snapshot, r.snapshot_at, r.snapshot_source
              from public.rounds r where r.id = v_r) x),
        'round_holes', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
            select h.round_id, h.hole_index, h.par, h.stroke_index, h.length_m
              from public.round_holes h where h.round_id = v_r) x),
        'players', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
            select p.round_id, p.member_id, p.club_id, p.handicap_index, p.seed_group, p.playing_handicap,
                   p.bay_no, p.is_marker, p.team_no, p.side
              from public.round_players p where p.round_id = v_r) x),
        'matches', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
            select m.round_id, m.match_no, m.player_a, m.player_b, m.player_c, m.team_a, m.team_b, m.result
              from public.round_matches m where m.round_id = v_r) x),
        'claims', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
            select c.id, c.round_id, c.member_id, c.kind, c.meters, c.hole_index, c.created_at
              from public.side_claims c where c.round_id = v_r) x),
        'courses', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
            select c.id, c.club_id, c.name, c.external_name, c.course_rating, c.slope_rating, c.in_use,
                   c.confirmed_by, c.confirmed_at
              from public.courses c where c.id = any (v_courses)) x),
        'course_holes', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
            select h.course_id, h.hole_number, h.par, h.stroke_index, h.length_m
              from public.course_holes h where h.course_id = any (v_courses)) x),
        'scores', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
            select s.round_id, s.member_id, s.hole_index, s.strokes, s.recorded_at, s.updated_by, s.updated_at
              from public.hole_scores s where s.round_id = v_r) x)),
      'bets', (select coalesce(jsonb_agg(jsonb_build_object(
                  'id', b.id, 'condition', b.condition, 'closed_at', b.closed_at,
                  'rules', private.bet_scope_ruleset(b.competition_id, b.round_scope)) order by b.created_at, b.id), '[]')
                 from public.bets b
                where b.round_id = v_r and b.status = 'open' and b.condition is not null)
    ));
  end loop;
  return v_out;
end;
$$;
revoke all on function public.bet_settle_jobs(integer) from public, anon, authenticated;
grant execute on function public.bet_settle_jobs(integer) to service_role;

-- --- settle_round_bets: serverens oppgjør av én låst runde --------------------------------
-- p_results: [{"bet_id": uuid, "verdict": "yes"|"no"|"void"}], høyst 500. Veddemål som alt er
-- avgjort (arrangøren rakk det), eller ikke hører til runden, hoppes over (skipped). Det som står
-- åpent etterpå, avgjør arrangøren for hånd. Jobben er ferdig etter kallet.
create or replace function public.settle_round_bets(p_round_id uuid, p_results jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status  text;
  v_item    record;
  v_bet     public.bets%rowtype;
  v_settled integer := 0;
  v_skipped integer := 0;
  v_left    integer;
begin
  select r.status into v_status from public.rounds r where r.id = p_round_id;
  if v_status is null then
    raise exception 'Fant ikke runden' using errcode = 'P0002';
  end if;
  if v_status <> 'locked' then
    raise exception 'Runden er ikke låst' using errcode = '55000';
  end if;
  if p_results is null or jsonb_typeof(p_results) <> 'array' or jsonb_array_length(p_results) > 500 then
    raise exception 'Resultatene må være en liste (høyst 500)' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_array_elements(p_results) e
              where jsonb_typeof(e) <> 'object'
                 or coalesce(e ->> 'bet_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 or coalesce(e ->> 'verdict', '') not in ('yes', 'no', 'void')) then
    raise exception 'Hvert resultat trenger bet_id og verdict (yes, no eller void)' using errcode = '22023';
  end if;

  for v_item in
    select distinct on ((e ->> 'bet_id')::uuid) (e ->> 'bet_id')::uuid as bet_id, e ->> 'verdict' as verdict
      from jsonb_array_elements(p_results) e
     order by (e ->> 'bet_id')::uuid
  loop
    select * into v_bet from public.bets b where b.id = v_item.bet_id for update;
    if not found or v_bet.round_id is distinct from p_round_id or v_bet.status <> 'open'
       or v_bet.condition is null
       or (v_item.verdict = 'void' and v_bet.condition ->> 'kind' not in ('hole', 'beats', 'match')) then
      v_skipped := v_skipped + 1;
      continue;
    end if;
    update public.bets b
       set status              = case when v_item.verdict = 'void' then 'void' else 'resolved' end,
           resolution          = case when v_item.verdict = 'void' then null else v_item.verdict end,
           resolved_by         = null,
           resolved_by_profile = null,
           resolved_at         = now(),
           closed_at           = coalesce(b.closed_at, now())
     where b.id = v_bet.id;
    v_settled := v_settled + 1;
    if v_bet.club_id is not null or v_bet.competition_id is not null then
      insert into public.activity (club_id, competition_id, kind, category, data, event_id, round_id)
      values (v_bet.club_id, v_bet.competition_id, 'bet_resolved', 'bet',
              jsonb_build_object('bet_id', v_bet.id, 'question', v_bet.question, 'resolution', v_item.verdict,
                                 'auto', true, 'server', true),
              v_bet.event_id, v_bet.round_id);
    end if;
  end loop;

  select count(*) into v_left from public.bets b
   where b.round_id = p_round_id and b.status = 'open' and b.condition is not null;
  update public.bet_settle_queue q
     set done_at = now(), claimed_at = null, last_error = null
   where q.round_id = p_round_id;
  return jsonb_build_object('settled', v_settled, 'skipped', v_skipped, 'open_left', v_left);
end;
$$;
revoke all on function public.settle_round_bets(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.settle_round_bets(uuid, jsonb) to service_role;

-- --- bet_settle_failed: arbeideren fikk ikke regnet runden ---------------------------------
create or replace function public.bet_settle_failed(p_round_id uuid, p_error text)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.bet_settle_queue q
     set claimed_at = null, last_error = left(coalesce(p_error, 'ukjent feil'), 500)
   where q.round_id = p_round_id and q.done_at is null;
$$;
revoke all on function public.bet_settle_failed(uuid, text) from public, anon, authenticated;
grant execute on function public.bet_settle_failed(uuid, text) to service_role;


-- ===========================================================================
-- KONTROLL
-- ===========================================================================
do $$
declare
  v_fail text := '';
begin
  -- 1. Alle veddemål har nøyaktig én bank, og veddemål fra før har sesongens turnering.
  if exists (select 1 from public.bets where num_nonnulls(competition_id, round_scope) <> 1)
     or exists (select 1 from public.bets b join public.competitions c on c.id = b.competition_id
                 where b.season_id is not null and c.season_id is distinct from b.season_id) then
    v_fail := v_fail || ' 1';
  end if;
  -- 2. Hver innsats har sin person, og medlemmene er de samme som før.
  if exists (select 1 from public.bet_stakes where person_key is null
                or (member_id is not null and person_key <> member_id)) then
    v_fail := v_fail || ' 2';
  end if;
  -- 3. Turneringer med veddemål har veddemål på.
  if exists (select 1 from public.bets b join public.competitions c on c.id = b.competition_id
              where not c.bets_enabled) then
    v_fail := v_fail || ' 3';
  end if;
  -- 4. Den nye banken gir samme tall som den gamle for alle som har satset i en sesong.
  if exists (
    select 1
      from (select distinct b.season_id, b.competition_id, s.member_id
              from public.bets b join public.bet_stakes s on s.bet_id = b.id
             where b.season_id is not null and s.member_id is not null) x
     where (select row(o.net, o.at_stake, o.balance, o.available) from public.bet_points_for(x.season_id, x.member_id) o)
           is distinct from
           (select row(n.net, n.at_stake, n.balance, n.available) from public.bet_points_for(x.competition_id, null, x.member_id, null) n)) then
    v_fail := v_fail || ' 4';
  end if;
  -- 5. Køen og RPC-ene for serveren: bare service_role.
  if has_function_privilege('authenticated', 'public.bet_settle_jobs(integer)', 'execute')
     or has_function_privilege('authenticated', 'public.settle_round_bets(uuid, jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.bet_settle_failed(uuid, text)', 'execute')
     or has_function_privilege('anon', 'public.settle_round_bets(uuid, jsonb)', 'execute')
     or not has_function_privilege('service_role', 'public.settle_round_bets(uuid, jsonb)', 'execute')
     or not has_function_privilege('service_role', 'public.bet_settle_jobs(integer)', 'execute')
     or has_table_privilege('authenticated', 'public.bet_settle_queue', 'select')
     or has_table_privilege('anon', 'public.bet_settle_queue', 'select') then
    v_fail := v_fail || ' 5';
  end if;
  -- 6. Appens RPC-er: authenticated ja, anon nei. Hjelperne er stengt.
  if not has_function_privilege('authenticated', 'public.create_bet_v2(uuid, uuid, text, jsonb, uuid, uuid, text, integer)', 'execute')
     or not has_function_privilege('authenticated', 'public.bet_bank(uuid, uuid, uuid, uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.bets_set_enabled(uuid, uuid, boolean)', 'execute')
     or has_function_privilege('anon', 'public.create_bet_v2(uuid, uuid, text, jsonb, uuid, uuid, text, integer)', 'execute')
     or has_function_privilege('anon', 'public.bet_bank(uuid, uuid, uuid, uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.bet_points_for(uuid, uuid, uuid, uuid)', 'execute')
     or has_function_privilege('authenticated', 'private.bet_add_stake(public.bets, uuid, uuid, text, integer)', 'execute')
     or has_function_privilege('authenticated', 'public.bet_insert_stake(public.bets, uuid, text, integer)', 'execute') then
    v_fail := v_fail || ' 6';
  end if;
  -- 7. Gamle bygg: create_bet, settle_bet og mark_bets_closed står med samme signatur.
  if not has_function_privilege('authenticated', 'public.create_bet(uuid, uuid, uuid, text, jsonb, uuid, text, integer)', 'execute')
     or not has_function_privilege('authenticated', 'public.settle_bet(uuid, text)', 'execute')
     or not has_function_privilege('authenticated', 'public.mark_bets_closed(uuid[])', 'execute')
     or not has_function_privilege('authenticated', 'public.bet_points(uuid, uuid)', 'execute') then
    v_fail := v_fail || ' 7';
  end if;
  -- 8. Triggerne finnes.
  if (select count(*) from pg_trigger where not tgisinternal
        and ((tgname = 'bets_before_insert' and tgrelid = 'public.bets'::regclass)
          or (tgname = 'competitions_bets_inherit' and tgrelid = 'public.competitions'::regclass)
          or (tgname = 'bet_stakes_before_insert' and tgrelid = 'public.bet_stakes'::regclass)
          or (tgname = 'rounds_bet_settle_enqueue' and tgrelid = 'public.rounds'::regclass))) <> 4 then
    v_fail := v_fail || ' 8';
  end if;
  -- 9. Alle låste runder med åpne veddemål med vilkår står i køen.
  if exists (select 1 from public.bets b join public.rounds r on r.id = b.round_id
              where r.status = 'locked' and b.status = 'open' and b.condition is not null
                and not exists (select 1 from public.bet_settle_queue q where q.round_id = r.id)) then
    v_fail := v_fail || ' 9';
  end if;
  -- 10. Funksjonene her er security definer med tom search_path; køen har RLS uten policyer.
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where (n.nspname, p.proname) in (('public', 'bet_points_for'), ('public', 'bet_bank'),
                     ('public', 'bet_accepts_stakes'), ('public', 'bet_insert_stake'), ('public', 'bets_set_enabled'),
                     ('public', 'create_bet_v2'), ('public', 'place_bet_stake'), ('public', 'resolve_bet'),
                     ('public', 'bet_settle_jobs'), ('public', 'settle_round_bets'), ('public', 'bet_settle_failed'),
                     ('private', 'bet_scope_bets_rules'), ('private', 'bet_scope_rule'), ('private', 'bet_scope_ruleset'),
                     ('private', 'bet_people'), ('private', 'bet_me'), ('private', 'round_in_competition'),
                     ('private', 'bet_visible'), ('private', 'bets_before_insert'), ('private', 'competitions_bets_inherit'),
                     ('private', 'bet_stakes_before_insert'),
                     ('private', 'bet_add_stake'), ('private', 'bet_settle_enqueue'))
                and (not p.prosecdef or not ('search_path=""' = any (p.proconfig))))
     or not (select relrowsecurity from pg_class where oid = 'public.bet_settle_queue'::regclass)
     or exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'bet_settle_queue') then
    v_fail := v_fail || ' 10';
  end if;

  if v_fail <> '' then
    raise exception '052 kontroll feilet:%', v_fail;
  end if;
  raise notice '052 kontroll: 10 av 10 (veddemål: %, innsatser: %, turneringer med veddemål på: %, runder i køen: %)',
    (select count(*) from public.bets),
    (select count(*) from public.bet_stakes),
    (select count(*) from public.competitions where bets_enabled),
    (select count(*) from public.bet_settle_queue where done_at is null);
end $$;

commit;

-- ===========================================================================
-- RULLEBAKKE (bare test). Veddemål uten klubb eller sesong (nye turneringer, løse runder) og
-- innsatser fra profiler slettes, ellers stopper not null. Prøvd lokalt (se sql/README.md).
-- ===========================================================================
-- begin;
-- delete from public.bets where club_id is null or season_id is null;
-- delete from public.bet_stakes where member_id is null;
-- drop function if exists public.bet_settle_failed(uuid, text);
-- drop function if exists public.settle_round_bets(uuid, jsonb);
-- drop function if exists public.bet_settle_jobs(integer);
-- drop trigger if exists rounds_bet_settle_enqueue on public.rounds;
-- drop function if exists private.bet_settle_enqueue();
-- drop table if exists public.bet_settle_queue;
-- drop function if exists public.create_bet_v2(uuid, uuid, text, jsonb, uuid, uuid, text, integer);
-- drop function if exists public.bets_set_enabled(uuid, uuid, boolean);
-- drop function if exists public.bet_bank(uuid, uuid, uuid, uuid);
-- drop trigger if exists bet_stakes_before_insert on public.bet_stakes;
-- drop function if exists private.bet_stakes_before_insert();
-- drop trigger if exists bets_before_insert on public.bets;
-- drop function if exists private.bets_before_insert();
-- drop trigger if exists competitions_bets_inherit on public.competitions;
-- drop function if exists private.competitions_bets_inherit();
-- -- 012 og 044: de gamle utgavene tilbake.
-- drop policy if exists bets_select on public.bets;
-- create policy bets_select on public.bets
--   for select to authenticated
--   using (public.is_club_member(club_id) and (round_id is null or public.can_read_round(round_id)));
-- create or replace function public.bet_accepts_stakes(p_bet_id uuid)
-- returns boolean
-- language plpgsql
-- stable
-- security definer
-- set search_path = ''
-- as $$
-- declare
--   v_bet     public.bets%rowtype;
--   v_status  text;
--   v_open    integer;
--   v_members uuid[];
-- begin
--   select * into v_bet from public.bets where id = p_bet_id;
--   if not found or v_bet.status <> 'open' or v_bet.closed_at is not null then
--     return false;
--   end if;
--   if v_bet.condition is null then
--     return true;
--   end if;
--   select r.status into v_status from public.rounds r where r.id = v_bet.round_id;
--   if v_status is null then
--     return true;   -- runden finnes ikke (kan ikke skje med fremmednøkkelen)
--   end if;
--   if v_status = 'locked' then
--     return false;
--   end if;
--   if v_bet.condition ->> 'kind' in ('birdie', 'par', 'hole') then
--     select coalesce(array_agg(x::uuid), '{}') into v_members
--     from (select v_bet.condition ->> k as x from unnest(array['player', 'a', 'b']) k) s
--     where x is not null and x <> '';
--     v_open := public.bet_first_open_hole(v_bet.round_id, v_members,
--                                          coalesce(public.bet_rule(v_bet.season_id, 'lockAheadHoles', 1), 1));
--     return v_open is not null and (v_bet.condition ->> 'hole')::integer >= v_open;
--   end if;
--   return not exists (select 1 from public.hole_scores hs where hs.round_id = v_bet.round_id);
-- end;
-- $$;
-- revoke all on function public.bet_accepts_stakes(uuid) from public, anon;
-- grant execute on function public.bet_accepts_stakes(uuid) to authenticated;
-- create or replace function public.bet_insert_stake(p_bet public.bets, p_member_id uuid, p_side text, p_points integer)
-- returns uuid
-- language plpgsql
-- security definer
-- set search_path = ''
-- as $$
-- declare
--   v_max      integer;
--   v_mine     integer;
--   v_side     text;
--   v_free     numeric;
--   v_id       uuid;
-- begin
--   if p_side is null or p_side not in ('yes', 'no') then
--     raise exception 'Velg JA eller NEI' using errcode = '22023';
--   end if;
--   if p_points is null or p_points < 1 then
--     raise exception 'Innsatsen må være minst 1 poeng' using errcode = '22023';
--   end if;
--   perform pg_advisory_xact_lock(hashtextextended('bet_bank:' || p_bet.season_id || ':' || p_member_id, 0));
--
--   if not public.bet_accepts_stakes(p_bet.id) then
--     raise exception 'Veddemålet tar ikke imot innsatser nå: utfallet har begynt å bli kjent'
--       using errcode = '55000';
--   end if;
--
--   select coalesce(sum(s.points), 0), min(s.side) into v_mine, v_side
--   from public.bet_stakes s where s.bet_id = p_bet.id and s.member_id = p_member_id;
--   if v_side is not null and v_side <> p_side then
--     raise exception 'Du har alt satset på den andre siden' using errcode = '22023';
--   end if;
--   v_max := coalesce(public.bet_rule(p_bet.season_id, 'maxStakePerBet', 200), 200);
--   if v_mine + p_points > v_max then
--     raise exception 'Maks % poeng per veddemål. Du har % på det fra før.', v_max, v_mine
--       using errcode = '22023';
--   end if;
--   select available into v_free from public.bet_points_for(p_bet.season_id, p_member_id);
--   if v_free is not null and p_points > v_free then
--     raise exception 'Du har % ledige poeng', greatest(v_free, 0)::integer using errcode = '22023';
--   end if;
--
--   insert into public.bet_stakes (bet_id, club_id, member_id, side, points)
--   values (p_bet.id, p_bet.club_id, p_member_id, p_side, p_points)
--   returning id into v_id;
--   return v_id;
-- end;
-- $$;
-- revoke all on function public.bet_insert_stake(public.bets, uuid, text, integer) from public, anon, authenticated;
-- create or replace function public.place_bet_stake(p_bet_id uuid, p_side text, p_points integer)
-- returns uuid
-- language plpgsql
-- security definer
-- set search_path = ''
-- as $$
-- declare
--   v_bet  public.bets%rowtype;
--   v_me   uuid;
-- begin
--   if auth.uid() is null then
--     raise exception 'Du må være logget inn' using errcode = '42501';
--   end if;
--   select * into v_bet from public.bets b where b.id = p_bet_id for update;
--   if not found or not public.is_club_member(v_bet.club_id)
--      or (v_bet.round_id is not null and not public.can_read_round(v_bet.round_id)) then
--     raise exception 'Fant ikke veddemålet' using errcode = 'P0002';
--   end if;
--   v_me := public.my_member_id(v_bet.club_id);
--   return public.bet_insert_stake(v_bet, v_me, p_side, p_points);
-- end;
-- $$;
-- revoke all on function public.place_bet_stake(uuid, text, integer) from public, anon;
-- grant execute on function public.place_bet_stake(uuid, text, integer) to authenticated;
-- create or replace function public.resolve_bet(p_bet_id uuid, p_resolution text)
-- returns public.bets
-- language plpgsql
-- security definer
-- set search_path = ''
-- as $$
-- declare
--   v_bet  public.bets%rowtype;
--   v_me   uuid;
-- begin
--   if auth.uid() is null then
--     raise exception 'Du må være logget inn' using errcode = '42501';
--   end if;
--   if p_resolution is null or p_resolution not in ('yes', 'no', 'void') then
--     raise exception 'Utfallet må være yes, no eller void' using errcode = '22023';
--   end if;
--   select * into v_bet from public.bets b where b.id = p_bet_id for update;
--   if not found or not public.is_club_member(v_bet.club_id) then
--     raise exception 'Fant ikke veddemålet' using errcode = 'P0002';
--   end if;
--   if not private.has_club_right(v_bet.club_id, 'money') then
--     raise exception 'Bare arrangøren avgjør veddemål' using errcode = '42501';
--   end if;
--   if v_bet.status <> 'open' then
--     raise exception 'Veddemålet er alt avgjort' using errcode = '55000';
--   end if;
--   v_me := public.my_member_id(v_bet.club_id);
--   if exists (select 1 from public.bet_stakes s where s.bet_id = p_bet_id and s.member_id = v_me) then
--     raise exception 'Du har satset på dette veddemålet og kan ikke avgjøre det. En annen arrangør må gjøre det.'
--       using errcode = '55000';
--   end if;
--
--   update public.bets b
--      set status      = case when p_resolution = 'void' then 'void' else 'resolved' end,
--          resolution  = case when p_resolution = 'void' then null else p_resolution end,
--          resolved_by = v_me,
--          resolved_at = now(),
--          closed_at   = coalesce(b.closed_at, now())
--    where b.id = p_bet_id
--   returning * into v_bet;
--
--   insert into public.activity (club_id, kind, category, data, event_id, round_id)
--   values (v_bet.club_id, 'bet_resolved', 'bet',
--           jsonb_build_object('bet_id', v_bet.id, 'question', v_bet.question, 'resolution', p_resolution),
--           v_bet.event_id, v_bet.round_id);
--   return v_bet;
-- end;
-- $$;
-- revoke all on function public.resolve_bet(uuid, text) from public, anon;
-- grant execute on function public.resolve_bet(uuid, text) to authenticated, service_role;
-- drop function if exists public.bet_points_for(uuid, uuid, uuid, uuid);
-- drop function if exists private.bet_add_stake(public.bets, uuid, uuid, text, integer);
-- drop function if exists private.bet_visible(public.bets);
-- drop function if exists private.round_in_competition(uuid, uuid);
-- drop function if exists private.bet_me(uuid, uuid);
-- drop function if exists private.bet_people(uuid, uuid);
-- drop function if exists private.bet_scope_ruleset(uuid, uuid);
-- drop function if exists private.bet_scope_rule(uuid, uuid, text, integer);
-- drop function if exists private.bet_scope_bets_rules(uuid, uuid);
-- drop function if exists private.bet_rule_value(jsonb, text, integer);
-- alter table public.bet_stakes drop constraint if exists bet_stakes_person_key, drop constraint if exists bet_stakes_one_person,
--   drop constraint if exists bet_stakes_member_needs_club, drop constraint if exists bet_stakes_profile_fkey,
--   drop constraint if exists bet_stakes_bet_id_fkey;
-- drop index if exists public.bet_stakes_person_idx;
-- drop index if exists public.bet_stakes_profile_idx;
-- alter table public.bet_stakes drop column if exists person_key, drop column if exists profile_id;
-- alter table public.bet_stakes alter column member_id set not null, alter column club_id set not null;
-- alter table public.bets drop constraint if exists bets_one_scope, drop constraint if exists bets_scope_round,
--   drop constraint if exists bets_creator_one, drop constraint if exists bets_against_one,
--   drop constraint if exists bets_resolved_by_one, drop constraint if exists bets_round_id_fkey,
--   drop constraint if exists bets_competition_id_fkey, drop constraint if exists bets_round_scope_fkey,
--   drop constraint if exists bets_creator_profile_fkey, drop constraint if exists bets_against_profile_fkey,
--   drop constraint if exists bets_resolved_by_profile_fkey;
-- drop index if exists public.bets_competition_idx;
-- drop index if exists public.bets_round_scope_idx;
-- alter table public.bets drop column if exists competition_id, drop column if exists round_scope,
--   drop column if exists creator_profile_id, drop column if exists against_profile_id,
--   drop column if exists resolved_by_profile;
-- alter table public.bets alter column club_id set not null, alter column season_id set not null;
-- alter table public.rounds drop column if exists bets_enabled;
-- alter table public.competitions drop column if exists bets_enabled;
-- commit;
