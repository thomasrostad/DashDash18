\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Første halvdel av rolleprøven for 032: «verden før». Kjøres i en tom,
-- lokal Postgres etter lokal/stub.sql, lokal/stub_storage.sql, 001–030
-- (rekkefølgen i sql/README.md), lokal/031_for.sql og 031, men FØR 032.
--
-- Bruker Golfgutu-verdenen fra lokal/031_for.sql. Tar et bilde av hva hver
-- innlogging ser og kan (lokal31.bilde, pluss hvilke turneringer den kan
-- lese og deltar i) og Tavla per sesong (lokal31.tavla), og lagrer svaret på
-- paritetskontrollen fra docs/fase-22-turnering-som-kjerne.md (10.2).
-- lokal/032_prove.sql sammenligner med det etter 032.
-- ===========================================================================

create schema if not exists lokal32;
grant usage on schema lokal32 to authenticated;

create table lokal32.for_bilde (uid uuid primary key, bilde jsonb, tavla jsonb);
grant insert, select on lokal32.for_bilde to authenticated;

-- lokal31.bilde() pluss turneringene innloggingen kan lese og deltar i.
create function lokal32.bilde() returns jsonb language sql stable as $$
  select lokal31.bilde() || jsonb_build_object(
    'leser_turnering', (select coalesce(jsonb_agg(c.id order by c.id), '[]')
                        from public.competitions c where public.can_read_competition(c.id)),
    'deltar',          (select coalesce(jsonb_agg(c.id order by c.id), '[]')
                        from public.competitions c where public.is_competition_participant(c.id)),
    'start_groups',    (select count(*) from public.round_start_groups)
  );
$$;
grant execute on function lokal32.bilde() to authenticated;

-- Paritetskontrollen (10.2), uendret fra dokumentet.
create function lokal32.paritet() returns jsonb language sql stable as $$
  with grunnlag as (
    select s.id as season_id, s.name,
           (select md5(coalesce(string_agg(h.round_id::text || h.member_id || h.hole_index || ':' || h.strokes, ','
                                           order by h.round_id, h.member_id, h.hole_index), ''))
              from public.hole_scores h
              join public.rounds r on r.id = h.round_id
              join public.events e on e.id = r.event_id
             where e.season_id = s.id and r.status in ('active', 'locked')) as via_sesong,
           (select md5(coalesce(string_agg(h.round_id::text || h.member_id || h.hole_index || ':' || h.strokes, ','
                                           order by h.round_id, h.member_id, h.hole_index), ''))
              from public.hole_scores h
              join public.rounds r on r.id = h.round_id
              join public.competition_rounds cr on cr.round_id = r.id
              join public.competitions c on c.id = cr.competition_id
             where c.season_id = s.id and cr.source = 'season' and r.status in ('active', 'locked')) as via_turnering,
           (select count(*) from public.round_players p join public.rounds r on r.id = p.round_id
              join public.events e on e.id = r.event_id
             where e.season_id = s.id and r.status in ('active', 'locked')) as spillere,
           (select count(*) from public.round_matches m join public.rounds r on r.id = m.round_id
              join public.events e on e.id = r.event_id
             where e.season_id = s.id and r.status in ('active', 'locked')) as matcher,
           (select count(*) from public.side_claims c2 join public.rounds r on r.id = c2.round_id
              join public.events e on e.id = r.event_id
             where e.season_id = s.id and r.status in ('active', 'locked')) as sidepremier,
           md5(s.rules::text) as regler
    from public.seasons s
  )
  select coalesce(jsonb_agg(to_jsonb(g) || jsonb_build_object('lik', g.via_sesong = g.via_turnering)
                            order by g.name), '[]')
  from grunnlag g;
$$;

create table lokal32.paritet_for as select lokal32.paritet() as svar;

create function pg_temp.som(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_uid, false);
$$;
grant execute on all functions in schema pg_temp to public;

\set u1 '00000000-0000-0000-0000-000000000001'
\set u2 '00000000-0000-0000-0000-000000000002'
\set u3 '00000000-0000-0000-0000-000000000003'
\set u4 '00000000-0000-0000-0000-000000000004'
\set u5 '00000000-0000-0000-0000-000000000005'

select pg_temp.som(:'u1'); set role authenticated;
insert into lokal32.for_bilde values (:'u1', lokal32.bilde(), lokal31.tavla()); reset role;
select pg_temp.som(:'u2'); set role authenticated;
insert into lokal32.for_bilde values (:'u2', lokal32.bilde(), lokal31.tavla()); reset role;
select pg_temp.som(:'u3'); set role authenticated;
insert into lokal32.for_bilde values (:'u3', lokal32.bilde(), lokal31.tavla()); reset role;
select pg_temp.som(:'u4'); set role authenticated;
insert into lokal32.for_bilde values (:'u4', lokal32.bilde(), lokal31.tavla()); reset role;
select pg_temp.som(:'u5'); set role authenticated;
insert into lokal32.for_bilde values (:'u5', lokal32.bilde(), lokal31.tavla()); reset role;
select pg_temp.som('');

select 'ok bilde før 032: ' || count(*) || ' innlogginger; paritet: '
       || (select jsonb_array_length(svar) from lokal32.paritet_for) || ' sesonger, alle like: '
       || (select bool_and((x ->> 'lik')::boolean) from lokal32.paritet_for, jsonb_array_elements(svar) x)
from lokal32.for_bilde;
select '  ' || (x ->> 'name') || ': via_sesong=' || coalesce(x ->> 'via_sesong', 'null')
       || ' via_turnering=' || coalesce(x ->> 'via_turnering', 'null') || ' lik=' || coalesce(x ->> 'lik', 'null')
from lokal32.paritet_for, jsonb_array_elements(svar) x;
