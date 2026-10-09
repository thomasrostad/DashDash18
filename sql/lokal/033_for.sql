\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Første halvdel av rolleprøven for 033: «verden før». Kjøres i en tom,
-- lokal Postgres etter lokal/stub.sql, lokal/stub_storage.sql, 001–030
-- (rekkefølgen i sql/README.md), lokal/031_for.sql, 031, lokal/032_for.sql,
-- 032, 036, 037 og 038, men FØR 033.
--
-- Bruker Golfgutu-verdenen fra lokal/031_for.sql. Legger til et
-- simulatorsenter (u7) med en liga som har en egen spilledag og en låst runde
-- (slik test kan ha det etter 031: runden er IKKE koblet til ligaen før 033).
-- Så tar den et bilde per innlogging av:
--   * det dagens app ser og kan (lokal32.bilde) og Tavla (lokal31.tavla),
--   * svarene fra 036 (tavla_data for hver sesong), 037 (known_profiles,
--     my_competition_ids, my_competitions, my_loose_rounds, my_activity),
-- og svaret fra delete_tournament (038, i en transaksjon som rulles
-- tilbake) og paritetskontrollen (10.2). lokal/033_prove.sql sammenligner
-- med det etter 033.
-- ===========================================================================

create schema if not exists lokal33;
grant usage on schema lokal33 to authenticated;

create table lokal33.for_bilde (uid uuid primary key, bilde jsonb, tavla jsonb, rpc jsonb);
create table lokal33.sesonger as select id from public.seasons;
create table lokal33.klubber as select id from public.clubs;
create table lokal33.slett (hva text primary key, svar text);
grant insert, select on lokal33.for_bilde to authenticated;
grant select on lokal33.sesonger, lokal33.klubber to authenticated;

-- Svarene fra RPC-ene i 036 og 037 for den innloggede. tavla_data kalles for
-- alle sesonger; der den innloggede ikke er medlem, lagres feilkoden.
create function lokal33.rpc() returns jsonb language plpgsql as $$
declare
  s record;
  v_tavla jsonb := '{}';
  d jsonb;
begin
  for s in select id from lokal33.sesonger order by id loop
    begin
      d := public.tavla_data(s.id);
    exception when others then
      d := to_jsonb(sqlstate);
    end;
    v_tavla := v_tavla || jsonb_build_object(s.id::text, d);
  end loop;
  return jsonb_build_object(
    'tavla_data',         v_tavla,
    'known_profiles',     (select coalesce(jsonb_agg(p.id order by p.id), '[]') from public.known_profiles() p),
    'my_competition_ids', (select coalesce(jsonb_agg(x order by x), '[]') from unnest(public.my_competition_ids()) x),
    'my_competitions',    (select coalesce(jsonb_agg(to_jsonb(c) - 'updated_at' order by c.id), '[]')
                           from public.my_competitions() c),
    'my_loose_rounds',    (select coalesce(jsonb_agg(r.id order by r.id), '[]') from public.my_loose_rounds() r),
    'my_activity',        (select coalesce(jsonb_agg(a.id order by a.id), '[]')
                           from public.my_activity((select array_agg(id) from lokal33.klubber), '2000-01-01'::timestamptz) a));
end $$;
grant execute on function lokal33.rpc() to authenticated;

-- Paritetskontrollen (10.2) slik 032 lagret den.
create table lokal33.paritet_for as select lokal32.paritet() as svar;

create function pg_temp.som(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_uid, false);
$$;
grant execute on all functions in schema pg_temp to public;

\set u1 '00000000-0000-0000-0000-000000000001'
\set u2 '00000000-0000-0000-0000-000000000002'
\set u3 '00000000-0000-0000-0000-000000000003'
\set u4 '00000000-0000-0000-0000-000000000004'
\set u5 '00000000-0000-0000-0000-000000000005'
\set u7 '00000000-0000-0000-0000-000000000007'
\set klubb3  'aaaaaaaa-0000-0000-0000-000000000003'
\set liga3   'c0000000-0000-0000-0000-0000000a0003'
\set dag3    'eeeeeeee-0000-0000-0000-000000000031'
\set r31     'dddddddd-0000-0000-0000-000000000031'

