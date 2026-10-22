-- 072: tilleggspoeng (1.0.2). Ikke kjørt.
--
-- Ønsket (Thomas etter klubbkvelden 22.10.2026): arrangøren kan gi en spiller poeng for hånd i
-- turneringstabellen (Tavla), med en grunn. Første bruk: «CP knockout challenge» 22.10, spilt utenfor
-- appen (Næsset og Rostad 1 poeng, Strypet og JonasH 0,5).
--
-- Hva fila gjør (bare legg til, docs/utgivelser.md punkt 4):
--   1. Ny tabell point_adjustments (id, club_id, season_id, member_id, event_id null, points,
--      reason, created_by, created_at, updated_at).
--        * points: numeric(5,2), ikke 0, mellom −100 og 100. Halve (og kvarte) poeng går. Negative
--          er lov: en straff eller en rettelse av poeng gitt for mye, uten å slette historikken.
--        * reason: 1–80 tegn (trimmet), vist for spillerne.
--        * season_id peker på turneringsraden (competitions(season_id, club_id), som events og bets
--          etter 035) og slettes med turneringen (cascade).
--        * member_id: et medlem i samme klubb (club_members(id, club_id)), slettes med medlemmet.
--        * event_id (valgfri): en kveld i samme klubb; kvelden må høre til samme sesong (triggeren).
--          Slettes kvelden, blir event_id tom og poengene står.
--        * created_by settes av triggeren (din rad i klubben). id, klubb, sesong, created_by og
--          created_at kan ikke endres.
--   2. RLS: lese for medlemmer av klubben (samme som tavla_data), skrive og slette for rettigheten
--      tournaments (044). Ingen rettigheter for anon.
--   3. tavla_data (048) og tv_board_data (048) får et nytt felt 'adjustments' (radene for sesongen,
--      eldste først). Ellers er svaret helt likt; gamle bygg ser ikke feltet. TV og «Del tavla»
--      (dashdash18.com) regner da samme total som appen.
--
-- Tabellen regnes fortsatt på telefonen (GolfgutuCore `Season`, `adjustments`): tilleggspoengene
-- legges på totalen ved siden av sidepremiene, uvektet, og strykes aldri av «beste N».
--
-- Krever 001, 035, 044, 048 og 059. Én transaksjon, idempotent. Kontroll og rullebakke nederst.
--
-- Etter kjøring, CP knockout challenge 22.10 (finn id-ene først; navnene står i display_name):
--   insert into public.point_adjustments (club_id, season_id, member_id, event_id, points, reason)
--   select c.club_id, c.season_id, m.id, e.id, v.points, 'CP knockout challenge'
--     from public.competitions c
--     join public.clubs k on k.id = c.club_id and k.name = 'Golfgutu Invitational'
--     join (values ('Næsset', 1.0), ('Rostad', 1.0), ('Strypet', 0.5), ('JonasH', 0.5)) v(name, points) on true
--     join public.club_members m on m.club_id = c.club_id and m.display_name = v.name
--     left join public.events e on e.season_id = c.season_id and e.event_date = date '2026-10-22'
--    where c.name = 'Golfgutu Invitational 2026';
--   -- Skal gi 4 rader. Eller legg dem inn i appen: Turneringen → Tilleggspoeng.

begin;

