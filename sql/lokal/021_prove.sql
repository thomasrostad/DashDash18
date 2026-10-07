\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Rolleprøve for 021_statistikk.sql. Rekkefølge i en tom, lokal Postgres:
--   lokal/stub.sql, lokal/stub_storage.sql, 001–016, lokal/017_for.sql,
--   017_fundament.sql, lokal/017_prove.sql, 021_statistikk.sql (gjerne to
--   ganger), lokal/021_prove.sql.
-- Hver resultatlinje skal starte med "ok"; ingen "FEIL".
--
-- Bygger på verdenen fra 017_for/017_prove: r3 pågår (9 hull, Marco Simone,
-- par 3 på hull 3, 6, 9), Anders og Bjørn (markør) i bås 1, Carl i bås 2 uten
-- markør, Thomas uten bås. r2 er låst. Ola er i en annen klubb. Losby er en
-- felles bane (par 4 overalt).
-- ===========================================================================

create function pg_temp.feil(p_sql text, p_kode text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'FEIL (gikk gjennom): ' || p_sql;
exception when others then
  if sqlstate = p_kode then return 'ok ' || p_kode || ': ' || left(sqlerrm, 70);
  else return 'FEIL ' || sqlstate || ': ' || sqlerrm || ' <- ' || p_sql; end if;
end $$;
create function pg_temp.lik(p_verdi anyelement, p_forventet anyelement, p_hva text) returns text language sql as $$
  select case when p_verdi is not distinct from p_forventet then 'ok ' || p_hva
              else 'FEIL ' || p_hva || ': fikk ' || coalesce(p_verdi::text, 'null') || ', forventet ' || coalesce(p_forventet::text, 'null') end
$$;
create function pg_temp.som(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_uid, false);
$$;
grant execute on all functions in schema pg_temp to public;

\set klubb   'aaaaaaaa-0000-0000-0000-000000000001'
\set thomas  '11111111-0000-0000-0000-000000000001'
\set anders  '11111111-0000-0000-0000-000000000002'
\set bjorn   '11111111-0000-0000-0000-000000000003'
\set carl    '11111111-0000-0000-0000-000000000009'
\set u1 '00000000-0000-0000-0000-000000000001'
\set u2 '00000000-0000-0000-0000-000000000002'
\set u3 '00000000-0000-0000-0000-000000000003'
\set u4 '00000000-0000-0000-0000-000000000004'
\set r2      'dddddddd-0000-0000-0000-000000000002'
\set r3      'dddddddd-0000-0000-0000-000000000003'

select id as losby from public.courses where name = 'Losby' \gset

-- === A. Klubbrunde som pågår: spilleren selv, markøren og arrangøren ========
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik(public.can_score(:'r3', :'anders'), false, 'Anders fører ikke slag selv (Bjørn er markør i båsen)');
insert into public.hole_stats (round_id, member_id, hole_index, fairway, putts, updated_by)
values (:'r3', :'anders', 0, 'hit', 2, :'u4') returning 'ok Anders fører egen fairway og putter (tillegget i 021)';
select pg_temp.lik((select updated_by::text from public.hole_stats where round_id = :'r3' and member_id = :'anders' and hole_index = 0),
                   :'u2', 'updated_by settes av serveren (kan ikke forfalskes)');
update public.hole_stats set green_in_regulation = true where round_id = :'r3' and member_id = :'anders' and hole_index = 0;
select pg_temp.lik((select green_in_regulation from public.hole_stats where round_id = :'r3' and member_id = :'anders' and hole_index = 0),
                   true, 'Anders endrer sin egen rad');
select pg_temp.feil($$insert into public.hole_stats (round_id, member_id, hole_index, putts) values ('$$ || :'r3' || $$', '$$ || :'bjorn' || $$', 0, 2)$$, '42501');
select pg_temp.feil($$insert into public.hole_stats (round_id, member_id, hole_index, putts) values ('$$ || :'r3' || $$', '$$ || :'carl' || $$', 0, 2)$$, '42501');
select pg_temp.feil($$insert into public.hole_stats (round_id, member_id, hole_index, fairway) values ('$$ || :'r3' || $$', '$$ || :'anders' || $$', 2, 'left')$$, '22023');
select pg_temp.feil($$insert into public.hole_stats (round_id, member_id, hole_index, putts) values ('$$ || :'r3' || $$', '$$ || :'anders' || $$', 9, 2)$$, '22023');
select pg_temp.feil($$insert into public.hole_stats (round_id, member_id, hole_index, putts) values ('$$ || :'r3' || $$', '$$ || :'anders' || $$', 1, 12)$$, '23514');
select pg_temp.feil($$insert into public.hole_stats (round_id, member_id, hole_index, fairway) values ('$$ || :'r3' || $$', '$$ || :'anders' || $$', 1, 'bunker')$$, '23514');
select pg_temp.feil($$insert into public.hole_stats (round_id, member_id, hole_index) values ('$$ || :'r3' || $$', '$$ || :'anders' || $$', 1)$$, '23514');
insert into public.hole_stats (round_id, member_id, hole_index, green_in_regulation, putts, bunker, penalties)
values (:'r3', :'anders', 2, false, 3, true, 1) returning 'ok par 3 uten fairway går fint';
-- Låst runde: spilleren kan ikke lenger, slik som med slagene.
select pg_temp.feil($$insert into public.hole_stats (round_id, member_id, hole_index, putts) values ('$$ || :'r2' || $$', '$$ || :'anders' || $$', 0, 2)$$, '42501');
reset role;

select pg_temp.som(:'u3'); set role authenticated;
insert into public.hole_stats (round_id, member_id, hole_index, putts)
values (:'r3', :'bjorn', 0, 1), (:'r3', :'anders', 1, 2) returning 'ok Bjørn (markør) fører for seg selv og Anders i båsen';
select pg_temp.feil($$insert into public.hole_stats (round_id, member_id, hole_index, putts) values ('$$ || :'r3' || $$', '$$ || :'carl' || $$', 0, 2)$$, '42501');
select pg_temp.lik((select count(*) from public.hole_stats where round_id = :'r3'), 4::bigint, 'Bjørn ser alle radene i runden');
reset role;

select pg_temp.som(:'u1'); set role authenticated;
insert into public.hole_stats (round_id, member_id, hole_index, putts)
values (:'r3', :'carl', 0, 2), (:'r2', :'thomas', 0, 2) returning 'ok arrangøren fører for Carl, også i låst runde (som slagene)';
delete from public.hole_stats where round_id = :'r2' and member_id = :'thomas';
select pg_temp.lik((select count(*) from public.hole_stats where round_id = :'r2'), 0::bigint, 'arrangøren sletter');
reset role;

-- Par fra rundens egne hull vinner over banen.
select pg_temp.som('');
insert into public.round_holes (round_id, hole_index, par) values (:'r3', 4, 3);
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.feil($$insert into public.hole_stats (round_id, member_id, hole_index, fairway) values ('$$ || :'r3' || $$', '$$ || :'anders' || $$', 4, 'hit')$$, '22023');
reset role;

-- === B. Andre klubber, fremmede og anon =====================================
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.lik((select count(*) from public.hole_stats), 0::bigint, 'Ola (annen klubb) ser ingen rader');
select pg_temp.feil($$insert into public.hole_stats (round_id, member_id, hole_index, putts) values ('$$ || :'r3' || $$', '$$ || :'anders' || $$', 3, 2)$$, '42501');
update public.hole_stats set putts = 9 where round_id = :'r3';
delete from public.hole_stats where round_id = :'r3';
reset role;
select pg_temp.lik((select count(*) filter (where putts = 9) || '/' || count(*) from public.hole_stats where round_id = :'r3'),
                   '0/5', 'Ola kan verken endre eller slette');

select pg_temp.som('');
set role anon;
select pg_temp.feil($$select * from public.hole_stats$$, '42501');
select pg_temp.feil($$select public.can_write_hole_stats(gen_random_uuid(), gen_random_uuid())$$, '42501');
reset role;
set role authenticated;
select pg_temp.feil($$select public.hole_stats_before_write()$$, '42501');
select pg_temp.lik(public.can_write_hole_stats(:'r3', :'anders'), false, 'uten innlogging: ingen skriving');
reset role;

-- === C. Løs runde: eieren, deltakeren og gjesten ============================
select pg_temp.som(:'u1'); set role authenticated;
select (public.create_loose_round(:'losby', 18, 1, 'stableford', 'course',
        jsonb_build_array(jsonb_build_object('profile_id', :'u2'), jsonb_build_object('guest_name', 'Siri')))) ->> 'round_id' as lr \gset
select id as siri from public.round_participants where round_id = :'lr' and display_name = 'Siri' \gset
select id as anders_l from public.round_participants where round_id = :'lr' and profile_id = :'u2' \gset
select id as thomas_l from public.round_participants where round_id = :'lr' and profile_id = :'u1' \gset
insert into public.hole_stats (round_id, member_id, hole_index, fairway, green_in_regulation, putts)
values (:'lr', :'siri', 0, 'right', false, 2), (:'lr', :'thomas_l', 0, 'hit', true, 2)
returning 'ok eieren fører for seg selv og gjesten';
reset role;
select pg_temp.som(:'u2'); set role authenticated;
insert into public.hole_stats (round_id, member_id, hole_index, fairway, putts)
values (:'lr', :'anders_l', 0, 'left', 3) returning 'ok Anders fører for seg selv i den løse runden';
select pg_temp.feil($$insert into public.hole_stats (round_id, member_id, hole_index, putts) values ('$$ || :'lr' || $$', '$$ || :'siri' || $$', 1, 2)$$, '42501');
select pg_temp.lik((select count(*) from public.hole_stats where round_id = :'lr'), 3::bigint, 'Anders ser radene i runden han er med i');
reset role;
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik((select count(*) from public.hole_stats where round_id = :'lr'), 0::bigint, 'Bjørn (ikke med) ser ingenting fra den løse runden');
reset role;

-- === D. Opprydding følger runden og deltakeren ==============================
select pg_temp.som(:'u1'); set role authenticated;
delete from public.rounds where id = :'lr';
reset role;
select pg_temp.lik((select count(*) from public.hole_stats where round_id = :'lr'), 0::bigint, 'radene går med når runden slettes');
select pg_temp.som('');
delete from public.round_holes where round_id = :'r3' and hole_index = 4;
