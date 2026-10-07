-- ===========================================================================
-- 020 – SPILL PÅ RUNDEN (FASE 14) – FORSLAG, IKKE KJØRT
-- ===========================================================================
-- Status: FORSLAG til godkjenning (ROADMAP B5, B10). IKKE KJØRT mot Supabase,
-- verken test eller prod. Prøvd mot en lokal, midlertidig Postgres
-- (sql/lokal/020_prove.sql). Krever 001–017 (017: profiles, løse runder,
-- round_participants, can_read_round / is_round_organizer / can_score /
-- owns_round_player for begge rundetyper). Bruker ikke 018/019.
--
-- Hva: spill oppå en runde (klubbrunde eller løs runde): skins, Nassau, Wolf,
-- bingo-bango-bongo og 2 mot 2 best ball. En runde kan ha flere spill, og
-- hvert spill har sine egne deltakere (noen kan være med i ett spill og ikke
-- et annet). Bare POENG (B10), aldri kroner.
--
-- Modellen:
--   * round_games: spillet (runde, type, innstillinger som jsonb, status).
--     Innstillingene er det spillet har overstyrt i malen for typen. Felt som
--     mangler, får malens verdi i regelmotoren (GolfgutuCore, Games.swift).
--     Ingen regelverdier i SQL.
--   * round_game_players: deltakerne i rekkefølge (seat, Wolf: tee-rekkefølgen)
--     og side (1/2) for Nassau og best ball.
--   * round_game_marks: manuelle markeringer per hull: Wolf-valget (partner,
--     alene, blind) og bingo / bango / bongo.
--   * round_game_results: oppgjøret i hele poeng per deltaker, skrevet når
--     spillet gjøres opp. Summen per spill er null.
--
-- Poengbanken: EGEN PER RUNDE (round_game_results), ikke 012-banken. Grunner:
--   1. 012-banken er per sesong og klubbmedlem (bet_stakes.member_id ->
--      club_members, bets.season_id not null). En løs runde har verken klubb
--      eller sesong, og gjester er ikke medlemmer.
--   2. Spill er nullsum innenfor runden. Det trengs ingen startbeholdning,
--      innsats eller «ledig saldo» (ingen setter poeng på forhånd), så 012s
--      sperrer og tak har ingenting å gjøre her.
--   3. Spillene påvirker ikke veddemålstabellen eller jakkeracet. Skal de
--      telle i en sesongs bank senere, kan bet_points_for legge til summen fra
--      round_game_results for klubbrundene i sesongen (eget forslag).
-- Oppgjøret LAGRES (bevisst valg, som playing_handicap): regnestykket finnes
-- bare i regelmotoren (Swift), og databasen kan ikke regne skins, Nassau,
-- press og Wolf selv. Rådataene (scorer, oppsett, markeringer) ligger der, så
-- oppgjøret kan alltid regnes på nytt i appen. settle_round_game sjekker at
-- det går i null, at alle deltakerne er med og at runden er ferdig.
-- Restrisiko (som settle_bet i 012): databasen sjekker ikke selve tallene.
--
-- RLS via deltakelse (017): du ser spillene i runder du kan se
-- (can_read_round: klubbmedlem, eier eller deltaker i en løs runde, eller via
-- en konkurranse). All skriving går gjennom RPC-ene under, hver i én
-- transaksjon. Tabellene har bare SELECT for authenticated, ingenting for anon.
--
--   create_round_game   spillet med deltakerne. Arrangøren / eieren, eller en
--                       spiller i runden som selv er med i spillet.
--   delete_round_game   den som laget spillet, eller arrangøren / eieren.
--                       Ikke når spillet er gjort opp.
--   set_round_game_mark markering på et hull (eller fjerne den). Den som kan
--                       føre for en av deltakerne (kanFore: markøren,
--                       spilleren selv, arrangøren / eieren).
--   settle_round_game   oppgjøret når runden er ferdig (låst eller avkortet).
--                       Den som laget spillet, eller arrangøren / eieren.
--                       Arrangøren / eieren kan gjøre opp på nytt (rettet score).
--
-- Mønsteret fra 001–017: én transaksjon, idempotent, `set search_path = ''`,
-- `revoke … from public, anon` ETTER hver create or replace.
-- ===========================================================================

