\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Første halvdel av rolleprøven for 017: «verden før». Kjøres i en tom base
-- etter lokal/stub.sql, lokal/stub_storage.sql og 001–016, men FØR 017.
-- Lager en klubb med to sesonger, kvelder, runder (låst, pågår, kladd),
-- scorer, matcher, sidepremier og baner, pluss en annen klubb. Så tar den et
-- bilde av hva hver innlogging ser og kan føre (lokal.bilde), lagret i
-- lokal.for_bilde. lokal/017_prove.sql sammenligner med det etter 017.
-- ===========================================================================

create schema if not exists lokal;
grant usage on schema lokal to authenticated;

-- Alle (runde, spiller)-par, så kanFore prøves også for runder brukeren ikke ser.
create table lokal.par (round_id uuid, member_id uuid);
create table lokal.for_bilde (uid uuid primary key, bilde jsonb);
grant select on lokal.par to authenticated;

-- Hva den innloggede ser og kan, som jsonb. Kjøres med role authenticated, så RLS gjelder.
create function lokal.bilde() returns jsonb language sql stable as $$
  select jsonb_build_object(
    'clubs',          (select coalesce(jsonb_agg(id order by id), '[]') from public.clubs),
    'club_members',   (select coalesce(jsonb_agg(id order by id), '[]') from public.club_members),
    'seasons',        (select coalesce(jsonb_agg(id order by id), '[]') from public.seasons),
    'events',         (select coalesce(jsonb_agg(id order by id), '[]') from public.events),
    'rounds',         (select coalesce(jsonb_agg(id order by id), '[]') from public.rounds),
    'round_players',  (select count(*) from public.round_players),
    'round_holes',    (select count(*) from public.round_holes),
    'round_matches',  (select count(*) from public.round_matches),
    'hole_scores',    (select count(*) from public.hole_scores),
    'side_claims',    (select count(*) from public.side_claims),
    'courses',        (select coalesce(jsonb_agg(id order by id), '[]') from public.courses),
    'course_holes',   (select count(*) from public.course_holes),
    'signups',        (select count(*) from public.signups),
    'activity',       (select count(*) from public.activity),
    'bets',           (select count(*) from public.bets),
    'kan_lese',       (select coalesce(jsonb_agg(p.round_id::text order by p.round_id::text), '[]')
                       from (select distinct round_id from lokal.par) p where public.can_read_round(p.round_id)),
    'kan_styre',      (select coalesce(jsonb_agg(p.round_id::text order by p.round_id::text), '[]')
                       from (select distinct round_id from lokal.par) p where public.is_round_organizer(p.round_id)),
    'kan_fore',       (select coalesce(jsonb_agg(p.round_id::text || ':' || p.member_id::text
                                                 order by p.round_id::text || ':' || p.member_id::text), '[]')
                       from lokal.par p where public.can_score(p.round_id, p.member_id))
  );
$$;
grant execute on function lokal.bilde() to authenticated;
grant insert, select on lokal.for_bilde to authenticated;

create function pg_temp.som(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_uid, false);
$$;
grant execute on all functions in schema pg_temp to public;

-- === Golfgutu-verdenen ======================================================
-- u1 Thomas (arrangør), u2 Anders, u3 Bjørn (markør), u4 Ola (annen klubb),
-- u5 Dag (venter på godkjenning). Carl er et ledig navn uten innlogging.
insert into auth.users values
 ('00000000-0000-0000-0000-000000000001'), ('00000000-0000-0000-0000-000000000002'),
 ('00000000-0000-0000-0000-000000000003'), ('00000000-0000-0000-0000-000000000004'),
 ('00000000-0000-0000-0000-000000000005');

\set klubb   'aaaaaaaa-0000-0000-0000-000000000001'
\set klubb2  'aaaaaaaa-0000-0000-0000-000000000002'
\set thomas  '11111111-0000-0000-0000-000000000001'
\set anders  '11111111-0000-0000-0000-000000000002'
\set bjorn   '11111111-0000-0000-0000-000000000003'
\set carl    '11111111-0000-0000-0000-000000000009'
\set dag     '11111111-0000-0000-0000-000000000005'
\set ola     '22222222-0000-0000-0000-000000000004'
\set u1 '00000000-0000-0000-0000-000000000001'
\set u2 '00000000-0000-0000-0000-000000000002'
\set u3 '00000000-0000-0000-0000-000000000003'
\set u4 '00000000-0000-0000-0000-000000000004'
\set u5 '00000000-0000-0000-0000-000000000005'

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

-- Sesong 2025 (ferdig) og 2026 (aktiv), hver med kvelder og runder.
insert into public.seasons (id, club_id, name, status) values
  ('5eeeeeee-0000-0000-0000-000000002025', :'klubb', 'Sesong 2025', 'finished'),
  ('5eeeeeee-0000-0000-0000-000000002026', :'klubb', 'Sesong 2026', 'active'),
  ('5eeeeeee-0000-0000-0000-000000000099', :'klubb2', 'Andre 2026', 'active');
insert into public.events (id, club_id, season_id, event_date) values
  ('eeeeeeee-0000-0000-0000-000000000001', :'klubb', '5eeeeeee-0000-0000-0000-000000002025', '2025-09-04'),
  ('eeeeeeee-0000-0000-0000-000000000002', :'klubb', '5eeeeeee-0000-0000-0000-000000002026', '2026-09-03'),
  ('eeeeeeee-0000-0000-0000-000000000003', :'klubb', '5eeeeeee-0000-0000-0000-000000002026', '2026-10-01'),
  ('eeeeeeee-0000-0000-0000-000000000004', :'klubb', null,                                   '2026-10-15'),
  ('eeeeeeee-0000-0000-0000-000000000009', :'klubb2', '5eeeeeee-0000-0000-0000-000000000099', '2026-10-01');

-- r1: 2025, låst. r2: 2026 kveld 1, låst med match og sidepremie. r3: 2026
-- kveld 2, pågår, bås med markør (Bjørn). r4: kladd. r5: kveld uten sesong.
-- r9: den andre klubben.
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
-- Høyst én pågående runde per klubb: r3 pågår, r9 i den andre klubben.
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

insert into lokal.par select round_id, member_id from public.round_players;

-- === Bildet før 017, per innlogging ==========================================
select pg_temp.som(:'u1'); set role authenticated;
insert into lokal.for_bilde values (:'u1', lokal.bilde()); reset role;
select pg_temp.som(:'u2'); set role authenticated;
insert into lokal.for_bilde values (:'u2', lokal.bilde()); reset role;
select pg_temp.som(:'u3'); set role authenticated;
insert into lokal.for_bilde values (:'u3', lokal.bilde()); reset role;
select pg_temp.som(:'u4'); set role authenticated;
insert into lokal.for_bilde values (:'u4', lokal.bilde()); reset role;
select pg_temp.som(:'u5'); set role authenticated;
insert into lokal.for_bilde values (:'u5', lokal.bilde()); reset role;
select pg_temp.som('');

select 'ok bilde før 017: ' || count(*) || ' innlogginger, Thomas ser ' ||
       jsonb_array_length(bilde -> 'rounds') || ' runder'
from lokal.for_bilde, lateral (select 1) x where uid = :'u1' group by bilde;
