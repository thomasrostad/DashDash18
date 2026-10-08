\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Første halvdel av rolleprøven for 031: «verden før». Kjøres i en tom,
-- lokal Postgres etter lokal/stub.sql, lokal/stub_storage.sql og 001–030
-- (rekkefølgen i sql/README.md), men FØR 031.
--
-- Lager en Golfgutu-klubb med to sesonger, kvelder (også en uten sesong),
-- runder (låst, pågår, kladd), scorer, match, sidepremie, aktivitet og en
-- morroturnering, pluss en annen klubb. Så tar den et bilde av hva hver
-- innlogging ser og kan (lokal31.bilde) og et fingeravtrykk av Tavla per
-- sesong (lokal31.tavla), lagret i lokal31.for_bilde. lokal/031_prove.sql
-- sammenligner med det etter 031.
-- ===========================================================================

create schema if not exists lokal31;
grant usage on schema lokal31 to authenticated;

create table lokal31.par (round_id uuid, member_id uuid);
create table lokal31.for_bilde (uid uuid primary key, bilde jsonb, tavla jsonb);
grant select on lokal31.par to authenticated;

-- Hva den innloggede ser og kan, som jsonb. Kjøres med role authenticated.
-- Kolonnelistene er dem dagens app henter (CompetitionRow.columnsWithSignup,
-- CompetitionParticipantRow, CompetitionRoundRow), så en endring der synes.
create function lokal31.bilde() returns jsonb language sql stable as $$
  select jsonb_build_object(
    'clubs',          (select coalesce(jsonb_agg(id order by id), '[]') from public.clubs),
    'club_members',   (select coalesce(jsonb_agg(id order by id), '[]') from public.club_members),
    'seasons',        (select coalesce(jsonb_agg(to_jsonb(s) - 'updated_at' order by id), '[]')
                       from (select id, club_id, name, status, rules from public.seasons) s),
    'events',         (select coalesce(jsonb_agg(jsonb_build_array(id, season_id, event_date, updated_at) order by id), '[]')
                       from public.events),
    'rounds',         (select coalesce(jsonb_agg(jsonb_build_array(id, status, event_id) order by id), '[]') from public.rounds),
    'round_players',  (select count(*) from public.round_players),
    'hole_scores',    (select count(*) from public.hole_scores),
    'side_claims',    (select count(*) from public.side_claims),
    'activity',       (select coalesce(jsonb_agg(id order by id), '[]') from public.activity),
    'competitions',   (select coalesce(jsonb_agg(to_jsonb(c) order by c.id), '[]')
                       from (select id, kind, name, club_id, owner_id, season_id, status, entry, rules, starts_on,
                                    ends_on, is_main, requires_purchase, entitlement_id, signup_open
                             from public.competitions) c),
    'participants',   (select coalesce(jsonb_agg(to_jsonb(p) order by p.id), '[]')
                       from (select id, competition_id, member_id, profile_id, status
                             from public.competition_participants) p),
    'links',          (select coalesce(jsonb_agg(jsonb_build_array(competition_id, round_id, source)
                                                 order by competition_id, round_id), '[]')
                       from public.competition_rounds),
    'kan_lese',       (select coalesce(jsonb_agg(p.round_id::text order by p.round_id::text), '[]')
                       from (select distinct round_id from lokal31.par) p where public.can_read_round(p.round_id)),
    'kan_styre',      (select coalesce(jsonb_agg(p.round_id::text order by p.round_id::text), '[]')
                       from (select distinct round_id from lokal31.par) p where public.is_round_organizer(p.round_id)),
    'kan_fore',       (select coalesce(jsonb_agg(p.round_id::text || ':' || p.member_id::text
                                                 order by p.round_id::text || ':' || p.member_id::text), '[]')
                       from lokal31.par p where public.can_score(p.round_id, p.member_id)),
    'styrer_turnering', (select coalesce(jsonb_agg(c.id order by c.id), '[]')
                         from public.competitions c where public.is_competition_admin(c.id))
  );
$$;

