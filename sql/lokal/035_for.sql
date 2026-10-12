\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Første halvdel av prøven for 035_sesong_som_view.sql: «verden før». Kjøres på
-- en kopi av den lokale kjeden til og med 054 (001–054 med 034; lokal31-, lokal32-
-- og lokal33-hjelperne fra 031/032/033-prøvene finnes der), FØR 035.
--
-- Lager skjemaet lokal35 med:
--   lokal35.q(uid, sql)      kjører en spørring eller skriving (med returning) som
--                            innlogget (authenticated) eller som server (uid null) og
--                            svarer med radene som JSON, eller {"feil": sqlstate}.
--                            Feiler den, rulles bare den tilbake (som én forespørsel).
--   lokal35.bilde()          alt per innlogging: lokal32.bilde (det dagens app ser og
--                            kan, med seasons), lokal31.tavla, lokal33.rpc (tavla_data
--                            for 033-sesongene og 037-RPC-ene), tavla_data for ALLE
--                            sesonger, sesonglista slik gamle bygg leser den (seasons)
--                            og slik den nye appen leser den (competitions med
--                            season_id, steg 3 del A), og veddemålene.
--   lokal35.server()         det samme uten innlogging: paritetskontrollen (10.2),
--                            veddemålene og kveldene med sesong og turnering, bet_rule
--                            og bet_points per sesong.
--   lokal35.scenario()       gamle bygg skriver seasons (ny, nytt navn og regler,
--                            activate_season med og uten hovedturnering, avslutt, slett
--                            planlagt, ikke lov, kvelder stopper, dobbel id), den nye
--                            appen skriver competitions, delete_tournament med kvelder
--                            og veddemål, og create_bet uten kveld. Alt i en
--                            deltransaksjon som rulles tilbake; svaret er JSON uten
--                            tider og tilfeldige id-er.
-- og lagrer svarene i lokal35.for_bilde, lokal35.for_server og lokal35.for_scenario.
-- lokal/035_prove.sql tar de samme etter 035 og sammenligner.
-- ===========================================================================

drop schema if exists lokal35 cascade;
create schema lokal35;
grant usage on schema lokal35 to authenticated;

create table lokal35.sesonger as select id, club_id from public.seasons;
create table lokal35.brukere (uid uuid primary key);
insert into lokal35.brukere select id from auth.users;
grant select on lokal35.sesonger, lokal35.brukere to authenticated;

create table lokal35.for_bilde (uid uuid primary key, bilde jsonb);
create table lokal35.for_server (bilde jsonb);
create table lokal35.for_scenario (svar jsonb);
grant insert on lokal35.for_bilde to authenticated;

create function lokal35.q(p_uid text, p_sql text) returns jsonb language plpgsql as $$
declare
  v jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid, ''), true);
  if p_uid is not null then
    perform set_config('role', 'authenticated', true);
  end if;
  begin
    execute 'with x as (' || p_sql || ') select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from x' into v;
  exception when others then
    v := jsonb_build_object('feil', sqlstate);
  end;
  perform set_config('role', 'none', true);
  perform set_config('request.jwt.claim.sub', '', true);
  return v;
end $$;

-- Per innlogging (kalles som authenticated med request.jwt.claim.sub satt).
create function lokal35.bilde() returns jsonb language plpgsql as $$
declare
  v_s record;
  v_tavla jsonb := '{}';
  d jsonb;
begin
  for v_s in select id from lokal35.sesonger order by id loop
    begin
      d := public.tavla_data(v_s.id);
    exception when others then
      d := to_jsonb(sqlstate);
    end;
    v_tavla := v_tavla || jsonb_build_object(v_s.id::text, d);
  end loop;
  return lokal32.bilde() || jsonb_build_object(
    'tavla',       lokal31.tavla(),
    'rpc',         lokal33.rpc(),
    'tavla_data',  v_tavla,
    'sesongliste', (select coalesce(jsonb_agg(to_jsonb(l) order by l.created_at desc, l.id), '[]')
                    from (select id, club_id, name, status, rules, created_at from public.seasons) l),
    'ny_app',      (select coalesce(jsonb_agg(to_jsonb(c) order by c.created_at desc, c.id), '[]')
                    from (select season_id as id, club_id, name, status, rules, created_at
                            from public.competitions where season_id is not null) c),
    'veddemaal',   (select coalesce(jsonb_agg(jsonb_build_array(b.id, b.season_id, b.competition_id, b.status)
                                              order by b.id), '[]')
                    from public.bets b)
  );