-- ===========================================================================
-- 1. TABELLEN
-- ===========================================================================
create table if not exists public.point_adjustments (
  id          uuid primary key default gen_random_uuid(),
  club_id     uuid not null references public.clubs(id) on delete cascade,
  season_id   uuid not null,
  member_id   uuid not null,
  event_id    uuid,
  points      numeric(5,2) not null check (points <> 0 and points between -100 and 100),
  reason      text not null check (char_length(btrim(reason)) between 1 and 80),
  created_by  uuid references public.club_members(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint point_adjustments_season_fk foreign key (season_id, club_id)
    references public.competitions (season_id, club_id) on delete cascade,
  constraint point_adjustments_member_fk foreign key (member_id, club_id)
    references public.club_members (id, club_id) on delete cascade,
  constraint point_adjustments_event_fk foreign key (event_id, club_id)
    references public.events (id, club_id) on delete set null (event_id)
);
comment on table public.point_adjustments is
  'Tilleggspoeng (072): poeng arrangøren gir en spiller for hånd i turneringstabellen, med en grunn. '
  'Legges på totalen ved siden av sidepremiene (regnes i appen). Negative = straff eller rettelse. '
  'event_id = kvelden de hører til (valgfri, bare til visning).';
create index if not exists point_adjustments_season_idx on public.point_adjustments (season_id);
create index if not exists point_adjustments_member_idx on public.point_adjustments (member_id);
create index if not exists point_adjustments_event_idx on public.point_adjustments (event_id) where event_id is not null;

drop trigger if exists point_adjustments_set_updated_at on public.point_adjustments;
create trigger point_adjustments_set_updated_at before update on public.point_adjustments
  for each row execute function public.set_updated_at();

-- Kvelden må høre til sesongen. created_by settes her. Nøklene og opprettet kan ikke endres.
create or replace function private.point_adjustments_before_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.created_by := public.my_member_id(new.club_id);
    new.created_at := now();
  elsif (new.id, new.club_id, new.season_id, new.created_by, new.created_at)
        is distinct from (old.id, old.club_id, old.season_id, old.created_by, old.created_at) then
    raise exception 'Tilleggspoengets turnering kan ikke endres' using errcode = '42501';
  end if;
  new.reason := btrim(new.reason);
  if new.event_id is not null and not exists (
       select 1 from public.events e where e.id = new.event_id and e.season_id = new.season_id) then
    raise exception 'Kvelden hører ikke til turneringen' using errcode = '23514';
  end if;
  return new;
end;
$$;
revoke all on function private.point_adjustments_before_write() from public, anon, authenticated;

drop trigger if exists point_adjustments_before_write on public.point_adjustments;
create trigger point_adjustments_before_write before insert or update on public.point_adjustments
  for each row execute function private.point_adjustments_before_write();


-- ===========================================================================
-- 2. RLS OG RETTIGHETER
-- ===========================================================================
alter table public.point_adjustments enable row level security;

revoke all on table public.point_adjustments from public, anon, authenticated;
grant select, insert, update, delete on table public.point_adjustments to authenticated;
grant all on table public.point_adjustments to service_role;

drop policy if exists point_adjustments_select on public.point_adjustments;
create policy point_adjustments_select on public.point_adjustments
  for select to authenticated using (public.is_club_member(club_id));

drop policy if exists point_adjustments_insert on public.point_adjustments;
create policy point_adjustments_insert on public.point_adjustments
  for insert to authenticated with check (private.has_club_right(club_id, 'tournaments'));

drop policy if exists point_adjustments_update on public.point_adjustments;
create policy point_adjustments_update on public.point_adjustments
  for update to authenticated
  using (private.has_club_right(club_id, 'tournaments'))
  with check (private.has_club_right(club_id, 'tournaments'));

drop policy if exists point_adjustments_delete on public.point_adjustments;
create policy point_adjustments_delete on public.point_adjustments
  for delete to authenticated using (private.has_club_right(club_id, 'tournaments'));


-- ===========================================================================
-- 3. TAVLA OG TV: FELTET 'adjustments'
-- ===========================================================================
-- Som i 048, med tilleggspoengene for sesongen. Alt annet i svaret er likt.
create or replace function public.tavla_data(p_season_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_club uuid;
  v_events uuid[];
  v_rounds uuid[];
  v_courses uuid[];
begin
  select s.club_id into v_club from public.seasons s where s.id = p_season_id;
  if v_club is null or not public.is_club_member(v_club) then
    raise exception 'Fant ikke sesongen' using errcode = 'P0002';
  end if;

  select coalesce(array_agg(e.id), '{}') into v_events
    from public.events e where e.season_id = p_season_id;

  select coalesce(array_agg(r.id), '{}') into v_rounds
    from public.rounds r
   where r.event_id = any (v_events)
     and r.status in ('active', 'locked')
     and public.can_read_round(r.id);

  select coalesce(array_agg(c.id), '{}') into v_courses
    from public.courses c
   where c.id in (select r.course_id from public.rounds r where r.id = any (v_rounds))
     and (c.club_id is null or public.is_club_member(c.club_id));

  return jsonb_build_object(
    'events', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select e.id, e.club_id, e.season_id, e.event_date, e.start_time, e.venue, e.note
          from public.events e where e.id = any (v_events)) x),
    'members', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select m.id, m.club_id, m.user_id, m.display_name, m.handicap_index, m.seed_group,
               m.is_organizer, m.is_treasurer, m.status, m.avatar_path
          from public.club_members m where m.club_id = v_club) x),
    'rounds', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select r.id, r.club_id, r.event_id, r.course_id, r.round_no, r.name, r.status, r.hole_count,
               r.first_hole, r.tee_time, r.format, r.handicap_allowance, r.external_handicap, r.weight,
               r.ld_enabled, r.ld_hole_index, r.kp_enabled, r.kp_hole_index, r.cut_rule, r.cut_after,
               r.par_confirmed_by, r.par_confirmed_at, r.started_at, r.locked_at, r.venue,
               r.tee_id, r.tee_name, r.course_rating, r.slope_rating, r.tee_par,
               r.counts, r.points_table, r.hide_last_holes, r.kind, r.playoff_for, r.playoff_holes,
               r.rules_snapshot, r.holes_snapshot, r.snapshot_at, r.snapshot_source
          from public.rounds r where r.id = any (v_rounds)) x),
    'round_holes', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select h.round_id, h.hole_index, h.par, h.stroke_index, h.length_m
          from public.round_holes h where h.round_id = any (v_rounds)) x),
    'round_competitions', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select c.id, c.round_id, c.name, c.is_main, c.format_version, c.config, c.sort_order
          from public.round_competitions c where c.round_id = any (v_rounds)
         order by c.round_id, c.sort_order, c.created_at, c.id) x),
    'players', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select p.round_id, p.member_id, p.club_id, p.handicap_index, p.seed_group, p.playing_handicap,
               p.bay_no, p.is_marker, p.team_no, p.side
          from public.round_players p where p.round_id = any (v_rounds)) x),
    'matches', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select m.round_id, m.match_no, m.player_a, m.player_b, m.player_c, m.team_a, m.team_b, m.result
          from public.round_matches m where m.round_id = any (v_rounds)) x),
    'claims', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select c.id, c.round_id, c.member_id, c.kind, c.meters, c.hole_index, c.created_at
          from public.side_claims c where c.round_id = any (v_rounds)) x),
    'adjustments', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select a.id, a.club_id, a.season_id, a.member_id, a.event_id, a.points, a.reason, a.created_at
          from public.point_adjustments a where a.season_id = p_season_id
         order by a.created_at, a.id) x),
    'courses', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select c.id, c.club_id, c.name, c.external_name, c.course_rating, c.slope_rating, c.in_use,
               c.confirmed_by, c.confirmed_at
          from public.courses c where c.id = any (v_courses)) x),
    'course_holes', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select h.course_id, h.hole_number, h.par, h.stroke_index, h.length_m
          from public.course_holes h where h.course_id = any (v_courses)) x),
    'scores', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select s.round_id, s.member_id, s.hole_index, s.strokes, s.recorded_at, s.updated_by, s.updated_at
          from public.hole_scores s where s.round_id = any (v_rounds)) x)
  );