-- Tavla slik dagens app henter den (TavlaQueries): sesongene, kveldene via
-- season_id, de startede rundene i dem, og alle rådata under. Fingeravtrykk
-- (md5) per sesong. Kjøres med role authenticated, så RLS gjelder.
create function lokal31.tavla() returns jsonb language sql stable as $$
  select coalesce(jsonb_object_agg(s.id, jsonb_build_object(
    'rules', s.rules,
    'runder', (select coalesce(jsonb_agg(r.id order by r.id), '[]')
               from public.rounds r join public.events e on e.id = r.event_id
               where e.season_id = s.id and r.status in ('active', 'locked')),
    'scorer', (select md5(coalesce(string_agg(h.round_id || h.member_id::text || h.hole_index || ':' || h.strokes, ','
                                              order by h.round_id, h.member_id, h.hole_index), ''))
               from public.hole_scores h join public.rounds r on r.id = h.round_id
               join public.events e on e.id = r.event_id
               where e.season_id = s.id and r.status in ('active', 'locked')),
    'spillere', (select md5(coalesce(string_agg(p.round_id || p.member_id::text || coalesce(p.bay_no, 0) || p.is_marker,
                                                ',' order by p.round_id, p.member_id), ''))
                 from public.round_players p join public.rounds r on r.id = p.round_id
                 join public.events e on e.id = r.event_id
                 where e.season_id = s.id and r.status in ('active', 'locked')),
    'matcher', (select count(*) from public.round_matches m join public.rounds r on r.id = m.round_id
                join public.events e on e.id = r.event_id
                where e.season_id = s.id and r.status in ('active', 'locked')),
    'sidepremier', (select count(*) from public.side_claims c join public.rounds r on r.id = c.round_id
                    join public.events e on e.id = r.event_id
                    where e.season_id = s.id and r.status in ('active', 'locked'))
  )), '{}')
  from public.seasons s;
$$;
grant execute on function lokal31.bilde() to authenticated;
grant execute on function lokal31.tavla() to authenticated;
grant insert, select on lokal31.for_bilde to authenticated;

create function pg_temp.som(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_uid, false);
$$;
grant execute on all functions in schema pg_temp to public;

-- === Golfgutu-verdenen ======================================================
-- u1 Thomas (arrangør), u2 Anders, u3 Bjørn (markør), u4 Ola (arrangør i en
-- annen klubb), u5 Dag (venter på godkjenning). Carl er et ledig navn.
\set u1 '00000000-0000-0000-0000-000000000001'
\set u2 '00000000-0000-0000-0000-000000000002'
\set u3 '00000000-0000-0000-0000-000000000003'
\set u4 '00000000-0000-0000-0000-000000000004'
\set u5 '00000000-0000-0000-0000-000000000005'
\set klubb   'aaaaaaaa-0000-0000-0000-000000000001'
\set klubb2  'aaaaaaaa-0000-0000-0000-000000000002'
\set thomas  '11111111-0000-0000-0000-000000000001'
\set anders  '11111111-0000-0000-0000-000000000002'
\set bjorn   '11111111-0000-0000-0000-000000000003'
\set carl    '11111111-0000-0000-0000-000000000009'
\set dag     '11111111-0000-0000-0000-000000000005'
\set ola     '22222222-0000-0000-0000-000000000004'

select pg_temp.som('');
insert into auth.users values (:'u1'), (:'u2'), (:'u3'), (:'u4'), (:'u5');

insert into public.clubs (id, name) values (:'klubb', 'Golfgutu'), (:'klubb2', 'Andre');
insert into public.club_members (id, club_id, user_id, display_name, handicap_index, is_organizer, status) values
  (:'thomas', :'klubb',  :'u1', 'Thomas', 14.2, true,  'active'),
  (:'anders', :'klubb',  :'u2', 'Anders', 9.8,  false, 'active'),
  (:'bjorn',  :'klubb',  :'u3', 'Bjørn',  20.1, false, 'active'),
  (:'carl',   :'klubb',  null,  'Carl',   18.0, false, 'active'),
  (:'dag',    :'klubb',  :'u5', 'Dag',    null, false, 'pending'),
  (:'ola',    :'klubb2', :'u4', 'Ola',    5.0,  true,  'active');

insert into public.courses (id, club_id, name) values
  ('cccccccc-0000-0000-0000-000000000001', :'klubb', 'Marco Simone'),
  ('cccccccc-0000-0000-0000-000000000002', :'klubb2', 'Andrebanen');
