-- ===========================================================================
-- 012 – VEDDEMÅL MED POENG (FORSLAG)
-- ===========================================================================
-- Status: FORSLAG til godkjenning (ROADMAP B5 og B10, fase 10). IKKE KJØRT mot
-- Supabase. Prøvd mot en lokal, midlertidig Postgres (sql/lokal/012_prove.sql).
-- Kjøres først på TEST etter ja fra brukeren, så kontrollen nederst. Prod først
-- etter ny godkjenning.
--
-- Oppdatert etter brukerens valg 07.10.2026 (docs/veddemaal-poeng.md, «Besluttet»):
--   * Poengbank 1000 per sesong; ny sesong = ny bank (saldoen regnes per sesong).
--   * Oppgjør i HELE POENG (regelverdien payoutDecimals, Golfgutu 0). Resten etter
--     avrundingen går til største innsats, så hvert veddemål går i null.
--   * Den som avgjør, vedder ikke: resolve_bet avviser en arrangør med innsats.
--   * Delt hull, delt match og likt resultat annulleres automatisk av feiingen
--     (settle_bet med 'void').
--   * Push bare for nye og avgjorte veddemål. Én side per spiller.
--   * Tippekupongen har egen bank (fase 7), ikke denne.
--
-- Krever 001 (tabeller og hjelpefunksjoner), 008 (activity) og 010 (push_queue,
-- kategorien 'bet' finnes alt i activity.category og i push-kategoriene).
--
-- Modellen (docs/veddemaal-poeng.md):
--   * bets: ett veddemål med påstand, valgfritt vilkår appen kan avgjøre selv,
--     status (open / resolved / void) og utfall (yes / no).
--   * bet_stakes: innsatsene i POENG (B10, ingen kroner).
--   * Poengbanken LAGRES IKKE. Saldo = startbeholdning (regelsettet, sesongens
--     rules->'bets'->'startingPoints') + netto fra avgjorte veddemål. Netto og
--     ledig regnes av bet_points() her og av Bets.swift i appen, med samme
--     regnestykke (som PWA-ens spiller_saldo og balanceFor). Grunnen: en saldo
--     som lagres kan komme i utakt med innsatsene; en sum kan ikke det.
--   * All skriving går gjennom fire RPC-er, hver i én transaksjon:
--       create_bet       veddemålet, din første innsats og aktivitetslinja
--       place_bet_stake  en innsats til (tak, samme side, ledige poeng, sperra)
--       resolve_bet      arrangøren avgjør for hånd (yes / no) eller annullerer
--                        (void). Ikke på et veddemål hun selv har satset på.
--       settle_bet       feiingen på arrangørens telefon: vilkåret avgjør (yes /
--                        no), delt resultat annulleres (void). Bare veddemål med
--                        vilkår, og bare når scorene kan ha gitt svar.
--     pluss mark_bets_closed, arrangørens journalstempel (lukket_at i PWA-en).
--     Tabellene har ingen insert/update/delete for klienten.
--
-- Lærdom fra PWA-en som er bygd inn:
--   * Sperra (markedTarInnsatser / veddemaal_tar_innsatser) ligger i databasen
--     og er AVLEDET av scorene, ikke av et stempel. Den gjelder i samme øyeblikk
--     som hullet føres, uansett hvem som fører.
--   * Veddemålet og første innsats skrives i én transaksjon. PWA-en gjorde to
--     kall og kunne lage et veddemål uten innsats (README A2).
--   * Vilkåret har ekte fremmednøkkel til runden. PWA-en hadde runde-id inne i
--     jsonb, og sletting etterlot åpne veddemål. Slettes runden, går veddemålene
--     om den med (cascade), som PWA-ens slett_runde.
--   * revoke … from public, anon står ETTER hver create or replace.
--
-- Regelverdier: SQL leser sesongens regelsett (forsprang, tak, startbeholdning,
-- desimaler i oppgjøret). Mangler feltet, gjelder Golfgutu-verdien, samme regel
-- som Ruleset-dekoderen i appen (forsprang 1, tak 200, startbeholdning 1000,
-- payoutDecimals 0; null = ingen bank). voidTies leses bare av appens feiing.
--
-- Én transaksjon. Idempotent der det er naturlig.
-- ===========================================================================

begin;


-- ===========================================================================
-- 1. TABELLER
-- ===========================================================================

