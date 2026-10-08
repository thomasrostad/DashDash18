\set ON_ERROR_STOP on
\pset footer off
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Lasttest for fase 22 (docs/fase-22-turnering-som-kjerne.md, kap. 9).
--
-- Fyller en EGEN, tom, lokal database med syntetiske data i målbildets
-- størrelse og måler de tyngste spørringene appen gjør i dag (Tavla, Hjem,
-- turneringslista, «folk du kjenner», løse runder, pågående runde) med
-- EXPLAIN ANALYZE, både som innlogget bruker (RLS på, slik PostgREST kjører
-- dem) og som postgres (uten RLS), så vi ser hva RLS koster.
--
-- Rekkefølge i en tom, lokal Postgres (egen database, f.eks. «last»):
--   lokal/stub.sql, lokal/stub_storage.sql, 001–030 (som i sql/README.md),
--   031, så denne fila. Tar 1–3 minutter.
--
-- Størrelse (endres i avsnitt 0):
--   1 000 brukere, 50 klubber/arenaer (30 simulatorsentre, 15 golfklubber,
--   5 gjenger), ~1 500 medlemskap, 200 turneringer (4 per klubb: sesong,
--   liga, morro, cup), 5 000 spilledager, 20 000 klubbrunder + 2 000 løse
--   runder, 8 spillere per klubbrunde, ~3,2 mill. hullscorer, ~145 000
--   aktivitetslinjer, 50 000 trådmeldinger.
--
-- Hvorfor her (sql/lokal) og ikke tools/: det er ren SQL som kjøres med psql
-- mot samme lokale oppsett som rolleprøvene (stub.sql, 001–031), uten nye
-- avhengigheter. Den hører til skjemaet den måler, og må endres når skjemaet
-- endres. «KUN LOKALT» gjelder hele mappa.
--
-- auth.uid() byttes til Supabase sin utgave (leser request.jwt.claims som
-- json, slik PostgREST setter den), så kostnaden per kall er realistisk.
-- Bulkinnlastingen går med session_replication_role = replica (triggere av),
-- derfor lages profiler, sesongturneringer og koblinger eksplisitt.
-- ===========================================================================