insert into public.course_holes (course_id, hole_number, par, stroke_index)
select 'cccccccc-0000-0000-0000-000000000001', h, case when h % 3 = 0 then 3 else 4 end, h
from generate_series(1, 18) h;

insert into public.seasons (id, club_id, name, status, rules) values
  ('5eeeeeee-0000-0000-0000-000000002025', :'klubb', 'Sesong 2025', 'finished', '{"version": 1, "preset": "golfgutu"}'),
  ('5eeeeeee-0000-0000-0000-000000002026', :'klubb', 'Sesong 2026', 'active', '{"version": 1, "preset": "golfgutu"}'),
  ('5eeeeeee-0000-0000-0000-000000000099', :'klubb2', 'Andre 2026', 'active', '{"version": 1}');
insert into public.events (id, club_id, season_id, event_date) values
  ('eeeeeeee-0000-0000-0000-000000000001', :'klubb', '5eeeeeee-0000-0000-0000-000000002025', '2025-09-04'),
  ('eeeeeeee-0000-0000-0000-000000000002', :'klubb', '5eeeeeee-0000-0000-0000-000000002026', '2026-09-03'),
  ('eeeeeeee-0000-0000-0000-000000000003', :'klubb', '5eeeeeee-0000-0000-0000-000000002026', '2026-10-01'),
  ('eeeeeeee-0000-0000-0000-000000000004', :'klubb', null,                                   '2026-10-15'),
  ('eeeeeeee-0000-0000-0000-000000000009', :'klubb2', '5eeeeeee-0000-0000-0000-000000000099', '2026-10-01');

insert into public.rounds (id, club_id, event_id, course_id, round_no, hole_count) values
  ('dddddddd-0000-0000-0000-000000000001', :'klubb', 'eeeeeeee-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001', 1, 18),
  ('dddddddd-0000-0000-0000-000000000002', :'klubb', 'eeeeeeee-0000-0000-0000-000000000002', 'cccccccc-0000-0000-0000-000000000001', 1, 18),
  ('dddddddd-0000-0000-0000-000000000003', :'klubb', 'eeeeeeee-0000-0000-0000-000000000003', 'cccccccc-0000-0000-0000-000000000001', 1, 9),
  ('dddddddd-0000-0000-0000-000000000004', :'klubb', 'eeeeeeee-0000-0000-0000-000000000003', 'cccccccc-0000-0000-0000-000000000001', 2, 18),
  ('dddddddd-0000-0000-0000-000000000005', :'klubb', 'eeeeeeee-0000-0000-0000-000000000004', null, 1, 18),
  ('dddddddd-0000-0000-0000-000000000009', :'klubb2', 'eeeeeeee-0000-0000-0000-000000000009', 'cccccccc-0000-0000-0000-000000000002', 1, 18);
insert into public.round_players (round_id, member_id, club_id, bay_no, is_marker) values
  ('dddddddd-0000-0000-0000-000000000001', :'thomas', :'klubb', null, false),
  ('dddddddd-0000-0000-0000-000000000001', :'anders', :'klubb', null, false),
  ('dddddddd-0000-0000-0000-000000000002', :'thomas', :'klubb', null, false),
  ('dddddddd-0000-0000-0000-000000000002', :'anders', :'klubb', null, false),
  ('dddddddd-0000-0000-0000-000000000002', :'bjorn',  :'klubb', null, false),
  ('dddddddd-0000-0000-0000-000000000003', :'anders', :'klubb', 1, false),
  ('dddddddd-0000-0000-0000-000000000003', :'bjorn',  :'klubb', 1, true),
  ('dddddddd-0000-0000-0000-000000000003', :'carl',   :'klubb', 2, false),
  ('dddddddd-0000-0000-0000-000000000003', :'thomas', :'klubb', null, false),
  ('dddddddd-0000-0000-0000-000000000004', :'anders', :'klubb', null, false),
  ('dddddddd-0000-0000-0000-000000000005', :'bjorn',  :'klubb', null, false),
  ('dddddddd-0000-0000-0000-000000000009', :'ola',    :'klubb2', null, false);
insert into public.round_matches (round_id, match_no, player_a, player_b) values
  ('dddddddd-0000-0000-0000-000000000002', 1, :'thomas', :'anders');