begin;


-- ===========================================================================
-- 1. TABELLER
-- ===========================================================================

-- --- round_games: spillet ----------------------------------------------------
-- kind: skins | nassau | wolf | bbb | best_ball (GameKind i regelmotoren).
-- settings: det spillet har overstyrt i malen (tomt objekt = malen).
create table if not exists public.round_games (
  id          uuid primary key default gen_random_uuid(),
  round_id    uuid not null references public.rounds(id) on delete cascade,
  kind        text not null check (kind in ('skins', 'nassau', 'wolf', 'bbb', 'best_ball')),
  settings    jsonb not null default '{}'::jsonb,
  status      text not null default 'open' check (status in ('open', 'settled')),
  created_by  uuid references public.profiles(id) on delete set null,
  settled_by  uuid references public.profiles(id) on delete set null,
  settled_at  timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint round_games_id_round_key unique (id, round_id),
  constraint round_games_settings_object
    check (jsonb_typeof(settings) = 'object' and pg_column_size(settings) <= 4096),
  constraint round_games_settled_at check ((status = 'settled') = (settled_at is not null))
);
comment on table public.round_games is
  'Spill på runden (fase 14). settings = overstyringer av malen i regelmotoren. '
  'Skrives bare via create_round_game, delete_round_game og settle_round_game.';
create index if not exists round_games_round_idx on public.round_games (round_id, created_at);

drop trigger if exists round_games_set_updated_at on public.round_games;
create trigger round_games_set_updated_at before update on public.round_games
  for each row execute function public.set_updated_at();

-- --- round_game_players: deltakerne -------------------------------------------
-- player_id er spillerens id i runden (round_players.member_id: klubbmedlem
-- eller deltaker i en løs runde). seat er rekkefølgen (1..n, Wolf: tee-
-- rekkefølgen). side 1/2 bare for Nassau og best ball.
create table if not exists public.round_game_players (
  game_id    uuid not null,
  round_id   uuid not null,
  player_id  uuid not null,
  seat       smallint not null check (seat between 1 and 8),
  side       smallint check (side in (1, 2)),
  primary key (game_id, player_id),
  constraint round_game_players_seat_key unique (game_id, seat),
  constraint round_game_players_game_fk foreign key (game_id, round_id)
    references public.round_games (id, round_id) on delete cascade,
  constraint round_game_players_player_fk foreign key (round_id, player_id)
    references public.round_players (round_id, member_id) on delete cascade
);
comment on table public.round_game_players is
  'Deltakerne i et spill på runden, i rekkefølge (seat) og med side (Nassau, best ball).';
create index if not exists round_game_players_round_idx on public.round_game_players (round_id);

-- --- round_game_marks: manuelle markeringer per hull ---------------------------
-- award = wolf: Wolf-valget. wolf_mode partner (player_id = partneren), alone
-- eller blind (player_id tom). award = bingo / bango / bongo: player_id fikk det.
-- Én rad per spill, hull og markering.
create table if not exists public.round_game_marks (
  game_id     uuid not null,
  round_id    uuid not null,
  hole_index  smallint not null check (hole_index between 0 and 17),
  award       text not null check (award in ('wolf', 'bingo', 'bango', 'bongo')),
  player_id   uuid,
  wolf_mode   text check (wolf_mode in ('partner', 'alone', 'blind')),
  updated_by  uuid references public.profiles(id) on delete set null,
  updated_at  timestamptz not null default now(),
  primary key (game_id, hole_index, award),
  constraint round_game_marks_game_fk foreign key (game_id, round_id)
    references public.round_games (id, round_id) on delete cascade,
  constraint round_game_marks_player_fk foreign key (game_id, player_id)
    references public.round_game_players (game_id, player_id) on delete cascade,
  constraint round_game_marks_shape check (
    case when award = 'wolf'
         then wolf_mode is not null and ((wolf_mode = 'partner') = (player_id is not null))
         else wolf_mode is null and player_id is not null end)
);
comment on table public.round_game_marks is
  'Wolf-valg og bingo-bango-bongo per hull. Skrives bare via set_round_game_mark.';
create index if not exists round_game_marks_round_idx on public.round_game_marks (round_id);