-- === 0. Oppsett ================================================================
create or replace function auth.uid() returns uuid language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
                  (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid
$$;

drop schema if exists lasttest cascade;
create schema lasttest;
grant usage on schema lasttest to authenticated;

set session_replication_role = replica;

-- === 1. Brukere, klubber, medlemskap ============================================
insert into auth.users select md5('u' || i)::uuid from generate_series(1, 1000) i;
insert into public.profiles (id, display_name, handicap_index)
select md5('u' || i)::uuid, 'Spiller ' || i, (i % 36)::numeric from generate_series(1, 1000) i;

insert into public.clubs (id, name, kind)
select md5('k' || c)::uuid, 'Arena ' || c,
       case when c < 30 then 'simulator_center' when c < 45 then 'golf_club' else 'group' end
from generate_series(0, 49) c;

-- Hver bruker i 1–3 klubber.
create table lasttest.medlem as
select distinct i, c from (
  select i, i % 50 as c from generate_series(1, 1000) i
  union all select i, (i * 7) % 50 from generate_series(1, 1000) i where i % 3 = 0
  union all select i, (i * 13) % 50 from generate_series(1, 1000) i where i % 5 = 0
) x;
create table lasttest.m as
select c, i, md5('m' || i || '-' || c)::uuid as id,
       (row_number() over (partition by c order by i) - 1)::int as nr,
       (count(*) over (partition by c))::int as n
from lasttest.medlem;
insert into public.club_members (id, club_id, user_id, display_name, handicap_index, seed_group, is_organizer, status)
select id, md5('k' || c)::uuid, md5('u' || i)::uuid, 'Spiller ' || i, (i % 36)::numeric, 1 + i % 4, nr < 2, 'active'
from lasttest.m;

-- === 2. Baner ===================================================================
insert into public.courses (id, club_id, name, kind)
select md5('b' || c || '-' || b)::uuid, md5('k' || c)::uuid, 'Bane ' || b, 'simulator'
from generate_series(0, 49) c, generate_series(0, 2) b;
insert into public.courses (id, club_id, name, kind)
select md5('lib' || b)::uuid, null, 'Felles bane ' || b, 'course' from generate_series(0, 19) b;
insert into public.course_holes (course_id, hole_number, par, stroke_index)
select c.id, h, case when h % 6 = 0 then 5 when h % 4 = 0 then 3 else 4 end, h
from public.courses c, generate_series(1, 18) h;

-- === 3. Turneringer, sesonger, påmeldte =========================================
insert into public.seasons (id, club_id, name, status, rules, created_at)
select md5('s' || c)::uuid, md5('k' || c)::uuid, 'Sesong 2026', 'active', '{"version": 1}', now() - interval '300 days'
from generate_series(0, 49) c;
insert into public.competitions (id, kind, name, club_id, season_id, status, entry, rules, is_main, created_at)
select md5('t' || c || '-' || s)::uuid,
       case s when 0 then 'season' when 1 then 'league' when 2 then 'fun' else 'cup' end,
       'Turnering ' || c || '-' || s, md5('k' || c)::uuid,
       case when s = 0 then md5('s' || c)::uuid end,
       'active', case when s = 0 then 'club' else 'listed' end, '{"version": 1}', s = 0,
       now() - interval '300 days' + s * interval '1 day'
from generate_series(0, 49) c, generate_series(0, 3) s;
insert into public.competition_participants (competition_id, member_id)
select md5('t' || m.c || '-' || s)::uuid, m.id
from lasttest.m m, generate_series(1, 3) s
where m.nr < 20;

-- === 4. Spilledager og runder ===================================================
-- 25 spilledager per turnering, 4 runder (puljer) per spilledag.
insert into public.events (id, club_id, season_id, competition_id, event_date)
select md5('e' || c || '-' || s || '-' || k)::uuid, md5('k' || c)::uuid,
       case when s = 0 then md5('s' || c)::uuid end, md5('t' || c || '-' || s)::uuid,
       current_date - 280 + k * 11 + s
from generate_series(0, 49) c, generate_series(0, 3) s, generate_series(0, 24) k;

create table lasttest.r as
select c, s, k, w, md5('r' || c || '-' || s || '-' || k || '-' || w)::uuid as id,
       md5('e' || c || '-' || s || '-' || k)::uuid as event_id,
       (current_date - 280 + k * 11 + s)::timestamptz + interval '17 hours' + w * interval '40 minutes' as started_at
from generate_series(0, 49) c, generate_series(0, 3) s, generate_series(0, 24) k, generate_series(1, 4) w;
insert into public.rounds (id, club_id, event_id, course_id, round_no, wave_no, status, hole_count,
                           started_at, locked_at, created_at)
select id, md5('k' || c)::uuid, event_id, md5('b' || c || '-' || (w % 3))::uuid, w, w,
       case when s = 0 and k = 24 and w = 1 then 'active' else 'locked' end, 18,
       started_at, case when s = 0 and k = 24 and w = 1 then null else started_at + interval '3 hours' end,
       started_at - interval '1 day'
from lasttest.r;

-- 8 spillere per runde, to båser med markør.
create table lasttest.rp as
select r.id as round_id, r.c, m.id as member_id, j
from lasttest.r r
cross join generate_series(0, 7) j
join lasttest.m m on m.c = r.c and m.nr = ((r.k * 5 + r.w * 3 + r.s * 7 + j) % m.n);
insert into public.round_players (round_id, member_id, club_id, bay_no, is_marker)
select round_id, member_id, md5('k' || c)::uuid, 1 + j / 4, j % 4 = 0 from lasttest.rp;
insert into public.round_matches (round_id, match_no, player_a, player_b)
select a.round_id, a.j / 2 + 1, a.member_id, b.member_id
from lasttest.rp a join lasttest.rp b on b.round_id = a.round_id and b.j = a.j + 1
where a.j % 2 = 0;
insert into public.side_claims (round_id, member_id, kind, meters, hole_index)
select round_id, member_id, case j when 0 then 'drive' else 'kp' end, 100 + j * 50, j + 2
from lasttest.rp where j < 2;
insert into public.hole_scores (round_id, member_id, hole_index, strokes, recorded_at, updated_at)
select rp.round_id, rp.member_id, h, 3 + (abs(hashtext(rp.member_id::text || h)) % 4), now(), now()
from lasttest.rp rp, generate_series(0, 17) h;

insert into public.competition_rounds (competition_id, round_id, source)
select md5('t' || c || '-' || s)::uuid, id, case when s = 0 then 'season' else 'manual' end from lasttest.r;

-- === 5. Løse runder (2 000), 4 deltakere hver =====================================
create table lasttest.l as
select x, md5('lr' || x)::uuid as id, 1 + (x % 1000) as eier,
       now() - (x % 280) * interval '1 day' as started_at
from generate_series(0, 1999) x;
insert into public.rounds (id, club_id, event_id, owner_id, course_id, round_no, status, hole_count,
                           started_at, locked_at, created_at)
select id, null, null, md5('u' || eier)::uuid, md5('lib' || (x % 20))::uuid, 1, 'locked', 18,
       started_at, started_at + interval '4 hours', started_at
from lasttest.l;
insert into public.round_participants (id, round_id, profile_id, display_name)
select md5('p' || l.x || '-' || j)::uuid, l.id, md5('u' || (1 + (l.eier - 1 + j * 17) % 1000))::uuid, 'Spiller'
from lasttest.l l, generate_series(0, 3) j;
insert into public.round_players (round_id, member_id, club_id)
select round_id, id, null from public.round_participants;
insert into public.hole_scores (round_id, member_id, hole_index, strokes, recorded_at, updated_at)
select p.round_id, p.id, h, 3 + (abs(hashtext(p.id::text || h)) % 4), now(), now()
from public.round_participants p, generate_series(0, 17) h;

-- === 6. Aktivitet, tråd, reaksjoner =============================================
insert into public.activity (club_id, kind, category, data, actor_member_id, round_id, competition_id, created_at)
select md5('k' || r.c)::uuid, v.kind, v.category, v.data, null, r.id, md5('t' || r.c || '-' || r.s)::uuid,
       r.started_at + v.etter
from lasttest.r r
cross join (values ('round_started', 'round', '{}'::jsonb, interval '0'),
                   ('lead_changed', 'lead', '{"after_hole": 6}'::jsonb, interval '1 hour'),
                   ('lead_changed', 'lead', '{"after_hole": 12}'::jsonb, interval '2 hours'),
                   ('round_locked', 'round', '{}'::jsonb, interval '3 hours')) v(kind, category, data, etter);
insert into public.activity (club_id, kind, category, data, round_id, competition_id, created_at)
select md5('k' || rp.c)::uuid, 'big_score', 'score',
       jsonb_build_object('member', rp.member_id, 'hole_index', 4), rp.round_id, null, now() - interval '5 days'
from lasttest.rp rp where rp.j = 3 and abs(hashtext(rp.round_id::text)) % 4 = 0;
insert into public.activity (club_id, kind, category, data, round_id, competition_id, created_at)
select md5('k' || r.c)::uuid, 'table_changed', 'round', jsonb_build_object('competition', md5('t' || r.c || '-' || r.s)::uuid),
       r.id, md5('t' || r.c || '-' || r.s)::uuid, r.started_at + interval '3 hours'
from lasttest.r r;
insert into public.activity (club_id, kind, category, data, event_id, competition_id, actor_member_id, created_at)
select md5('k' || m.c)::uuid, 'signup', 'signup', '{"status": "yes"}', md5('e' || m.c || '-0-' || k)::uuid,
       md5('t' || m.c || '-0')::uuid, m.id, (current_date - 283 + k * 11)::timestamptz
from lasttest.m m, generate_series(0, 24) k where m.nr < 5;

insert into public.thread_messages (club_id, event_id, member_id, body, mentions, created_at)
select md5('k' || m.c)::uuid, md5('e' || m.c || '-' || (k % 4) || '-' || (k / 4))::uuid, m.id, 'Melding ' || k,
       case when k % 5 = 0 then array[(select m2.id from lasttest.m m2 where m2.c = m.c and m2.nr = (m.nr + 1) % m.n)] else '{}' end,
       (current_date - 280 + (k / 4) * 11 + (k % 4))::timestamptz + interval '20 hours'
from lasttest.m m, generate_series(0, 99) k where m.nr < 10;

insert into public.activity_reactions (activity_id, member_id, club_id, emoji)
select a.id, m.id, a.club_id, '🔥'
from public.activity a
join lasttest.m m on md5('k' || m.c)::uuid = a.club_id and m.nr = abs(hashtext(a.id::text)) % m.n
where abs(hashtext(a.id::text)) % 5 = 0;

set session_replication_role = origin;
analyze;

select 'Data: ' || (select count(*) from auth.users) || ' brukere, '
       || (select count(*) from public.clubs) || ' klubber, '
       || (select count(*) from public.club_members) || ' medlemskap, '
       || (select count(*) from public.competitions) || ' turneringer, '
       || (select count(*) from public.events) || ' spilledager, '
       || (select count(*) from public.rounds) || ' runder, '
       || (select count(*) from public.round_players) || ' spillere i runder, '
       || (select count(*) from public.hole_scores) || ' hullscorer, '
       || (select count(*) from public.activity) || ' aktivitetslinjer, '
       || (select count(*) from public.thread_messages) || ' trådmeldinger' as data;

-- === 7. Måleverktøy ==============================================================
-- Kjører spørringen p_ganger ganger med EXPLAIN (ANALYZE) og gir median tid
-- (planlegging + kjøring), antall rader og en kort plan. Kjøres som den rollen
-- som kaller (authenticated = RLS på).
create function lasttest.plan_kort(p jsonb) returns text language sql immutable as $$
  select left(string_agg(n ->> 'Node Type'
                         || coalesce(' ' || coalesce(n ->> 'Index Name', n ->> 'Relation Name'), ''), ' > '), 160)
  from jsonb_path_query(p, 'strict $.** ? (exists(@."Node Type"))') n
$$;
create function lasttest.maal(p_navn text, p_sql text, p_ganger int default 7)
returns table (sporring text, median_ms numeric, rader bigint, plan text)
language plpgsql as $$
declare
  j jsonb;
  t numeric[] := '{}';
begin
  for g in 1 .. p_ganger loop
    execute 'explain (analyze, format json) ' || p_sql into j;
    t := t || ((j -> 0 ->> 'Execution Time')::numeric + (j -> 0 ->> 'Planning Time')::numeric);
  end loop;
  return query
    select p_navn,
           (select percentile_cont(0.5) within group (order by x) from unnest(t) x)::numeric(10, 2),
           (j -> 0 -> 'Plan' ->> 'Actual Rows')::bigint,
           lasttest.plan_kort(j -> 0 -> 'Plan');
end $$;
grant execute on all functions in schema lasttest to authenticated;

create function lasttest.som(p_uid uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, false);
$$;
grant execute on function lasttest.som(uuid) to authenticated;

-- Spørringene, med verdiene appen ville sendt (lister som = any(array), slik PostgREST gjør).
create table lasttest.q (nr int primary key, navn text, sql text);

-- En vanlig spiller (ikke arrangør) i minst to klubber.
select m.user_id as bruker, m.club_id as klubb, m.id as medlem
from public.club_members m
where m.club_id = md5('k3')::uuid and not m.is_organizer
  and m.user_id in (select user_id from public.club_members group by user_id having count(*) >= 2)
order by m.display_name limit 1 \gset
select (select array_agg(club_id)::text from public.club_members where user_id = :'bruker') as klubber,
       (select array_agg(id)::text from public.club_members where user_id = :'bruker') as medlemmer,
       (select id from public.seasons where club_id = :'klubb') as sesong,
       (select id from public.competitions where season_id = (select id from public.seasons where club_id = :'klubb')) as jakke \gset
select (select array_agg(id)::text from public.events where season_id = :'sesong') as kvelder \gset
select (select array_agg(id)::text from public.rounds where event_id = any(:'kvelder'::uuid[]) and status in ('active', 'locked')) as tavlarunder,
       (select id from public.rounds where event_id = any(:'kvelder'::uuid[]) and status = 'locked' limit 1) as enrunde \gset
select (select array_agg(id)::text from (select id from public.activity where club_id = any(:'klubber'::uuid[])
          and created_at >= now() - interval '30 days' order by created_at desc limit 150) a) as aktivitet,
       (select array_agg(id)::text from (select id from public.rounds where club_id = any(:'klubber'::uuid[])
          and status = 'locked' and locked_at >= now() - interval '30 days' order by locked_at desc limit 40) r) as hjemrunder \gset
-- Turneringene spilleren ser (appen sender bare dem videre).
select lasttest.som(:'bruker');
set role authenticated;
select (select array_agg(id)::text from public.competitions where kind <> 'game') as turneringer \gset
reset role;
select set_config('request.jwt.claims', '', false);

insert into lasttest.q values
 (1,  'Tavla 1: sesongene i klubben',
      format($q$select id, club_id, name, status, rules, created_at from public.seasons where club_id = %L and status = any('{active,finished}') order by created_at desc$q$, :'klubb')),
 (2,  'Tavla 2: kveldene i sesongen',
      format($q$select id, club_id, season_id, event_date, start_time from public.events where season_id = %L$q$, :'sesong')),
 (3,  'Tavla 3: troppen',
      format($q$select id, club_id, user_id, display_name, handicap_index, seed_group, is_organizer, status from public.club_members where club_id = %L$q$, :'klubb')),
 (4,  'Tavla 4: rundene i kveldene (100)',
      format($q$select * from public.rounds where event_id = any(%L::uuid[]) and status = any('{active,locked}')$q$, :'kvelder')),
 (5,  'Tavla 5: spillerne i rundene',
      format($q$select * from public.round_players where round_id = any(%L::uuid[])$q$, :'tavlarunder')),
 (6,  'Tavla 6: matchene',
      format($q$select * from public.round_matches where round_id = any(%L::uuid[])$q$, :'tavlarunder')),
 (7,  'Tavla 7: sidepremiene',
      format($q$select * from public.side_claims where round_id = any(%L::uuid[])$q$, :'tavlarunder')),
 (8,  'Tavla 8: hullscorer for ÉN runde (appen gjør 100 slike parallelt)',
      format($q$select round_id, member_id, hole_index, strokes, recorded_at, updated_at from public.hole_scores where round_id = %L$q$, :'enrunde')),
 (9,  'Tavla 9: hullscorer for alle 100 rundene i én spørring',
      format($q$select round_id, member_id, hole_index, strokes from public.hole_scores where round_id = any(%L::uuid[])$q$, :'tavlarunder')),
 (10, 'Tavla via turneringen: koblingene (competition_rounds)',
      format($q$select competition_id, round_id, source from public.competition_rounds where competition_id = %L$q$, :'jakke')),
 (11, 'Hjem 1: aktiviteten siste 30 dager (limit 150)',
      format($q$select * from public.activity where club_id = any(%L::uuid[]) and created_at >= now() - interval '30 days' order by created_at desc limit 150$q$, :'klubber')),
 (12, 'Hjem 2: troppene i klubbene',
      format($q$select * from public.club_members where club_id = any(%L::uuid[])$q$, :'klubber')),
 (13, 'Hjem 3: reaksjonene på 150 linjer',
      format($q$select * from public.activity_reactions where activity_id = any(%L::uuid[])$q$, :'aktivitet')),
 (14, 'Hjem 4: låste klubbrunder siste 30 dager (limit 40)',
      format($q$select * from public.rounds where club_id = any(%L::uuid[]) and status = 'locked' and locked_at >= now() - interval '30 days' order by locked_at desc limit 40$q$, :'klubber')),
 (15, 'Hjem 5: hvilke av dem du spilte',
      format($q$select round_id from public.round_players where round_id = any(%L::uuid[]) and member_id = any(%L::uuid[])$q$, :'hjemrunder', :'medlemmer')),
 (16, 'Hjem 6: koblingene for rundene',
      format($q$select competition_id, round_id, source from public.competition_rounds where round_id = any(%L::uuid[])$q$, :'hjemrunder')),
 (17, 'Hjem 7: trådmeldinger der du er nevnt',
      format($q$select * from public.thread_messages where club_id = any(%L::uuid[]) and created_at > now() - interval '30 days' and mentions && %L::uuid[] order by created_at desc limit 50$q$, :'klubber', :'medlemmer')),
 (18, 'Turneringer: alle du kan se (RLS filtrerer)',
      $q$select * from public.competitions where kind <> 'game' order by created_at desc$q$),
 (19, 'Turneringer: påmeldte i dem',
      format($q$select * from public.competition_participants where competition_id = any(%L::uuid[])$q$, :'turneringer')),
 (20, 'Folk du kjenner: profiles uten filter (RLS filtrerer)',
      format($q$select * from public.profiles where id <> %L$q$, :'bruker')),
 (21, 'Løse runder: dine (RLS filtrerer)',
      $q$select * from public.rounds where club_id is null and status <> 'draft' order by started_at desc limit 50$q$),
 (22, 'Kveld: pågående runde i klubben',
      format($q$select * from public.rounds where club_id = %L and status = 'active' limit 1$q$, :'klubb'));

create table lasttest.resultat (nr int, rolle text, sporring text, median_ms numeric, rader bigint, plan text);
grant insert, select on lasttest.resultat to authenticated;
grant select on lasttest.q to authenticated;

-- === 8. Målingene ================================================================
-- Som innlogget spiller (RLS på).
select lasttest.som(:'bruker');
set role authenticated;
insert into lasttest.resultat
select q.nr, 'spiller (RLS)', m.* from lasttest.q q, lateral lasttest.maal(q.navn, q.sql) m order by q.nr;
reset role;
-- Som postgres (uten RLS): det spørringen koster uten tilgangskontrollen.
select set_config('request.jwt.claims', '', false);
insert into lasttest.resultat
select q.nr, 'postgres (uten RLS)', m.* from lasttest.q q, lateral lasttest.maal(q.navn, q.sql) m order by q.nr;

\pset format aligned
select r.nr, r.sporring, r.rader, r.median_ms as rls_ms, p.median_ms as uten_rls_ms, r.plan
from lasttest.resultat r join lasttest.resultat p on p.nr = r.nr and p.rolle like 'postgres%'
where r.rolle like 'spiller%'
order by r.nr;


-- === 9. Forslag til fase 24, målt på samme data ===================================
-- Prototyper (bare i skjemaet lasttest, ikke i public). De viser hva en
-- mengdebasert spørring eller én RPC med tilgangssjekk én gang sparer i
-- forhold til RLS per rad. Ikke ferdige: blokkering og alle grener av
-- can_see_profile er ikke med i lasttest.kontakter().

-- Tavla-data i ett kall: tilgangen sjekkes én gang, så hentes rådata for
-- turneringens startede runder uten RLS per rad. Tabellen regnes fortsatt på
-- telefonen (pariteten står).
create function lasttest.tavla_data(p_competition_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_ids uuid[];
begin
  if not public.can_read_competition(p_competition_id) then
    raise exception 'Fant ikke turneringen' using errcode = 'P0002';
  end if;
  select coalesce(array_agg(r.id), '{}') into v_ids
    from public.competition_rounds cr join public.rounds r on r.id = cr.round_id
   where cr.competition_id = p_competition_id and r.status in ('active', 'locked');
  return jsonb_build_object(
    'rounds',  (select jsonb_agg(to_jsonb(r)) from public.rounds r where r.id = any (v_ids)),
    'players', (select jsonb_agg(to_jsonb(p)) from public.round_players p where p.round_id = any (v_ids)),
    'matches', (select jsonb_agg(to_jsonb(m)) from public.round_matches m where m.round_id = any (v_ids)),
    'claims',  (select jsonb_agg(to_jsonb(c)) from public.side_claims c where c.round_id = any (v_ids)),
    'scores',  (select jsonb_agg(jsonb_build_array(h.round_id, h.member_id, h.hole_index, h.strokes))
                from public.hole_scores h where h.round_id = any (v_ids)));
end $$;

-- «Folk du kjenner» som en mengde i stedet for can_see_profile per profil.
create function lasttest.kontakter() returns setof public.profiles
language sql stable security definer set search_path = '' as $$
  select p.* from public.profiles p
  where p.id <> auth.uid()
    and p.id in (
      select b.user_id from public.club_members a join public.club_members b on b.club_id = a.club_id
       where a.user_id = auth.uid() and a.status = 'active' and b.user_id is not null
      union
      select b.profile_id from public.round_participants a join public.round_participants b on b.round_id = a.round_id
       where a.profile_id = auth.uid() and b.profile_id is not null
      union
      select b.profile_id from public.competition_participants a
        join public.competition_participants b on b.competition_id = a.competition_id
       where a.profile_id = auth.uid() and b.profile_id is not null and a.status = 'active' and b.status = 'active')
$$;
-- Dine løse runder som en mengde (eier eller deltaker), uten RLS per rad.
create function lasttest.mine_lose_runder(p_limit int) returns setof public.rounds
language sql stable security definer set search_path = '' as $$
  select r.* from public.rounds r
  where r.club_id is null and r.status <> 'draft'
    and (r.owner_id = auth.uid()
         or r.id in (select p.round_id from public.round_participants p where p.profile_id = auth.uid()))
  order by r.started_at desc limit p_limit
$$;
grant execute on function lasttest.tavla_data(uuid) to authenticated;
grant execute on function lasttest.kontakter() to authenticated;
grant execute on function lasttest.mine_lose_runder(int) to authenticated;

insert into lasttest.q values
 (23, 'Forslag: Tavla-data i én RPC (alt over i ett kall)',
      format($q$select lasttest.tavla_data(%L)$q$, :'jakke')),
 (24, 'Forslag: turneringer med filter (dine klubber, eier, påmeldt)',
      format($q$select * from public.competitions where kind <> 'game' and (club_id = any(%L::uuid[]) or owner_id = %L
               or id in (select competition_id from public.competition_participants where profile_id = %L or member_id = any(%L::uuid[])))
               order by created_at desc$q$, :'klubber', :'bruker', :'bruker', :'medlemmer')),
 (25, 'Forslag: folk du kjenner som én mengde (RPC)',
      $q$select * from lasttest.kontakter()$q$),
 (26, 'Forslag: løse runder med filter (eier eller deltaker)',
      format($q$select * from public.rounds where club_id is null and status <> 'draft'
               and (owner_id = %L or id in (select round_id from public.round_participants where profile_id = %L))
               order by started_at desc limit 50$q$, :'bruker', :'bruker')),
 (27, 'Forslag: løse runder som én mengde (RPC)',
      $q$select * from lasttest.mine_lose_runder(50)$q$);

select lasttest.som(:'bruker');
set role authenticated;
insert into lasttest.resultat
select q.nr, 'spiller (RLS)', m.* from lasttest.q q, lateral lasttest.maal(q.navn, q.sql) m where q.nr >= 23 order by q.nr;
reset role;
select set_config('request.jwt.claims', '', false);

\echo
\echo Forslagene (som spilleren, RLS på):
select r.nr, r.sporring, r.rader, r.median_ms as rls_ms, r.plan
from lasttest.resultat r where r.nr >= 23 order by r.nr;

-- === 10. Policyvariant og indeksene fra 031 (rulles tilbake) ======================
-- hole_scores og round_players leser via rounds (EXISTS) i stedet for
-- can_read_round per rad. Raskere per runde, men se Tavla 9: med 100 runder i
-- én spørring velger planleggeren en dårlig plan. Derfor RPC-en over.
begin;
drop policy hole_scores_select on public.hole_scores;
create policy hole_scores_select on public.hole_scores for select to authenticated
  using (exists (select 1 from public.rounds r where r.id = hole_scores.round_id));
drop policy round_players_select on public.round_players;
create policy round_players_select on public.round_players for select to authenticated
  using (exists (select 1 from public.rounds r where r.id = round_players.round_id));
select lasttest.som(:'bruker');
set role authenticated;
\echo
\echo Policyvariant (EXISTS mot rounds), som spilleren:
select q.nr, m.sporring, m.rader, m.median_ms as rls_ms, m.plan
from lasttest.q q, lateral lasttest.maal(q.navn, q.sql, 5) m where q.nr in (5, 8, 9) order by q.nr;
reset role;
rollback;

-- is_competition_participant uten owns_member per påmeldt (medlemskapene
-- mine slås opp én gang i stedet).
begin;
create or replace function public.is_competition_participant(p_competition_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.competition_participants p
    where p.competition_id = p_competition_id and p.status = 'active'
      and (p.profile_id = auth.uid()
           or p.member_id = any (array(select m.id from public.club_members m
                                       where m.user_id = auth.uid() and m.status = 'active')))
  );
$$;
select lasttest.som(:'bruker');
set role authenticated;
\echo
\echo is_competition_participant som mengde, som spilleren:
select q.nr, m.sporring, m.rader, m.median_ms as rls_ms, m.plan
from lasttest.q q, lateral lasttest.maal(q.navn, q.sql) m where q.nr in (18, 19) order by q.nr;
reset role;
rollback;

begin;
drop index public.rounds_club_locked_idx;
drop index public.competition_participants_competition_idx;
select lasttest.som(:'bruker');
set role authenticated;
\echo
\echo Uten indeksene fra 031 (rounds_club_locked_idx, competition_participants_competition_idx), som spilleren:
select q.nr, m.sporring, m.rader, m.median_ms as rls_ms, m.plan
from lasttest.q q, lateral lasttest.maal(q.navn, q.sql) m where q.nr in (14, 18, 19) order by q.nr;
reset role;
rollback;
select set_config('request.jwt.claims', '', false);