update public.rounds set status = 'active'
 where id in ('dddddddd-0000-0000-0000-000000000003', 'dddddddd-0000-0000-0000-000000000009');
insert into public.hole_scores (round_id, member_id, hole_index, strokes)
select r, m, h, 4 + (h % 2)
from (values ('dddddddd-0000-0000-0000-000000000001'::uuid, :'thomas'::uuid), ('dddddddd-0000-0000-0000-000000000001', :'anders'),
             ('dddddddd-0000-0000-0000-000000000002', :'thomas'), ('dddddddd-0000-0000-0000-000000000002', :'anders'),
             ('dddddddd-0000-0000-0000-000000000002', :'bjorn')) v(r, m),
     generate_series(0, 17) h;
insert into public.hole_scores (round_id, member_id, hole_index, strokes)
select 'dddddddd-0000-0000-0000-000000000003', m, h, 5
from (values (:'anders'::uuid), (:'bjorn')) v(m), generate_series(0, 3) h;
insert into public.side_claims (round_id, member_id, kind, meters, hole_index)
values ('dddddddd-0000-0000-0000-000000000002', :'anders', 'drive', 245, 6);
update public.rounds set status = 'locked'
 where id in ('dddddddd-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000002',
              'dddddddd-0000-0000-0000-000000000005');

-- Morroturnering i klubben, med Anders påmeldt og runde 2 lagt til.
insert into public.competitions (id, kind, name, club_id, status, entry)
values ('c0000000-0000-0000-0000-00000000f001', 'fun', 'Morrocupen', :'klubb', 'active', 'listed');
insert into public.competition_participants (competition_id, member_id)
values ('c0000000-0000-0000-0000-00000000f001', :'anders');
insert into public.competition_rounds (competition_id, round_id, source)
values ('c0000000-0000-0000-0000-00000000f001', 'dddddddd-0000-0000-0000-000000000002', 'manual');

-- Aktivitet: ny runde (runde 2), påmelding (kveld 3), og plassbytte i
-- jakkeracet 2026 og i morrocupen.
insert into public.activity (club_id, kind, category, round_id, data) values
  (:'klubb', 'round_started', 'round', 'dddddddd-0000-0000-0000-000000000002', '{}');
insert into public.activity (club_id, kind, category, event_id, data) values
  (:'klubb', 'signup', 'signup', 'eeeeeeee-0000-0000-0000-000000000003', '{}');
insert into public.activity (club_id, kind, category, round_id, data)
select :'klubb', 'table_changed', 'round', 'dddddddd-0000-0000-0000-000000000002',
       jsonb_build_object('competition', c.id)
from public.competitions c where c.season_id = '5eeeeeee-0000-0000-0000-000000002026';
insert into public.activity (club_id, kind, category, round_id, data) values
  (:'klubb', 'table_changed', 'round', 'dddddddd-0000-0000-0000-000000000002',
   '{"competition": "c0000000-0000-0000-0000-00000000f001"}');

insert into lokal31.par select round_id, member_id from public.round_players;

-- === Bildet før 031, per innlogging ==========================================
select pg_temp.som(:'u1'); set role authenticated;
insert into lokal31.for_bilde values (:'u1', lokal31.bilde(), lokal31.tavla()); reset role;
select pg_temp.som(:'u2'); set role authenticated;
insert into lokal31.for_bilde values (:'u2', lokal31.bilde(), lokal31.tavla()); reset role;
select pg_temp.som(:'u3'); set role authenticated;
insert into lokal31.for_bilde values (:'u3', lokal31.bilde(), lokal31.tavla()); reset role;
select pg_temp.som(:'u4'); set role authenticated;
insert into lokal31.for_bilde values (:'u4', lokal31.bilde(), lokal31.tavla()); reset role;
select pg_temp.som(:'u5'); set role authenticated;
insert into lokal31.for_bilde values (:'u5', lokal31.bilde(), lokal31.tavla()); reset role;
select pg_temp.som('');

select 'ok bilde før 031: ' || count(*) || ' innlogginger, Thomas ser '
       || (select jsonb_array_length(bilde -> 'rounds') from lokal31.for_bilde where uid = :'u1') || ' runder'
from lokal31.for_bilde;
