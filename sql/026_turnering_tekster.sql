-- ===========================================================================
-- 026 – «SESONG» BLIR «TURNERING» I FEILMELDINGENE – FORSLAG, IKKE KJØRT
-- ===========================================================================
-- Status: FORSLAG til godkjenning. IKKE KJØRT mot Supabase, verken test eller prod.
--
-- Hvorfor (besluttet 08.10.2026, fase 18): appen kaller sesong og konkurranse
-- «turnering». Fem feilmeldinger i databasen sier fortsatt «sesong», og tre av dem
-- vises for brukeren (P0002, 22023, 55000 sendes rett til appen).
--
-- Hva fila gjør: fem funksjoner byttes ut med create or replace, med NØYAKTIG samme
-- kropp, signatur og rettigheter som i 004, 012 og 017. Bare teksten i meldingene er
-- endret (SQLSTATE er den samme):
--   activate_season     'Fant ikke sesongen'                     → 'Fant ikke turneringen'
--                       'Bare arrangøren kan aktivere en sesong' → '… en turnering'
--   bet_points          'Fant ikke sesongen'                     → 'Fant ikke turneringen'
--   create_bet          'Veddemål krever en aktiv sesong …'      → '… en aktiv turnering …'
--   guard_competitions  'Sesongens konkurranse lages av sesongen'→ 'En serie med kvelder lages under «Ny turnering»'
--                       'Endre sesongen i stedet'                → 'Endre turneringen i stedet'
--   create_competition  'Sesongens konkurranse lages av sesongen'→ som over
-- Ingen tabeller, data, triggere eller policies endres. Triggeren på competitions
-- peker på guard_competitions og følger med uendret.
--
-- Mønsteret fra 001–025: én transaksjon, idempotent, revoke/grant etter hver funksjon.
-- ===========================================================================

begin;

-- --- activate_season (fra 004_sesong.sql, bare meldingsteksten endret) ---
create or replace function public.activate_season(p_season_id uuid)
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

  update public.seasons s
     set status = 'finished'
   where s.club_id = v_club and s.status = 'active' and s.id <> p_season_id;

  update public.seasons s
     set status = 'active'
   where s.id = p_season_id
  returning s.* into v_row;

  -- Ingen rad: RLS stoppet skrivingen (ikke arrangør).
  if v_row.id is null then
    raise exception 'Bare arrangøren kan aktivere en turnering' using errcode = '42501';
  end if;
  return v_row;
end;
$$;
revoke all on function public.activate_season(uuid) from public, anon;
grant execute on function public.activate_season(uuid) to authenticated;

-- --- bet_points (fra 012_veddemaal.sql, bare meldingsteksten endret) ---
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
    raise exception 'Fant ikke turneringen' using errcode = 'P0002';
  end if;
  return query select * from public.bet_points_for(p_season_id, p_member_id);
end;
$$;
revoke all on function public.bet_points(uuid, uuid) from public, anon;
grant execute on function public.bet_points(uuid, uuid) to authenticated;

-- --- create_bet (fra 012_veddemaal.sql, bare meldingsteksten endret) ---
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

-- --- guard_competitions (fra 017_fundament.sql, bare meldingsteksten endret) ---
create or replace function public.guard_competitions()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or pg_trigger_depth() > 1 then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.owner_id := case when new.club_id is null then auth.uid() end;
    if new.kind = 'season' or new.season_id is not null or new.is_main then
      raise exception 'En serie med kvelder lages under «Ny turnering»' using errcode = '22023';
    end if;
    if new.requires_purchase or new.entitlement_id is not null then
      raise exception 'Kjøp settes bare av serveren' using errcode = '42501';
    end if;
    return new;
  end if;

  if new.kind is distinct from old.kind or new.club_id is distinct from old.club_id
     or (new.owner_id is distinct from old.owner_id
         and not (new.owner_id is null
                  and not exists (select 1 from public.profiles p where p.id = old.owner_id)))
     or new.season_id is distinct from old.season_id
     or new.is_main is distinct from old.is_main then
    raise exception 'Type, eier og hovedturnering kan ikke endres her' using errcode = '42501';
  end if;
  if new.requires_purchase is distinct from old.requires_purchase
     or new.entitlement_id is distinct from old.entitlement_id then
    raise exception 'Kjøp settes bare av serveren' using errcode = '42501';
  end if;
  if old.season_id is not null
     and (new.name is distinct from old.name or new.status is distinct from old.status
          or new.rules is distinct from old.rules or new.entry is distinct from old.entry) then
    raise exception 'Endre turneringen i stedet' using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_competitions() from public, anon, authenticated;