end $$;

-- Uten innlogging.
create function lokal35.server() returns jsonb language sql as $$
  select jsonb_build_object(
    'paritet',   lokal32.paritet(),
    'veddemaal', (select coalesce(jsonb_agg(jsonb_build_array(b.id, b.club_id, b.season_id, b.competition_id,
                                                                b.round_scope, b.status) order by b.id), '[]')
                  from public.bets b),
    'veddemaal_per_sesong', (select coalesce(jsonb_object_agg(s.id, (select count(*) from public.bets b
                                                                     where b.season_id = s.id)), '{}')
                             from lokal35.sesonger s),
    'kvelder',   (select coalesce(jsonb_agg(jsonb_build_array(e.id, e.club_id, e.season_id, e.competition_id,
                                                              e.updated_at) order by e.id), '[]')
                  from public.events e),
    'sesonger',  (select coalesce(jsonb_agg(to_jsonb(s) order by s.id), '[]')
                  from (select id, club_id, name, status, rules, created_at from public.seasons) s),
    'turneringer', (select coalesce(jsonb_agg(jsonb_build_array(c.id, c.season_id, c.name, c.status, c.rules,
                                                                c.is_main, c.entry, c.created_at) order by c.id), '[]')
                    from public.competitions c),
    'bet_rule',  (select coalesce(jsonb_object_agg(s.id, jsonb_build_array(
                                    public.bet_rule(s.id, 'start', 7), public.bet_rule(s.id, 'max_stake', 7),
                                    public.bet_rule(s.id, 'finnes_ikke', 7))), '{}')
                  from lokal35.sesonger s)
  );
$$;

-- Gamle bygg og den nye appen skriver. Svarene uten tider og uten id-ene til nye turneringsrader.
create function lokal35.scenario() returns jsonb language plpgsql as $$
declare
  u1 constant text := '00000000-0000-0000-0000-000000000001';
  u2 constant text := '00000000-0000-0000-0000-000000000002';
  u4 constant text := '00000000-0000-0000-0000-000000000004';
  u7 constant text := '00000000-0000-0000-0000-000000000007';
  k1 constant text := 'aaaaaaaa-0000-0000-0000-000000000001';
  k3 constant text := 'aaaaaaaa-0000-0000-0000-000000000003';
  s25 constant text := '5eeeeeee-0000-0000-0000-000000002025';
  s26 constant text := '5eeeeeee-0000-0000-0000-000000002026';
  x  constant text := '5eeeeeee-0000-0000-0000-00000000035a';
  y  constant text := '5eeeeeee-0000-0000-0000-00000000035b';
  z  constant text := '5eeeeeee-0000-0000-0000-00000000035c';
  r  jsonb := '{}';
  -- Tilstanden til klubbens sesonger: status og hovedturnering per sesong.
  tilstand constant text := 'select c.season_id, c.name, c.status, c.is_main, c.entry, c.kind, c.rules '
                            'from public.competitions c where c.season_id is not null and c.club_id = ''%s'' '
                            'order by c.season_id';
  rad constant text := 'id, club_id, name, status, rules';