-- --- bets: veddemålet ------------------------------------------------------
-- condition: null = fri tekst (arrangøren avgjør). Ellers et objekt appen kan
-- lese: {"kind": "birdie"|"par"|"hole"|"beats"|"drive"|"kp"|"match",
--        "hole": 0–17, "player": uuid, "a": uuid, "b": uuid}. Runden er
-- kolonnen round_id, ikke en nøkkel i jsonb.
-- closed_at er journalen: når utfallet ble kjent. Et stemplet veddemål tar
-- aldri flere innsatser, også om runden senere rettes bakover.
create table if not exists public.bets (
  id           uuid primary key default gen_random_uuid(),
  club_id      uuid not null references public.clubs(id) on delete cascade,
  season_id    uuid not null,
  event_id     uuid,
  round_id     uuid,
  creator_id   uuid,
  against_id   uuid,
  question     text not null check (char_length(btrim(question)) between 4 and 140),
  condition    jsonb,
  status       text not null default 'open' check (status in ('open', 'resolved', 'void')),
  resolution   text check (resolution in ('yes', 'no')),
  closed_at    timestamptz,
  resolved_by  uuid,
  resolved_at  timestamptz,
  created_at   timestamptz not null default now(),
  constraint bets_id_club_key unique (id, club_id),
  constraint bets_resolution_with_status check ((status = 'resolved') = (resolution is not null)),
  constraint bets_condition_needs_round check (condition is null or round_id is not null),
  constraint bets_season_fk foreign key (season_id, club_id)
    references public.seasons (id, club_id) on delete cascade,
  constraint bets_event_fk foreign key (event_id, club_id)
    references public.events (id, club_id) on delete set null (event_id),
  constraint bets_round_fk foreign key (round_id, club_id)
    references public.rounds (id, club_id) on delete cascade,
  constraint bets_creator_fk foreign key (creator_id, club_id)
    references public.club_members (id, club_id) on delete set null (creator_id),
  constraint bets_against_fk foreign key (against_id, club_id)
    references public.club_members (id, club_id) on delete set null (against_id),
  constraint bets_resolved_by_fk foreign key (resolved_by, club_id)
    references public.club_members (id, club_id) on delete set null (resolved_by)
);
comment on table public.bets is
  'Veddemål med poeng (fase 10, B10). condition null = fri tekst. Skrives bare via '
  'create_bet, resolve_bet og mark_bets_closed. Saldo lagres ikke (bet_points).';
create index if not exists bets_season_idx on public.bets (season_id, created_at desc);
create index if not exists bets_round_idx on public.bets (round_id) where round_id is not null;
create index if not exists bets_event_idx on public.bets (event_id) where event_id is not null;

-- --- bet_stakes: innsatsene i poeng -----------------------------------------
-- Flere innsatser fra samme spiller er lov (summen må holde seg under taket),
-- men alltid på samme side (place_bet_stake).
create table if not exists public.bet_stakes (
  id          uuid primary key default gen_random_uuid(),
  bet_id      uuid not null,
  club_id     uuid not null,
  member_id   uuid not null,
  side        text not null check (side in ('yes', 'no')),
  points      integer not null check (points between 1 and 10000),
  created_at  timestamptz not null default now(),
  constraint bet_stakes_bet_fk foreign key (bet_id, club_id)
    references public.bets (id, club_id) on delete cascade,
  constraint bet_stakes_member_fk foreign key (member_id, club_id)
    references public.club_members (id, club_id) on delete restrict
);
comment on table public.bet_stakes is
  'Innsatser i POENG på et veddemål. Skrives bare via create_bet og place_bet_stake.';
create index if not exists bet_stakes_bet_idx on public.bet_stakes (bet_id);
create index if not exists bet_stakes_member_idx on public.bet_stakes (member_id);


-- ===========================================================================
-- 2. HJELPEFUNKSJONER (regnestykket, samme som Bets.swift)
-- ===========================================================================