end;
$$;
revoke all on function public.tavla_data(uuid) from public, anon;
grant execute on function public.tavla_data(uuid) to authenticated;

create or replace function public.tv_board_data(p_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_comp    public.competitions%rowtype;
  v_events  uuid[];
  v_rounds  uuid[];
  v_courses uuid[];
begin
  select c.* into v_comp
    from public.tv_codes t join public.competitions c on c.id = t.competition_id
   where t.code = upper(btrim(coalesce(p_code, ''))) and t.revoked_at is null and t.expires_at > now();
  if v_comp.id is null then
    raise exception 'Fant ingen TV-visning for koden' using errcode = 'P0002';
  end if;
  if v_comp.season_id is null then
    return public.tv_competition_data(v_comp.id);
  end if;

  select coalesce(array_agg(e.id), '{}') into v_events
    from public.events e where e.season_id = v_comp.season_id;
  select coalesce(array_agg(r.id), '{}') into v_rounds
    from public.rounds r where r.event_id = any (v_events) and r.status in ('active', 'locked');
  select coalesce(array_agg(distinct r.course_id), '{}') into v_courses
    from public.rounds r where r.id = any (v_rounds) and r.course_id is not null;

  return jsonb_build_object(
    'competition', jsonb_build_object('id', v_comp.id, 'name', v_comp.name, 'kind', v_comp.kind,
                                      'status', v_comp.status, 'season_id', v_comp.season_id,
                                      'club_id', v_comp.club_id, 'rules', v_comp.rules,
                                      'club_name', (select k.name from public.clubs k where k.id = v_comp.club_id)),
    'events', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select e.id, e.club_id, e.season_id, e.event_date, e.start_time, e.venue
          from public.events e where e.id = any (v_events)) x),
    'members', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select m.id, m.club_id, null::uuid as user_id, m.display_name, m.handicap_index, m.seed_group,
               m.is_organizer, m.is_treasurer, m.status, null::text as avatar_path
          from public.club_members m where m.club_id = v_comp.club_id) x),
    'rounds', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select r.id, r.club_id, r.event_id, r.course_id, r.round_no, r.name, r.status, r.hole_count,
               r.first_hole, r.tee_time, r.format, r.handicap_allowance, r.external_handicap, r.weight,
               r.ld_enabled, r.ld_hole_index, r.kp_enabled, r.kp_hole_index, r.cut_rule, r.cut_after,
               null::uuid as par_confirmed_by, r.par_confirmed_at, r.started_at, r.locked_at, r.venue,
               r.tee_id, r.tee_name, r.course_rating, r.slope_rating, r.tee_par,
               r.counts, r.points_table, r.hide_last_holes, r.kind, r.playoff_for, r.playoff_holes,
               r.rules_snapshot, r.holes_snapshot, r.snapshot_at, r.snapshot_source
          from public.rounds r where r.id = any (v_rounds)) x),
    'round_holes', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select h.round_id, h.hole_index, h.par, h.stroke_index, h.length_m
          from public.round_holes h where h.round_id = any (v_rounds)) x),
    'round_competitions', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select c.id, c.round_id, c.name, c.is_main, c.format_version, c.config, c.sort_order
          from public.round_competitions c where c.round_id = any (v_rounds)
         order by c.round_id, c.sort_order, c.created_at, c.id) x),
    'players', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select p.round_id, p.member_id, p.club_id, p.handicap_index, p.seed_group, p.playing_handicap,
               p.bay_no, p.is_marker, p.team_no, p.side
          from public.round_players p where p.round_id = any (v_rounds)) x),
    'matches', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select m.round_id, m.match_no, m.player_a, m.player_b, m.player_c, m.team_a, m.team_b, m.result
          from public.round_matches m where m.round_id = any (v_rounds)) x),
    'claims', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select c.id, c.round_id, c.member_id, c.kind, c.meters, c.hole_index, c.created_at
          from public.side_claims c where c.round_id = any (v_rounds)) x),
    'adjustments', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select a.id, a.club_id, a.season_id, a.member_id, a.event_id, a.points, a.reason, a.created_at
          from public.point_adjustments a where a.season_id = v_comp.season_id
         order by a.created_at, a.id) x),
    'courses', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select c.id, c.club_id, c.name, c.external_name, c.course_rating, c.slope_rating, c.in_use,
               null::uuid as confirmed_by, null::timestamptz as confirmed_at
          from public.courses c where c.id = any (v_courses)) x),
    'course_holes', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select h.course_id, h.hole_number, h.par, h.stroke_index, h.length_m
          from public.course_holes h where h.course_id = any (v_courses)) x),
    'scores', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select s.round_id, s.member_id, s.hole_index, s.strokes
          from public.hole_scores s join public.rounds r on r.id = s.round_id
         where s.round_id = any (v_rounds)
           and (r.status = 'locked' or r.hide_last_holes = 0
                or s.hole_index < r.hole_count - least(r.hide_last_holes, r.hole_count))) x)
  );