-- --- create_competition (fra 017_fundament.sql, bare meldingsteksten endret) ---
create or replace function public.create_competition(
  p_kind       text,
  p_name       text,
  p_club_id    uuid  default null,
  p_entry      text  default 'listed',
  p_rules      jsonb default null,
  p_starts_on  date  default null,
  p_ends_on    date  default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_me public.profiles;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if p_kind is null or p_kind = 'season' then
    raise exception 'En serie med kvelder lages under «Ny turnering»' using errcode = '22023';
  end if;
  if p_club_id is not null and not public.is_club_organizer(p_club_id) then
    raise exception 'Bare en arrangør kan lage en konkurranse i klubben' using errcode = '42501';
  end if;

  v_me := public.ensure_profile();

  insert into public.competitions (kind, name, club_id, owner_id, status, entry, rules, starts_on, ends_on)
  values (p_kind, btrim(p_name), p_club_id, case when p_club_id is null then v_me.id end,
          'active', coalesce(p_entry, 'listed'), coalesce(p_rules, '{"version": 1}'::jsonb),
          p_starts_on, p_ends_on)
  returning id into v_id;

  if p_club_id is null then
    insert into public.competition_participants (competition_id, profile_id) values (v_id, v_me.id);
  end if;
  return v_id;
end;
$$;
revoke all on function public.create_competition(text, text, uuid, text, jsonb, date, date) from public, anon;
grant execute on function public.create_competition(text, text, uuid, text, jsonb, date, date) to authenticated;

commit;


-- ===========================================================================
-- KONTROLL (kjør i SQL Editor etter fila, som én kjøring). Alle rader skal ha ok = true.
-- ===========================================================================
-- with f as (
--   select p.proname, p.prosrc,
--          has_function_privilege('anon', p.oid, 'execute') as anon_kan
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public'
--     and p.proname in ('activate_season', 'bet_points', 'create_bet', 'guard_competitions', 'create_competition')
-- )
-- select 1 as nr, 'Alle fem funksjonene finnes' as sjekk, (select count(*) = 5 from f) as ok
-- union all
-- select 2, 'Ingen av meldingene sier «sesong» lenger',
--        (select bool_and(prosrc not like '%Fant ikke sesongen%' and prosrc not like '%aktivere en sesong%'
--                         and prosrc not like '%lages av sesongen%' and prosrc not like '%Endre sesongen%'
--                         and prosrc not like '%krever en aktiv sesong%') from f)
-- union all
-- select 3, 'De nye meldingene står der',
--        (select prosrc like '%Fant ikke turneringen%' from f where proname = 'activate_season')
--        and (select prosrc like '%Fant ikke turneringen%' from f where proname = 'bet_points')
--        and (select prosrc like '%krever en aktiv turnering%' from f where proname = 'create_bet')
--        and (select prosrc like '%Ny turnering%' and prosrc like '%Endre turneringen%' from f where proname = 'guard_competitions')
--        and (select prosrc like '%Ny turnering%' from f where proname = 'create_competition')
-- union all
-- select 4, 'anon kan ikke kjøre noen av dem', (select bool_and(not anon_kan) from f)
-- union all
-- select 5, 'Triggeren på competitions bruker fortsatt guard_competitions',
--        exists (select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid
--                where t.tgrelid = 'public.competitions'::regclass and p.proname = 'guard_competitions')
-- order by nr;


-- ===========================================================================
-- RULLEBAKKE (bare test): kjør de samme fem funksjonene fra 004, 012 og 017 på nytt.
-- ===========================================================================