-- --- bet_condition_valid: formen på vilkåret --------------------------------
create or replace function public.bet_condition_valid(p jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p is null or (
    jsonb_typeof(p) = 'object'
    and pg_column_size(p) <= 1024
    and p ->> 'kind' in ('birdie', 'par', 'hole', 'beats', 'drive', 'kp', 'match')
    and coalesce(p ->> 'player', '') ~* '^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})?$'
    and coalesce(p ->> 'a', '')      ~* '^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})?$'
    and coalesce(p ->> 'b', '')      ~* '^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})?$'
    and case p ->> 'kind'
      when 'birdie' then coalesce(p ->> 'hole', '') ~ '^([0-9]|1[0-7])$'
      when 'par'    then coalesce(p ->> 'hole', '') ~ '^([0-9]|1[0-7])$' and p ? 'player'
      when 'hole'   then coalesce(p ->> 'hole', '') ~ '^([0-9]|1[0-7])$' and p ? 'a' and p ? 'b'
                         and p ->> 'a' <> p ->> 'b'
      when 'beats'  then p ? 'a' and p ? 'b' and p ->> 'a' <> p ->> 'b' and not p ? 'hole'
      else p ? 'player' and not p ? 'hole'
    end
  );
$$;
revoke all on function public.bet_condition_valid(jsonb) from public, anon;
grant execute on function public.bet_condition_valid(jsonb) to authenticated;

alter table public.bets drop constraint if exists bets_condition_shape;
alter table public.bets add constraint bets_condition_shape check (public.bet_condition_valid(condition));

-- --- bet_rule: en heltallsverdi fra sesongens rules->'bets' ------------------
-- Mangler feltet, gjelder p_default (Golfgutu-verdien, som Ruleset-dekoderen).
-- JSON null gir null (startingPoints: null = ingen bank).
create or replace function public.bet_rule(p_season_id uuid, p_key text, p_default integer)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when s.rules -> 'bets' ? p_key
      then case when jsonb_typeof(s.rules -> 'bets' -> p_key) = 'number'
                then (s.rules -> 'bets' ->> p_key)::numeric::integer end
    else p_default
  end
  from public.seasons s
  where s.id = p_season_id;
$$;
revoke all on function public.bet_rule(uuid, text, integer) from public, anon, authenticated;

-- --- bet_first_open_hole: forsteApneHull ------------------------------------
-- Fronten er høyeste førte hull + 1 for den av spillerne som har kommet lengst
-- (tom liste = feltet). Front 0 = ingen har begynt, og da er hull 1 åpent.
-- null når runden er låst eller kommet for langt (tellende hull, avkortet
-- «felles» kutter).
create or replace function public.bet_first_open_hole(p_round_id uuid, p_members uuid[], p_lock_ahead integer)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  with r as (
    select ro.status,
           case when ro.cut_rule = 'common' and ro.cut_after >= 1
                then least(ro.hole_count, ro.cut_after) else ro.hole_count end as counting
    from public.rounds ro where ro.id = p_round_id
  ),
  f as (
    select coalesce(max(hs.hole_index) + 1, 0) as front
    from public.hole_scores hs
    where hs.round_id = p_round_id
      and (coalesce(cardinality(p_members), 0) = 0 or hs.member_id = any (p_members))
  ),
  i as (select case when f.front = 0 then 0 else f.front + p_lock_ahead end as hole from f)
  select case when r.status = 'locked' or i.hole >= r.counting then null else i.hole end
  from r, i;
$$;
revoke all on function public.bet_first_open_hole(uuid, uuid[], integer) from public, anon, authenticated;

-- --- bet_accepts_stakes: markedTarInnsatser -----------------------------------
-- Åpent, ikke stemplet, og: fri tekst alltid; hullvilkår når hullet ligger
-- minst forspranget foran den/dem det gjelder; rundevilkår før første score.
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
    return true;   -- runden finnes ikke (kan ikke skje med fremmednøkkelen)
  end if;
  if v_status = 'locked' then
    return false;
  end if;
  if v_bet.condition ->> 'kind' in ('birdie', 'par', 'hole') then
    select coalesce(array_agg(x::uuid), '{}') into v_members
    from (select v_bet.condition ->> k as x from unnest(array['player', 'a', 'b']) k) s
    where x is not null and x <> '';
    v_open := public.bet_first_open_hole(v_bet.round_id, v_members,
                                         coalesce(public.bet_rule(v_bet.season_id, 'lockAheadHoles', 1), 1));
    return v_open is not null and (v_bet.condition ->> 'hole')::integer >= v_open;
  end if;
  return not exists (select 1 from public.hole_scores hs where hs.round_id = v_bet.round_id);
end;
$$;
revoke all on function public.bet_accepts_stakes(uuid) from public, anon;
grant execute on function public.bet_accepts_stakes(uuid) to authenticated;

-- --- bet_points: netto, stående og ledig for ett medlem i én sesong ----------
-- Netto (marketNetFor, Bets.payouts i appen): vinnersiden deler taperpotten
-- etter innsats. Ingen på vinnersiden eller ingen tapere: alle får innsatsen
-- tilbake. Åpne og annullerte teller ikke.
-- Hele poeng (payoutDecimals, Golfgutu 0, høyst 2): hver vinners gevinst rundes
-- med floor(x + 0.5), regnet i heltall: (2·innsats·tapt·10^d + vunnet) div
-- (2·vunnet). Resten (taperpotten minus summen av de rundede gevinstene) gis
-- eller tas én enhet om gangen fra vinnerne etter største innsats, så laveste
-- medlems-id. Summen i hvert veddemål er da nøyaktig null.
-- Saldo = startbeholdning + netto. Ledig = saldo − det som står i åpne.
-- balance og available er null når sesongen ikke har poengbank.
create or replace function public.bet_points_for(p_season_id uuid, p_member_id uuid)
returns table (net numeric, at_stake numeric, balance numeric, available numeric)
language sql
stable
security definer
set search_path = ''
as $$
  with d as (
    select greatest(0, least(2, coalesce(public.bet_rule(p_season_id, 'payoutDecimals', 0), 0))) as decimals
  ),
  sc as (select d.decimals, (10 ^ d.decimals)::bigint as scale from d),
  b as (
    select id, resolution from public.bets
    where season_id = p_season_id and status = 'resolved'
  ),
  per as (   -- én rad per veddemål og medlem: summen og om siden vant
    select s.bet_id, s.member_id, sum(s.points)::bigint as pts, bool_and(s.side = b.resolution) as won
    from public.bet_stakes s join b on b.id = s.bet_id
    group by s.bet_id, s.member_id
  ),
  pools as (
    select bet_id,
           coalesce(sum(pts) filter (where won), 0)::bigint as win,
           coalesce(sum(pts) filter (where not won), 0)::bigint as lose
    from per group by bet_id
  ),
  w as (   -- vinnerne i veddemål der poeng flytter seg: gevinsten i enheter
    select p.bet_id, p.member_id, p.pts,
           (2 * p.pts * pl.lose * sc.scale + pl.win) / (2 * pl.win) as units,
           pl.lose * sc.scale as total
    from per p join pools pl on pl.bet_id = p.bet_id cross join sc
    where p.won and pl.win > 0 and pl.lose > 0
  ),
  r as (
    select w.member_id, w.units,
           w.total - sum(w.units) over (partition by w.bet_id) as rest,
           row_number() over (partition by w.bet_id order by w.pts desc, w.member_id) as rn
    from w
  ),
  mine as (
    select round((r.units + case when r.rn <= abs(r.rest) then sign(r.rest)::bigint else 0 end)::numeric / sc.scale,
                 sc.decimals) as amount
    from r cross join sc
    where r.member_id = p_member_id
    union all
    select -p.pts::numeric
    from per p join pools pl on pl.bet_id = p.bet_id
    where p.member_id = p_member_id and not p.won and pl.win > 0 and pl.lose > 0
  ),
  n as (select coalesce(sum(amount), 0)::numeric as net from mine),
  st as (
    select coalesce(sum(s.points), 0)::numeric as at_stake
    from public.bet_stakes s join public.bets o on o.id = s.bet_id
    where o.season_id = p_season_id and o.status = 'open' and s.member_id = p_member_id
  ),
  bank as (select public.bet_rule(p_season_id, 'startingPoints', 1000) as start)
  select n.net, st.at_stake,
         bank.start + n.net,
         bank.start + n.net - st.at_stake
  from n, st, bank;
$$;
revoke all on function public.bet_points_for(uuid, uuid) from public, anon, authenticated;

-- --- bet_points: det appen kan spørre om (egne eller andres i egen klubb) ----
create or replace function public.bet_points(p_season_id uuid, p_member_id uuid)
returns table (net numeric, at_stake numeric, balance numeric, available numeric)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_club uuid;
begin
  select s.club_id into v_club from public.seasons s where s.id = p_season_id;
  if v_club is null or not public.is_club_member(v_club) then
    raise exception 'Fant ikke sesongen' using errcode = 'P0002';
  end if;
  return query select * from public.bet_points_for(p_season_id, p_member_id);
end;
$$;
revoke all on function public.bet_points(uuid, uuid) from public, anon;
grant execute on function public.bet_points(uuid, uuid) to authenticated;


-- ===========================================================================
-- 3. RLS OG RETTIGHETER
-- ===========================================================================
-- Lesing: aktive medlemmer i klubben. Veddemål om en kladd ser bare den som
-- ser runden (arrangøren). Skriving: bare RPC-ene under (security definer).

alter table public.bets       enable row level security;
alter table public.bet_stakes enable row level security;

do $$
declare
  p record;
begin
  for p in
    select policyname, tablename from pg_policies
    where schemaname = 'public' and tablename in ('bets', 'bet_stakes')
  loop
    execute format('drop policy if exists %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

create policy bets_select on public.bets
  for select to authenticated
  using (public.is_club_member(club_id) and (round_id is null or public.can_read_round(round_id)));
create policy bet_stakes_select on public.bet_stakes
  for select to authenticated
  using (exists (select 1 from public.bets b where b.id = bet_id));

do $$
declare
  t text;
begin
  foreach t in array array['bets', 'bet_stakes'] loop
    execute format('revoke all on table public.%I from public, anon, authenticated', t);
  end loop;
end $$;
grant select on table public.bets       to authenticated;
grant select on table public.bet_stakes to authenticated;


-- ===========================================================================
-- 4. RPC-ER
-- ===========================================================================

-- --- felles: legg inn én innsats med alle sjekkene --------------------------
-- Kalles bare fra create_bet og place_bet_stake (ingen rettighet for klienten).
-- Låser medlemmets poengbank for sesongen, så to innsatser samtidig ikke kan
-- bruke de samme ledige poengene.
create or replace function public.bet_insert_stake(p_bet public.bets, p_member_id uuid, p_side text, p_points integer)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_max      integer;
  v_mine     integer;
  v_side     text;
  v_free     numeric;
  v_id       uuid;
begin
  if p_side is null or p_side not in ('yes', 'no') then
    raise exception 'Velg JA eller NEI' using errcode = '22023';
  end if;
  if p_points is null or p_points < 1 then
    raise exception 'Innsatsen må være minst 1 poeng' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('bet_bank:' || p_bet.season_id || ':' || p_member_id, 0));

  if not public.bet_accepts_stakes(p_bet.id) then
    raise exception 'Veddemålet tar ikke imot innsatser nå: utfallet har begynt å bli kjent'
      using errcode = '55000';
  end if;

  select coalesce(sum(s.points), 0), min(s.side) into v_mine, v_side
  from public.bet_stakes s where s.bet_id = p_bet.id and s.member_id = p_member_id;
  if v_side is not null and v_side <> p_side then
    raise exception 'Du har alt satset på den andre siden' using errcode = '22023';
  end if;
  v_max := coalesce(public.bet_rule(p_bet.season_id, 'maxStakePerBet', 200), 200);
  if v_mine + p_points > v_max then
    raise exception 'Maks % poeng per veddemål. Du har % på det fra før.', v_max, v_mine
      using errcode = '22023';
  end if;
  select available into v_free from public.bet_points_for(p_bet.season_id, p_member_id);
  if v_free is not null and p_points > v_free then
    raise exception 'Du har % ledige poeng', greatest(v_free, 0)::integer using errcode = '22023';
  end if;

  insert into public.bet_stakes (bet_id, club_id, member_id, side, points)
  values (p_bet.id, p_bet.club_id, p_member_id, p_side, p_points)
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.bet_insert_stake(public.bets, uuid, text, integer) from public, anon, authenticated;

-- --- create_bet: veddemålet og din første innsats, i én transaksjon ---------
-- p_round_id: runden vilkåret gjelder (påkrevd med vilkår). p_event_id: kvelden
-- (settes fra runden når runden er gitt). Uten noen av dem gjelder veddemålet
-- klubbens aktive sesong («pallen i sesongen»).
-- Spillerne i vilkåret må være med i runden. against er den det gjelder (mot).
-- Aktivitetslinja (kategori bet) skrives i samme transaksjon og blir push via
-- køtriggeren fra 010.
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
    select s.id into v_season from public.seasons s where s.club_id = p_club_id and s.status = 'active';
  end if;
  if v_season is null then
    raise exception 'Veddemål krever en aktiv sesong med kvelden i terminlista' using errcode = '55000';
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

-- --- place_bet_stake: en innsats på et veddemål som finnes ------------------
-- Ingen aktivitetslinje: push bare for nye og avgjorte veddemål (besluttet
-- 07.10.2026; PWA-ens «satset»-linje ga mye push).
create or replace function public.place_bet_stake(p_bet_id uuid, p_side text, p_points integer)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_bet  public.bets%rowtype;
  v_me   uuid;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select * into v_bet from public.bets b where b.id = p_bet_id for update;
  if not found or not public.is_club_member(v_bet.club_id)
     or (v_bet.round_id is not null and not public.can_read_round(v_bet.round_id)) then
    raise exception 'Fant ikke veddemålet' using errcode = 'P0002';
  end if;
  v_me := public.my_member_id(v_bet.club_id);
  return public.bet_insert_stake(v_bet, v_me, p_side, p_points);
end;
$$;
revoke all on function public.place_bet_stake(uuid, text, integer) from public, anon;
grant execute on function public.place_bet_stake(uuid, text, integer) to authenticated;

-- --- resolve_bet: arrangøren avgjør eller annullerer for hånd ----------------
-- p_resolution: 'yes', 'no' eller 'void' (alle får innsatsen tilbake). Fri
-- tekst, og nødutgangen for veddemål med vilkår (feiingen bruker settle_bet).
-- Den som avgjør, vedder ikke: en arrangør med innsats i veddemålet avvises, og
-- en annen arrangør må gjøre det (besluttet 07.10.2026). Kan ikke angres.
create or replace function public.resolve_bet(p_bet_id uuid, p_resolution text)
returns public.bets
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_bet  public.bets%rowtype;
  v_me   uuid;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if p_resolution is null or p_resolution not in ('yes', 'no', 'void') then
    raise exception 'Utfallet må være yes, no eller void' using errcode = '22023';
  end if;
  select * into v_bet from public.bets b where b.id = p_bet_id for update;
  if not found or not public.is_club_member(v_bet.club_id) then
    raise exception 'Fant ikke veddemålet' using errcode = 'P0002';
  end if;
  if not public.is_club_organizer(v_bet.club_id) then
    raise exception 'Bare arrangøren avgjør veddemål' using errcode = '42501';
  end if;
  if v_bet.status <> 'open' then
    raise exception 'Veddemålet er alt avgjort' using errcode = '55000';
  end if;
  v_me := public.my_member_id(v_bet.club_id);
  if exists (select 1 from public.bet_stakes s where s.bet_id = p_bet_id and s.member_id = v_me) then
    raise exception 'Du har satset på dette veddemålet og kan ikke avgjøre det. En annen arrangør må gjøre det.'
      using errcode = '55000';
  end if;

  update public.bets b
     set status      = case when p_resolution = 'void' then 'void' else 'resolved' end,
         resolution  = case when p_resolution = 'void' then null else p_resolution end,
         resolved_by = v_me,
         resolved_at = now(),
         closed_at   = coalesce(b.closed_at, now())
   where b.id = p_bet_id
  returning * into v_bet;

  insert into public.activity (club_id, kind, category, data, event_id, round_id)
  values (v_bet.club_id, 'bet_resolved', 'bet',
          jsonb_build_object('bet_id', v_bet.id, 'question', v_bet.question, 'resolution', p_resolution),
          v_bet.event_id, v_bet.round_id);
  return v_bet;
end;
$$;
revoke all on function public.resolve_bet(uuid, text) from public, anon;
grant execute on function public.resolve_bet(uuid, text) to authenticated;

-- --- bet_outcome_known: kan scorene ha gitt svar? ----------------------------
-- Vakt for settle_bet, ikke en fasit: databasen regner ikke netto mot par. Låst
-- runde: ja. Hullvilkår: hullet er ført for den/dem det gjelder («noen»: for
-- minst én). Match: runden er i gang (kan avgjøres før siste hull). Slår i
-- runden, longest drive og nærmest pinnen: først når runden er låst.
create or replace function public.bet_outcome_known(p_bet public.bets)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_status text;
  v_hole   integer;
  v_kind   text := p_bet.condition ->> 'kind';
  v_player uuid := nullif(p_bet.condition ->> 'player', '')::uuid;
begin
  if p_bet.condition is null or p_bet.round_id is null then
    return false;
  end if;
  select r.status into v_status from public.rounds r where r.id = p_bet.round_id;
  if v_status is null then
    return false;
  end if;
  if v_status = 'locked' then
    return true;
  end if;
  v_hole := (p_bet.condition ->> 'hole')::integer;
  return case
    when v_kind in ('birdie', 'par') then exists (
      select 1 from public.hole_scores hs
      where hs.round_id = p_bet.round_id and hs.hole_index = v_hole
        and (v_player is null or hs.member_id = v_player))
    when v_kind = 'hole' then (
      select count(distinct hs.member_id) = 2 from public.hole_scores hs
      where hs.round_id = p_bet.round_id and hs.hole_index = v_hole
        and hs.member_id in ((p_bet.condition ->> 'a')::uuid, (p_bet.condition ->> 'b')::uuid))
    when v_kind = 'match' then exists (select 1 from public.hole_scores hs where hs.round_id = p_bet.round_id)
    else false
  end;
end;
$$;
revoke all on function public.bet_outcome_known(public.bets) from public, anon, authenticated;

-- --- settle_bet: feiingen avgjør det vilkåret gir svar på ---------------------
-- Kalles av appen på arrangørens telefon (Bets.sweep). 'yes' / 'no' når
-- vilkåret har gitt svar, 'void' når det er delt (delt hull, delt match, likt
-- resultat: alle får innsatsen tilbake, besluttet 07.10.2026). Bare veddemål med
-- vilkår; fri tekst avgjøres for hånd (resolve_bet). Gjelder også veddemål
-- arrangøren har satset på: det er scorene som avgjør, ikke hun. resolved_by
-- blir tom (avgjort av scorene). Kan ikke angres.
create or replace function public.settle_bet(p_bet_id uuid, p_resolution text)
returns public.bets
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_bet  public.bets%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if p_resolution is null or p_resolution not in ('yes', 'no', 'void') then
    raise exception 'Utfallet må være yes, no eller void' using errcode = '22023';
  end if;
  select * into v_bet from public.bets b where b.id = p_bet_id for update;
  if not found or not public.is_club_member(v_bet.club_id) then
    raise exception 'Fant ikke veddemålet' using errcode = 'P0002';
  end if;
  if not public.is_club_organizer(v_bet.club_id) then
    raise exception 'Bare arrangørens telefon avgjør veddemål automatisk' using errcode = '42501';
  end if;
  if v_bet.status <> 'open' then
    raise exception 'Veddemålet er alt avgjort' using errcode = '55000';
  end if;
  if v_bet.condition is null then
    raise exception 'Fri tekst avgjøres av arrangøren for hånd' using errcode = '22023';
  end if;
  if p_resolution = 'void' and v_bet.condition ->> 'kind' not in ('hole', 'beats', 'match') then
    raise exception 'Bare delt hull, delt match og likt resultat annulleres automatisk' using errcode = '22023';
  end if;
  if not public.bet_outcome_known(v_bet) then
    raise exception 'Utfallet er ikke kjent ennå' using errcode = '55000';
  end if;

  update public.bets b
     set status      = case when p_resolution = 'void' then 'void' else 'resolved' end,
         resolution  = case when p_resolution = 'void' then null else p_resolution end,
         resolved_by = null,
         resolved_at = now(),
         closed_at   = coalesce(b.closed_at, now())
   where b.id = p_bet_id
  returning * into v_bet;

  insert into public.activity (club_id, kind, category, data, event_id, round_id)
  values (v_bet.club_id, 'bet_resolved', 'bet',
          jsonb_build_object('bet_id', v_bet.id, 'question', v_bet.question, 'resolution', p_resolution,
                             'auto', true),
          v_bet.event_id, v_bet.round_id);
  return v_bet;
end;
$$;
revoke all on function public.settle_bet(uuid, text) from public, anon;
grant execute on function public.settle_bet(uuid, text) to authenticated;

-- --- mark_bets_closed: journalstempelet (lukket_at) --------------------------
-- Arrangørens feiing setter det når et hull lukker et veddemål uten at det kan
-- avgjøres ennå (Bets.sweep: close uten utfall). Sperra trenger det ikke, den
-- regnes av scorene. Stempler bare åpne veddemål uten stempel. Returnerer antall.
create or replace function public.mark_bets_closed(p_bet_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  n integer;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if coalesce(cardinality(p_bet_ids), 0) > 200 then
    raise exception 'For mange veddemål på én gang' using errcode = '22023';
  end if;
  update public.bets b
     set closed_at = now()
   where b.id = any (p_bet_ids)
     and b.status = 'open'
     and b.closed_at is null
     and public.is_club_organizer(b.club_id);
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke all on function public.mark_bets_closed(uuid[]) from public, anon;
grant execute on function public.mark_bets_closed(uuid[]) to authenticated;


-- ===========================================================================
-- 5. REALTIME
-- ===========================================================================
do $$
declare
  t text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'Publikasjonen supabase_realtime finnes ikke – hopper over realtime';
    return;
  end if;
  foreach t in array array['bets', 'bet_stakes'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime'
                     and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

commit;


-- ===========================================================================
-- KONTROLL (kjør etterpå i SQL Editor). Én rad per sjekk, alle skal ha ok = true.
-- ===========================================================================
-- with
-- t as (
--   select c.relname, c.relrowsecurity
--   from pg_class c join pg_namespace n on n.oid = c.relnamespace
--   where n.nspname = 'public' and c.relkind = 'r' and c.relname in ('bets', 'bet_stakes')
-- ),
-- f as (
--   select p.proname,
--          has_function_privilege('anon', p.oid, 'execute') as anon_kan,
--          has_function_privilege('authenticated', p.oid, 'execute') as auth_kan
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public'
--     and p.proname in ('bet_condition_valid', 'bet_rule', 'bet_first_open_hole', 'bet_accepts_stakes',
--                       'bet_points_for', 'bet_points', 'bet_insert_stake', 'create_bet',
--                       'place_bet_stake', 'resolve_bet', 'bet_outcome_known', 'settle_bet',
--                       'mark_bets_closed')
-- ),
-- g as (
--   select table_name, string_agg(privilege_type, ', ' order by privilege_type) as rettigheter
--   from information_schema.role_table_grants
--   where table_schema = 'public' and grantee = 'authenticated' and table_name in ('bets', 'bet_stakes')
--   group by 1
-- )
-- select 1 as nr, 'Tabellene finnes med RLS' as sjekk,
--        (select count(*) = 2 and bool_and(relrowsecurity) from t) as ok
-- union all
-- select 2, 'anon har ingen tabellrettigheter',
--        not exists (select 1 from information_schema.role_table_grants
--                    where table_schema = 'public' and grantee in ('anon', 'PUBLIC')
--                      and table_name in ('bets', 'bet_stakes'))
-- union all
-- select 3, 'authenticated: bare SELECT på begge',
--        (select count(*) = 2 and bool_and(rettigheter = 'SELECT') from g)
-- union all
-- select 4, 'Alle tretten funksjonene finnes', (select count(*) = 13 from f)
-- union all
-- select 5, 'anon kan ikke kjøre noen veddemålsfunksjon', not exists (select 1 from f where anon_kan)
-- union all
-- select 6, 'authenticated kan kjøre appens åtte funksjoner',
--        (select count(*) = 8 and bool_and(auth_kan) from f
--         where proname in ('bet_condition_valid', 'bet_accepts_stakes', 'bet_points', 'create_bet',
--                           'place_bet_stake', 'resolve_bet', 'settle_bet', 'mark_bets_closed'))
-- union all
-- select 7, 'authenticated kan ikke kjøre de indre hjelperne',
--        not exists (select 1 from f where auth_kan
--                    and proname in ('bet_rule', 'bet_first_open_hole', 'bet_points_for', 'bet_insert_stake',
--                                    'bet_outcome_known'))
-- union all
-- select 8, 'Kategorien bet finnes i activity',
--        exists (select 1 from pg_constraint
--                where conrelid = 'public.activity'::regclass and contype = 'c'
--                  and pg_get_constraintdef(oid) like '%''bet''%')
-- union all
-- select 9, 'Realtime for bets og bet_stakes',
--        (select count(*) = 2 from pg_publication_tables
--         where pubname = 'supabase_realtime' and schemaname = 'public' and tablename in ('bets', 'bet_stakes'))
-- union all
-- select 10, 'Vilkårssjekken: gyldig og ugyldig',
--        public.bet_condition_valid('{"kind":"par","hole":4,"player":"11111111-0000-0000-0000-000000000001"}')
--        and not public.bet_condition_valid('{"kind":"par","hole":18,"player":"11111111-0000-0000-0000-000000000001"}')
--        and not public.bet_condition_valid('{"kind":"skins"}')
-- union all
-- select 11, 'resolve_bet avviser arrangør med innsats',
--        exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--                where n.nspname = 'public' and p.proname = 'resolve_bet'
--                  and p.prosrc like '%En annen arrangør må gjøre det%')
-- union all
-- select 12, 'Oppgjøret i hele poeng (bet_points_for leser payoutDecimals, standard 0)',
--        exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--                where n.nspname = 'public' and p.proname = 'bet_points_for'
--                  and p.prosrc like '%''payoutDecimals'', 0%')
-- order by nr;
--
-- Rolleprøven sql/lokal/012_prove.sql er KUN for lokal Postgres.


-- ===========================================================================
-- RULLEBAKKE (bare test). Fjerner tabellene og funksjonene, med alle veddemål.
-- Aktivitetslinjene (kind bet_*) står igjen i activity; slett dem for hånd om
-- ønskelig (append-only, så det må gjøres som postgres i SQL Editor).
-- ===========================================================================
-- begin;
-- do $$
-- declare t text;
-- begin
--   if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
--     foreach t in array array['bets', 'bet_stakes'] loop
--       if exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime'
--                  and schemaname = 'public' and tablename = t) then
--         execute format('alter publication supabase_realtime drop table public.%I', t);
--       end if;
--     end loop;
--   end if;
-- end $$;
-- drop function if exists public.mark_bets_closed(uuid[]);
-- drop function if exists public.settle_bet(uuid, text);
-- drop function if exists public.bet_outcome_known(public.bets);
-- drop function if exists public.resolve_bet(uuid, text);
-- drop function if exists public.place_bet_stake(uuid, text, integer);
-- drop function if exists public.create_bet(uuid, uuid, uuid, text, jsonb, uuid, text, integer);
-- drop function if exists public.bet_insert_stake(public.bets, uuid, text, integer);
-- drop function if exists public.bet_points(uuid, uuid);
-- drop function if exists public.bet_points_for(uuid, uuid);
-- drop table if exists public.bet_stakes, public.bets cascade;
-- drop function if exists public.bet_accepts_stakes(uuid);
-- drop function if exists public.bet_first_open_hole(uuid, uuid[], integer);
-- drop function if exists public.bet_rule(uuid, text, integer);
-- drop function if exists public.bet_condition_valid(jsonb);
-- commit;