-- === Simulatorsenteret med en liga og en egen spilledag (før 033) ============
select pg_temp.som('');
insert into auth.users values (:'u7');
insert into public.clubs (id, name, kind) values (:'klubb3', 'Simsenteret', 'simulator_center');
insert into public.club_members (id, club_id, user_id, display_name, is_organizer, status)
values ('33333333-0000-0000-0000-000000000007', :'klubb3', :'u7', 'Siv', true, 'active');
insert into public.competitions (id, kind, name, club_id, status, entry)
values (:'liga3', 'league', 'Tirsdagsligaen', :'klubb3', 'active', 'listed');
insert into public.events (id, club_id, competition_id, event_date)
values (:'dag3', :'klubb3', :'liga3', '2026-10-06');
insert into public.rounds (id, club_id, event_id, round_no, hole_count)
values (:'r31', :'klubb3', :'dag3', 1, 18);
insert into public.round_players (round_id, member_id, club_id)
values (:'r31', '33333333-0000-0000-0000-000000000007', :'klubb3');
update public.rounds set status = 'locked' where id = :'r31';
insert into lokal33.klubber values (:'klubb3');

select 'ok verden før 033: ligaens runde er ikke koblet (' ||
       (select count(*) from public.competition_rounds where round_id = :'r31') || ' koblinger), spilledagen har sesong '
       || coalesce((select season_id::text from public.events where id = :'dag3'), 'ingen');

-- === Bildet før 033, per innlogging ==========================================
select pg_temp.som(:'u1'); set role authenticated;
insert into lokal33.for_bilde values (:'u1', lokal32.bilde(), lokal31.tavla(), lokal33.rpc()); reset role;
select pg_temp.som(:'u2'); set role authenticated;
insert into lokal33.for_bilde values (:'u2', lokal32.bilde(), lokal31.tavla(), lokal33.rpc()); reset role;
select pg_temp.som(:'u3'); set role authenticated;
insert into lokal33.for_bilde values (:'u3', lokal32.bilde(), lokal31.tavla(), lokal33.rpc()); reset role;
select pg_temp.som(:'u4'); set role authenticated;
insert into lokal33.for_bilde values (:'u4', lokal32.bilde(), lokal31.tavla(), lokal33.rpc()); reset role;
select pg_temp.som(:'u5'); set role authenticated;
insert into lokal33.for_bilde values (:'u5', lokal32.bilde(), lokal31.tavla(), lokal33.rpc()); reset role;
select pg_temp.som('');

-- === 038: delete_tournament for jakkeracet 2026 og Morrocupen, rullet tilbake =
select c.id as j2026 from public.competitions c where c.season_id = '5eeeeeee-0000-0000-0000-000000002026' \gset
begin;
select pg_temp.som(:'u1'); set role authenticated;
select public.delete_tournament(:'j2026', 'Sesong 2026')::text as slett_j2026 \gset
select public.delete_tournament('c0000000-0000-0000-0000-00000000f001', 'Morrocupen')::text as slett_morro \gset
rollback;
select pg_temp.som('');
insert into lokal33.slett values ('j2026', :'slett_j2026'), ('morro', :'slett_morro');

select 'ok bilde før 033: ' || count(*) || ' innlogginger; tavla_data for '
       || (select count(*) from lokal33.sesonger) || ' sesonger; paritet: '
       || (select jsonb_array_length(svar) from lokal33.paritet_for) || ' sesonger, alle like: '
       || (select bool_and((x ->> 'lik')::boolean) from lokal33.paritet_for, jsonb_array_elements(svar) x)
from lokal33.for_bilde;
select 'ok delete_tournament før 033: ' || string_agg(hva || ' ' || svar, '; ' order by hva) from lokal33.slett;