end;
$$;
revoke all on function public.tv_board_data(text) from public;
grant execute on function public.tv_board_data(text) to anon, authenticated;

-- ===========================================================================
-- 4. KONTROLL
-- ===========================================================================
do $$
declare
  v_ok int := 0;
begin
  if to_regclass('public.point_adjustments') is not null
     and (select c.relrowsecurity from pg_class c where c.oid = 'public.point_adjustments'::regclass) then
    v_ok := v_ok + 1;
  end if;
  if (select count(*) from pg_policies
       where schemaname = 'public' and tablename = 'point_adjustments') = 4 then
    v_ok := v_ok + 1;
  end if;
  if not has_table_privilege('anon', 'public.point_adjustments', 'select') then
    v_ok := v_ok + 1;
  end if;
  if pg_get_functiondef('public.tavla_data(uuid)'::regprocedure) like '%''adjustments''%'
     and pg_get_functiondef('public.tv_board_data(text)'::regprocedure) like '%''adjustments''%' then
    v_ok := v_ok + 1;
  end if;
  if has_function_privilege('anon', 'public.tv_board_data(text)', 'execute')
     and not has_function_privilege('anon', 'public.tavla_data(uuid)', 'execute') then
    v_ok := v_ok + 1;
  end if;
  if v_ok <> 5 then
    raise exception '072: kontroll % av 5', v_ok;
  end if;
  raise notice '072 kontroll: 5 av 5';
end $$;

commit;

-- RULLEBAKKE
-- begin;
-- -- tavla_data og tv_board_data: kjør dem fra 048 på nytt (uten 'adjustments').
-- drop table if exists public.point_adjustments;
-- drop function if exists private.point_adjustments_before_write();
-- commit;