-- --- round_game_results: oppgjøret (poengbanken per runde) -----------------------
create table if not exists public.round_game_results (
  game_id    uuid not null,
  round_id   uuid not null,
  player_id  uuid not null,
  points     integer not null check (points between -100000 and 100000),
  primary key (game_id, player_id),
  constraint round_game_results_game_fk foreign key (game_id, round_id)
    references public.round_games (id, round_id) on delete cascade,
  constraint round_game_results_player_fk foreign key (game_id, player_id)
    references public.round_game_players (game_id, player_id) on delete cascade
);
comment on table public.round_game_results is
  'Oppgjøret av et spill i hele poeng (B10). Summen per spill er null. Skrives bare via settle_round_game.';
create index if not exists round_game_results_round_idx on public.round_game_results (round_id);


-- ===========================================================================
-- 2. RLS OG RETTIGHETER
-- ===========================================================================
alter table public.round_games        enable row level security;
alter table public.round_game_players enable row level security;
alter table public.round_game_marks   enable row level security;
alter table public.round_game_results enable row level security;

do $$
declare
  p record;
begin
  for p in
    select policyname, tablename from pg_policies
    where schemaname = 'public'
      and tablename in ('round_games', 'round_game_players', 'round_game_marks', 'round_game_results')
  loop
    execute format('drop policy if exists %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

-- Du ser spillene i rundene du kan se (017: klubbmedlem, eier eller deltaker i
-- en løs runde, eller via en konkurranse). Kladder bare for den som ser kladden.
create policy round_games_select on public.round_games
  for select to authenticated using (public.can_read_round(round_id));
create policy round_game_players_select on public.round_game_players
  for select to authenticated using (public.can_read_round(round_id));
create policy round_game_marks_select on public.round_game_marks
  for select to authenticated using (public.can_read_round(round_id));
create policy round_game_results_select on public.round_game_results
  for select to authenticated using (public.can_read_round(round_id));

do $$
declare
  t text;
begin
  foreach t in array array['round_games', 'round_game_players', 'round_game_marks', 'round_game_results'] loop
    execute format('revoke all on table public.%I from public, anon, authenticated', t);
    execute format('grant select on table public.%I to authenticated', t);
  end loop;
end $$;


-- ===========================================================================
-- 3. HJELPEFUNKSJONER
-- ===========================================================================

-- --- round_game_shape_ok: deltakere og sider passer typen -------------------------
-- Samme grenser som GameKind.playerRange og Games.problems i regelmotoren
-- (definisjonen av spillet, ikke regelverdier): skins 2–8, Nassau 2–4 (to
-- sider med 1–2 hver), Wolf 3–5, bingo-bango-bongo 2–8, best ball 2 mot 2.
-- p_sides: sidene i deltakernes rekkefølge (null = ingen side).
create or replace function public.round_game_shape_ok(p_kind text, p_sides smallint[])
returns boolean
language sql
immutable
set search_path = ''
as $$
  with s as (
    select coalesce(cardinality(p_sides), 0) as n,
           (select count(*) from unnest(p_sides) x where x = 1) as a,
           (select count(*) from unnest(p_sides) x where x = 2) as b,
           (select count(*) from unnest(p_sides) x where x is null) as blank
  )
  select case p_kind
    when 'skins'     then n between 2 and 8 and blank = n
    when 'bbb'       then n between 2 and 8 and blank = n
    when 'wolf'      then n between 3 and 5 and blank = n
    when 'nassau'    then n between 2 and 4 and a + b = n and a between 1 and 2 and b between 1 and 2
    when 'best_ball' then n = 4 and a = 2 and b = 2
    else false
  end
  from s;
$$;
revoke all on function public.round_game_shape_ok(text, smallint[]) from public, anon, authenticated;

-- --- can_mark_round_game: kan jeg føre for en av deltakerne? --------------------
create or replace function public.can_mark_round_game(p_game_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.round_game_players gp
    where gp.game_id = p_game_id and public.can_score(gp.round_id, gp.player_id)
  );
$$;
revoke all on function public.can_mark_round_game(uuid) from public, anon, authenticated;


-- ===========================================================================
-- 4. RPC-ER (én transaksjon hver)
-- ===========================================================================

-- --- create_round_game: spillet og deltakerne -----------------------------------
-- p_players: [{"player_id": "<id i runden>", "side": 1|2|null}, …] i rekkefølge
-- (Wolf: tee-rekkefølgen, første er wolf på rundens første hull).
-- p_settings: overstyringer av malen (tomt objekt = malen).
-- Hvem: arrangøren / eieren av runden, eller en spiller i runden som selv er
-- med i spillet. Ikke i en låst runde. Høyst 10 spill per runde.
create or replace function public.create_round_game(
  p_round_id  uuid,
  p_kind      text,
  p_settings  jsonb,
  p_players   jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me      public.profiles;
  v_status  text;
  v_game    uuid;
  v_ids     uuid[];
  v_sides   smallint[];
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select r.status into v_status from public.rounds r where r.id = p_round_id;
  if v_status is null or not public.can_read_round(p_round_id) then
    raise exception 'Fant ikke runden' using errcode = 'P0002';
  end if;
  if v_status = 'locked' then
    raise exception 'Runden er låst. Spill legges til før eller under runden.' using errcode = '55000';
  end if;
  if p_kind is null or p_kind not in ('skins', 'nassau', 'wolf', 'bbb', 'best_ball') then
    raise exception 'Ukjent spill' using errcode = '22023';
  end if;
  if p_settings is null or jsonb_typeof(p_settings) <> 'object' or pg_column_size(p_settings) > 4096 then
    raise exception 'Innstillingene må være et objekt' using errcode = '22023';
  end if;
  if p_players is null or jsonb_typeof(p_players) <> 'array' or jsonb_array_length(p_players) > 8 then
    raise exception 'Spillerlista må være en liste med høyst 8 spillere' using errcode = '22023';
  end if;

  begin
    select array_agg(nullif(e ->> 'player_id', '')::uuid order by i),
           array_agg((e ->> 'side')::smallint order by i)
      into v_ids, v_sides
    from jsonb_array_elements(p_players) with ordinality as t(e, i);
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'Ugyldig spiller eller side' using errcode = '22023';
  end;

  if v_ids is null or array_position(v_ids, null) is not null
     or (select count(distinct x) from unnest(v_ids) x) <> cardinality(v_ids) then
    raise exception 'Hver spiller kan bare være med én gang' using errcode = '22023';
  end if;
  if not public.round_game_shape_ok(p_kind, v_sides) then
    raise exception 'Antall spillere eller sidene passer ikke spillet' using errcode = '22023';
  end if;
  if exists (select 1 from unnest(v_ids) x
             where not exists (select 1 from public.round_players rp
                               where rp.round_id = p_round_id and rp.member_id = x)) then
    raise exception 'Alle i spillet må være med i runden' using errcode = '22023';
  end if;
  if not public.is_round_organizer(p_round_id)
     and not exists (select 1 from unnest(v_ids) x where public.owns_round_player(p_round_id, x)) then
    raise exception 'Du kan bare lage spill du selv er med i' using errcode = '42501';
  end if;
  if (select count(*) from public.round_games g where g.round_id = p_round_id) >= 10 then
    raise exception 'Runden har allerede 10 spill' using errcode = '55000';
  end if;

  v_me := public.ensure_profile();

  insert into public.round_games (round_id, kind, settings, created_by)
  values (p_round_id, p_kind, p_settings, v_me.id)
  returning id into v_game;

  insert into public.round_game_players (game_id, round_id, player_id, seat, side)
  select v_game, p_round_id, v_ids[i], i, v_sides[i]
  from generate_subscripts(v_ids, 1) i;

  return v_game;
end;
$$;
revoke all on function public.create_round_game(uuid, text, jsonb, jsonb) from public, anon;
grant execute on function public.create_round_game(uuid, text, jsonb, jsonb) to authenticated;

-- --- delete_round_game: fjerne et spill som ikke er gjort opp ----------------------
create or replace function public.delete_round_game(p_game_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_game public.round_games;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select * into v_game from public.round_games g where g.id = p_game_id for update;
  if v_game.id is null or not public.can_read_round(v_game.round_id) then
    raise exception 'Fant ikke spillet' using errcode = 'P0002';
  end if;
  if v_game.created_by is distinct from auth.uid() and not public.is_round_organizer(v_game.round_id) then
    raise exception 'Bare den som laget spillet, eller arrangøren, kan fjerne det' using errcode = '42501';
  end if;
  if v_game.status = 'settled' then
    raise exception 'Spillet er gjort opp og kan ikke fjernes' using errcode = '55000';
  end if;
  delete from public.round_games g where g.id = p_game_id;
end;
$$;
revoke all on function public.delete_round_game(uuid) from public, anon;
grant execute on function public.delete_round_game(uuid) to authenticated;

-- --- set_round_game_mark: Wolf-valg eller bingo / bango / bongo på et hull ----------
-- p_award: wolf | bingo | bango | bongo. Wolf: p_wolf_mode partner (med
-- p_player_id = partneren), alone eller blind. Partneren kan ikke være wolfen
-- på hullet (deltakerne etter tur: seat = hull mod antall + 1).
-- p_player_id og p_wolf_mode begge tomme: markeringen fjernes.
-- Hvem: den som kan føre for en av deltakerne (kanFore). Bare åpne spill.
-- Returnerer raden (jsonb), eller null når den ble fjernet.
create or replace function public.set_round_game_mark(
  p_game_id    uuid,
  p_hole       integer,
  p_award      text,
  p_player_id  uuid default null,
  p_wolf_mode  text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_game   public.round_games;
  v_holes  integer;
  v_n      integer;
  v_wolf   uuid;
  v_row    public.round_game_marks;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select * into v_game from public.round_games g where g.id = p_game_id for update;
  if v_game.id is null or not public.can_read_round(v_game.round_id) then
    raise exception 'Fant ikke spillet' using errcode = 'P0002';
  end if;
  if not public.can_mark_round_game(p_game_id) then
    raise exception 'Du kan ikke føre i dette spillet' using errcode = '42501';
  end if;
  if v_game.status = 'settled' then
    raise exception 'Spillet er gjort opp' using errcode = '55000';
  end if;
  select r.hole_count into v_holes from public.rounds r where r.id = v_game.round_id;
  if p_hole is null or p_hole < 0 or p_hole >= v_holes then
    raise exception 'Hullet finnes ikke i runden' using errcode = '22023';
  end if;
  if not ((v_game.kind = 'wolf' and p_award = 'wolf')
          or (v_game.kind = 'bbb' and p_award in ('bingo', 'bango', 'bongo'))) then
    raise exception 'Markeringen passer ikke spillet' using errcode = '22023';
  end if;

  if p_player_id is null and p_wolf_mode is null then
    delete from public.round_game_marks m
     where m.game_id = p_game_id and m.hole_index = p_hole and m.award = p_award;
    return null;
  end if;

  if p_player_id is not null and not exists (select 1 from public.round_game_players gp
                                             where gp.game_id = p_game_id and gp.player_id = p_player_id) then
    raise exception 'Spilleren er ikke med i spillet' using errcode = '22023';
  end if;
  if p_award = 'wolf' then
    if p_wolf_mode is null or p_wolf_mode not in ('partner', 'alone', 'blind')
       or (p_wolf_mode = 'partner') <> (p_player_id is not null) then
      raise exception 'Wolf-valget må være partner (med spiller), alene eller blind' using errcode = '22023';
    end if;
    select count(*) into v_n from public.round_game_players gp where gp.game_id = p_game_id;
    select gp.player_id into v_wolf from public.round_game_players gp
     where gp.game_id = p_game_id and gp.seat = (p_hole % v_n) + 1;
    if p_player_id = v_wolf then
      raise exception 'Wolfen kan ikke velge seg selv som partner' using errcode = '22023';
    end if;
  elsif p_wolf_mode is not null or p_player_id is null then
    raise exception 'Bingo, bango og bongo trenger en spiller' using errcode = '22023';
  end if;

  insert into public.round_game_marks (game_id, round_id, hole_index, award, player_id, wolf_mode, updated_by, updated_at)
  values (p_game_id, v_game.round_id, p_hole, p_award, p_player_id, p_wolf_mode, auth.uid(), now())
  on conflict (game_id, hole_index, award) do update
    set player_id = excluded.player_id, wolf_mode = excluded.wolf_mode,
        updated_by = excluded.updated_by, updated_at = excluded.updated_at
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;
revoke all on function public.set_round_game_mark(uuid, integer, text, uuid, text) from public, anon;
grant execute on function public.set_round_game_mark(uuid, integer, text, uuid, text) to authenticated;

-- --- settle_round_game: oppgjøret når runden er ferdig ---------------------------
-- p_points: {"<player_id>": <hele poeng>, …} for ALLE deltakerne, summen null
-- (Games.evaluate i appen). Runden må være låst eller avkortet. Den som laget
-- spillet, eller arrangøren / eieren. Et gjort opp spill kan bare gjøres opp på
-- nytt av arrangøren / eieren (rettet score); radene byttes da ut.
-- Restrisiko: tallene regnes i appen, databasen sjekker formen, ikke regnestykket.
create or replace function public.settle_round_game(p_game_id uuid, p_points jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_game     public.round_games;
  v_round    public.rounds;
  v_players  integer;
  v_keys     integer;
  v_sum      bigint;
  v_me       public.profiles;
  v_org      boolean;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select * into v_game from public.round_games g where g.id = p_game_id for update;
  if v_game.id is null or not public.can_read_round(v_game.round_id) then
    raise exception 'Fant ikke spillet' using errcode = 'P0002';
  end if;
  v_org := public.is_round_organizer(v_game.round_id);
  if not v_org and v_game.created_by is distinct from auth.uid() then
    raise exception 'Bare den som laget spillet, eller arrangøren, kan gjøre det opp' using errcode = '42501';
  end if;
  if v_game.status = 'settled' and not v_org then
    raise exception 'Spillet er allerede gjort opp. Arrangøren kan gjøre det opp på nytt.' using errcode = '55000';
  end if;
  select * into v_round from public.rounds r where r.id = v_game.round_id;
  if v_round.status <> 'locked' and v_round.cut_rule is null then
    raise exception 'Spillet gjøres opp når runden er låst eller avkortet' using errcode = '55000';
  end if;
  if p_points is null or jsonb_typeof(p_points) <> 'object' then
    raise exception 'Oppgjøret må være et objekt med poeng per spiller' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_each(p_points) e
             where jsonb_typeof(e.value) <> 'number'
                or (e.value::text)::numeric <> trunc((e.value::text)::numeric)
                or abs((e.value::text)::numeric) > 100000
                or e.key !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then
    raise exception 'Poengene må være hele tall per spiller' using errcode = '22023';
  end if;
  select count(*) into v_players from public.round_game_players gp where gp.game_id = p_game_id;
  select count(*), coalesce(sum((e.value::text)::numeric), 0)::bigint into v_keys, v_sum
  from jsonb_each(p_points) e
  join public.round_game_players gp on gp.game_id = p_game_id and gp.player_id = e.key::uuid;
  if v_keys <> v_players or (select count(*) from jsonb_object_keys(p_points)) <> v_players then
    raise exception 'Oppgjøret må ha med alle i spillet, og bare dem' using errcode = '22023';
  end if;
  if v_sum <> 0 then
    raise exception 'Oppgjøret må gå i null' using errcode = '22023';
  end if;

  v_me := public.ensure_profile();
  delete from public.round_game_results r where r.game_id = p_game_id;
  insert into public.round_game_results (game_id, round_id, player_id, points)
  select p_game_id, v_game.round_id, e.key::uuid, (e.value::text)::integer
  from jsonb_each(p_points) e;
  update public.round_games g
     set status = 'settled', settled_by = v_me.id, settled_at = now()
   where g.id = p_game_id;
end;
$$;
revoke all on function public.settle_round_game(uuid, jsonb) from public, anon;
grant execute on function public.settle_round_game(uuid, jsonb) to authenticated;


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
  foreach t in array array['round_games', 'round_game_players', 'round_game_marks', 'round_game_results'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
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
--   where n.nspname = 'public' and c.relkind = 'r'
--     and c.relname in ('round_games', 'round_game_players', 'round_game_marks', 'round_game_results')
-- ),
-- f as (
--   select p.proname,
--          has_function_privilege('anon', p.oid, 'execute') as anon_kan,
--          has_function_privilege('authenticated', p.oid, 'execute') as auth_kan
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public'
--     and p.proname in ('round_game_shape_ok', 'can_mark_round_game', 'create_round_game',
--                       'delete_round_game', 'set_round_game_mark', 'settle_round_game')
-- ),
-- g as (
--   select table_name, string_agg(privilege_type, ', ' order by privilege_type) as rettigheter
--   from information_schema.role_table_grants
--   where table_schema = 'public' and grantee = 'authenticated'
--     and table_name in ('round_games', 'round_game_players', 'round_game_marks', 'round_game_results')
--   group by 1
-- )
-- select 1 as nr, 'De fire tabellene finnes med RLS' as sjekk,
--        (select count(*) = 4 and bool_and(relrowsecurity) from t) as ok
-- union all
-- select 2, 'anon har ingen tabellrettigheter',
--        not exists (select 1 from information_schema.role_table_grants
--                    where table_schema = 'public' and grantee in ('anon', 'PUBLIC')
--                      and table_name in ('round_games', 'round_game_players', 'round_game_marks', 'round_game_results'))
-- union all
-- select 3, 'authenticated: bare SELECT på alle fire',
--        (select count(*) = 4 and bool_and(rettigheter = 'SELECT') from g)
-- union all
-- select 4, 'Alle seks funksjonene finnes', (select count(*) = 6 from f)
-- union all
-- select 5, 'anon kan ikke kjøre noen spillfunksjon', not exists (select 1 from f where anon_kan)
-- union all
-- select 6, 'authenticated kan kjøre de fire RPC-ene',
--        (select count(*) = 4 and bool_and(auth_kan) from f
--         where proname in ('create_round_game', 'delete_round_game', 'set_round_game_mark', 'settle_round_game'))
-- union all
-- select 7, 'authenticated kan ikke kjøre de indre hjelperne',
--        not exists (select 1 from f where auth_kan and proname in ('round_game_shape_ok', 'can_mark_round_game'))
-- union all
-- select 8, 'Policyene bruker can_read_round (deltakelse, 017)',
--        (select count(*) = 4 from pg_policies
--         where schemaname = 'public' and cmd = 'SELECT' and qual like '%can_read_round%'
--           and tablename in ('round_games', 'round_game_players', 'round_game_marks', 'round_game_results'))
-- union all
-- select 9, 'Realtime for de fire tabellene',
--        (select count(*) = 4 from pg_publication_tables
--         where pubname = 'supabase_realtime' and schemaname = 'public'
--           and tablename in ('round_games', 'round_game_players', 'round_game_marks', 'round_game_results'))
-- union all
-- select 10, 'Formsjekken: gyldig og ugyldig',
--        public.round_game_shape_ok('best_ball', '{1,1,2,2}') and public.round_game_shape_ok('wolf', '{null,null,null,null}')
--        and not public.round_game_shape_ok('best_ball', '{1,1,1,2}') and not public.round_game_shape_ok('wolf', '{null,null}')
--        and not public.round_game_shape_ok('kroner', '{null,null}')
-- union all
-- select 11, 'Oppgjøret må gå i null (settle_round_game)',
--        exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--                where n.nspname = 'public' and p.proname = 'settle_round_game'
--                  and p.prosrc like '%Oppgjøret må gå i null%')
-- order by nr;
--
-- Rolleprøven sql/lokal/020_prove.sql er KUN for lokal Postgres.


-- ===========================================================================
-- RULLEBAKKE (bare test). Fjerner tabellene og funksjonene, med alle spill og
-- oppgjør. Rører ikke runder, scorer eller 012-banken.
-- ===========================================================================
-- begin;
-- do $$
-- declare t text;
-- begin
--   if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
--     foreach t in array array['round_games', 'round_game_players', 'round_game_marks', 'round_game_results'] loop
--       if exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime'
--                  and schemaname = 'public' and tablename = t) then
--         execute format('alter publication supabase_realtime drop table public.%I', t);
--       end if;
--     end loop;
--   end if;
-- end $$;
-- drop function if exists public.settle_round_game(uuid, jsonb);
-- drop function if exists public.set_round_game_mark(uuid, integer, text, uuid, text);
-- drop function if exists public.delete_round_game(uuid);
-- drop function if exists public.create_round_game(uuid, text, jsonb, jsonb);
-- drop table if exists public.round_game_results, public.round_game_marks,
--                      public.round_game_players, public.round_games cascade;
-- drop function if exists public.can_mark_round_game(uuid);
-- drop function if exists public.round_game_shape_ok(text, smallint[]);
-- commit;