begin
  begin
    -- A. Simsenteret (u7 er arrangør; Vinter er aktiv hovedturnering, Vår planlagt).
    r := r || jsonb_build_object('a1_ny',
      lokal35.q(u7, format('insert into public.seasons (id, club_id, name, rules) values (%L, %L, %L, %L) returning %s',
                           x, k3, 'Høst 035', '{"version": 2}', rad)));
    r := r || jsonb_build_object('a1_tilstand', lokal35.q(null, format(tilstand, k3)));
    r := r || jsonb_build_object('a2_navn_regler',
      lokal35.q(u7, format('update public.seasons set name = %L, rules = %L where id = %L returning %s',
                           'Høst 035 b', '{"version": 2, "bets": {"start": 50}}', x, rad)));
    r := r || jsonb_build_object('a2_tilstand', lokal35.q(null, format(tilstand, k3)));
    r := r || jsonb_build_object('a3_aktiver_ved_siden',
      lokal35.q(u7, format('select id, club_id, name, status, rules from public.activate_season(%L, false)', x)));
    r := r || jsonb_build_object('a3_tilstand', lokal35.q(null, format(tilstand, k3)));
    r := r || jsonb_build_object('a4_aktiver_hoved',
      lokal35.q(u7, format('select id, club_id, name, status, rules from public.activate_season(%L)', x)));
    r := r || jsonb_build_object('a4_tilstand', lokal35.q(null, format(tilstand, k3)));
    r := r || jsonb_build_object('a5_avslutt',
      lokal35.q(u7, format('update public.seasons set status = %L where id = %L returning %s', 'finished', x, rad)));
    r := r || jsonb_build_object('a5_tilstand', lokal35.q(null, format(tilstand, k3)));
    r := r || jsonb_build_object('a6_ny_planlagt',
      lokal35.q(u7, format('insert into public.seasons (id, club_id, name, status) values (%L, %L, %L, %L) returning %s',
                           y, k3, 'Slettes', 'planned', rad)));
    r := r || jsonb_build_object('a6_slett_planlagt',
      lokal35.q(u7, format('delete from public.seasons where id = %L returning id, name', y)));
    r := r || jsonb_build_object('a6_slett_ferdig',
      lokal35.q(u7, format('delete from public.seasons where id = %L returning id, name', x)));
    r := r || jsonb_build_object('a6_tilstand', lokal35.q(null, format(tilstand, k3)));
    r := r || jsonb_build_object('a7_lese_u7',
      lokal35.q(u7, 'select id, name, status from public.seasons order by id'));

    -- B. Ikke lov: medlem uten rettighet (u2) og en i en annen klubb (u4).
    r := r || jsonb_build_object('b1_ny_u2',
      lokal35.q(u2, format('insert into public.seasons (club_id, name) values (%L, %L) returning id', k1, 'Ulovlig')));
    r := r || jsonb_build_object('b2_navn_u2',
      lokal35.q(u2, format('update public.seasons set name = %L where id = %L returning id', 'Ulovlig', s26)));
    r := r || jsonb_build_object('b3_slett_u2',
      lokal35.q(u2, format('delete from public.seasons where id = %L returning id', s25)));
    r := r || jsonb_build_object('b4_aktiver_u2',
      lokal35.q(u2, format('select id from public.activate_season(%L)', s25)));
    r := r || jsonb_build_object('b5_navn_u4',
      lokal35.q(u4, format('update public.seasons set name = %L where id = %L returning id', 'Ulovlig', s26)));
    r := r || jsonb_build_object('b6_lese_u4',
      lokal35.q(u4, format('select id from public.seasons where id = %L', s26)));
    r := r || jsonb_build_object('b7_aktiver_u4',
      lokal35.q(u4, format('select id from public.activate_season(%L)', s26)));
    r := r || jsonb_build_object('b8_uten_innlogging',
      lokal35.q(null, format('select id from public.activate_season(%L)', s26)));
    r := r || jsonb_build_object('b9_tilstand', lokal35.q(null, format(tilstand, k1)));

    -- C. Golfgutu (u1 er arrangør): kvelder stopper slettingen, dobbel id, ukjent sesong.
    r := r || jsonb_build_object('c1_ny',
      lokal35.q(u1, format('insert into public.seasons (id, club_id, name) values (%L, %L, %L) returning %s',
                           z, k1, 'Med kveld', rad)));
    r := r || jsonb_build_object('c1_kveld',
      lokal35.q(u1, format('insert into public.events (club_id, season_id, event_date) values (%L, %L, %L) '
                           'returning season_id, (competition_id is not null) as har_turnering', k1, z, '2027-05-06')));
    r := r || jsonb_build_object('c2_slett_med_kveld',
      lokal35.q(u1, format('delete from public.seasons where id = %L returning id', z)));
    r := r || jsonb_build_object('c3_dobbel_id',
      lokal35.q(u1, format('insert into public.seasons (id, club_id, name) values (%L, %L, %L) returning id',
                           s26, k1, 'Dobbel')));
    r := r || jsonb_build_object('c4_ukjent',
      lokal35.q(u1, format('select id from public.activate_season(%L)', x)));
    r := r || jsonb_build_object('c5_tomt_navn',
      lokal35.q(u1, format('update public.seasons set name = %L where id = %L returning id', ' ', s26)));

    -- D. Den nye appen skriver competitions (regler og navn), gamle bygg ser det i seasons.
    r := r || jsonb_build_object('d1_regler',
      lokal35.q(u1, format('update public.competitions set rules = %L, name = %L where season_id = %L '
                           'returning season_id as id, club_id, name, status, rules',
                           '{"version": 2, "bets": {"start": 80}}', 'Sesong 2026 b', s26)));
    r := r || jsonb_build_object('d1_seasons',
      lokal35.q(u1, format('select %s from public.seasons where id = %L', rad, s26)));
    r := r || jsonb_build_object('d2_bet_rule',
      lokal35.q(u1, format('select public.bet_rule(%L, %L, 7) as start', s26, 'start')));
    r := r || jsonb_build_object('d3_avslutt',
      lokal35.q(u1, format('update public.competitions set status = %L where season_id = %L '
                           'returning season_id as id, status', 'finished', s26)));
    r := r || jsonb_build_object('d3_tilstand', lokal35.q(null, format(tilstand, k1)));
    r := r || jsonb_build_object('d4_aktiver_2025',
      lokal35.q(u1, format('select id, name, status from public.activate_season(%L)', s25)));
    r := r || jsonb_build_object('d4_tilstand', lokal35.q(null, format(tilstand, k1)));
    r := r || jsonb_build_object('d5_aktiver_2026_hoved',
      lokal35.q(u1, format('select id, name, status from public.activate_season(%L)', s26)));
    r := r || jsonb_build_object('d5_tilstand', lokal35.q(null, format(tilstand, k1)));

    -- E. create_bet uten kveld velger hovedturneringen (2026).
    r := r || jsonb_build_object('e1_veddemaal',
      lokal35.q(u1, format('select (public.create_bet(%L, null, null, %L, null, null, %L, 1) ? %L) as laget',
                           k1, 'Noen vinner i kveld', 'yes', 'bet_id')));
    r := r || jsonb_build_object('e1_sesong',
      lokal35.q(null, format('select season_id, (competition_id is not null) as turnering from public.bets '
                             'where club_id = %L and question = %L', k1, 'Noen vinner i kveld')));

    -- F. delete_tournament på Sesong 2026 (kvelder, runder og veddemål).
    r := r || jsonb_build_object('f1_slett_turnering',
      lokal35.q(u1, format('select public.delete_tournament(c.id, c.name) as svar from public.competitions c '
                           'where c.season_id = %L', s26)));
    r := r || jsonb_build_object('f1_etter',
      lokal35.q(null, format('select (select count(*) from public.seasons where id = %1$L) as sesong, '
                             '(select count(*) from public.competitions where season_id = %1$L) as turnering, '
                             '(select count(*) from public.events where season_id = %1$L) as kvelder, '
                             '(select count(*) from public.bets where season_id = %1$L) as veddemaal', s26)));
    r := r || jsonb_build_object('f1_tilstand', lokal35.q(null, format(tilstand, k1)));

    raise exception using errcode = 'ZZ035', message = r::text;
  exception when sqlstate 'ZZ035' then
    return sqlerrm::jsonb;
  end;
end $$;

grant execute on all functions in schema lokal35 to authenticated;

-- ===========================================================================
-- Bildene før 035
-- ===========================================================================
do $$
declare
  b record;
begin
  for b in select uid from lokal35.brukere order by uid loop
    perform set_config('request.jwt.claim.sub', b.uid::text, false);
    set role authenticated;
    insert into lokal35.for_bilde (uid, bilde) select b.uid, lokal35.bilde();
    reset role;
  end loop;
  perform set_config('request.jwt.claim.sub', '', false);
end $$;

insert into lokal35.for_server (bilde) select lokal35.server();
insert into lokal35.for_scenario (svar) select lokal35.scenario();

select 'før 035: ' || (select count(*) from lokal35.for_bilde) || ' innlogginger, '
       || (select count(*) from jsonb_object_keys((select svar from lokal35.for_scenario))) || ' steg i scenariet, '
       || (select jsonb_array_length(bilde -> 'paritet') from lokal35.for_server) || ' sesonger i paritetskontrollen';
