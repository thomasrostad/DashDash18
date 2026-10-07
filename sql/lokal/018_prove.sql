\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Rolleprøve for 018_lose_runder.sql. Rekkefølge i en tom, lokal Postgres:
--   lokal/stub.sql, lokal/stub_storage.sql, 001–016, lokal/017_for.sql,
--   017_fundament.sql, 018_lose_runder.sql (gjerne to ganger), lokal/018_prove.sql.
-- Hver resultatlinje skal starte med "ok"; ingen "FEIL".
--
-- Folk: Golfgutu-verdenen fra 017_for (Thomas u1 arrangør, Anders u2, Bjørn u3
-- markør i r3), og tre fremmede som registrerer seg: Frida (u7), Gunnar (u8)
-- og Hege (u9).
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
\set anders  '11111111-0000-0000-0000-000000000002'
\set bjorn   '11111111-0000-0000-0000-000000000003'
\set u1 '00000000-0000-0000-0000-000000000001'
\set u2 '00000000-0000-0000-0000-000000000002'
\set u3 '00000000-0000-0000-0000-000000000003'
\set u7 '00000000-0000-0000-0000-000000000007'
\set u8 '00000000-0000-0000-0000-000000000008'
\set u9 '00000000-0000-0000-0000-000000000009'
\set bane    'cccccccc-0000-0000-0000-000000000001'
\set r3      'dddddddd-0000-0000-0000-000000000003'

-- === A. Koden: form, tilfeldighet og normalisering ===========================
select pg_temp.som('');
select pg_temp.lik((select bool_and(public.round_invite_code() ~ '^[0-9A-HJKMNP-TV-Z]{10}$') from generate_series(1, 500)), true,
                   '500 koder har riktig form (10 tegn Crockford base32)');
select pg_temp.lik((select count(distinct public.round_invite_code()) from generate_series(1, 2000)), 2000::bigint,
                   '2000 koder er alle forskjellige');
select pg_temp.lik(public.round_invite_normalize(' abcde-fghil o '), 'ABCDEFGH110', 'normalisering: mellomrom, bindestrek, små bokstaver, I/L → 1, O → 0');
select pg_temp.lik(public.round_invite_normalize('   '), null::text, 'tom kode blir null');

-- === B. Tre fremmede registrerer seg ==========================================
insert into auth.users values (:'u7'), (:'u8'), (:'u9');
select pg_temp.som(:'u7'); set role authenticated;
update public.profiles set display_name = 'Frida', handicap_index = 22 where id = :'u7';
reset role;
select pg_temp.som(:'u8'); set role authenticated;
update public.profiles set display_name = 'Gunnar', handicap_index = 8.5 where id = :'u8';
reset role;
select pg_temp.som(:'u9'); set role authenticated;
update public.profiles set display_name = 'Hege' where id = :'u9';
reset role;

-- === C. Felles bibliotek: save_library_course ================================
select pg_temp.som(:'u7'); set role authenticated;
select public.save_library_course(null, '  Losby  ', 'course', 71.2, 128::smallint,
         (select jsonb_agg(jsonb_build_object('hole_number', h, 'par', case when h % 6 = 0 then 3 else 4 end,
                                              'stroke_index', h, 'length_m', 300 + h))
          from generate_series(1, 18) h)) as losby \gset
select pg_temp.lik((select name || '/' || kind || '/' || coalesce(club_id::text, '-') || '/' || created_by_profile
                    from public.courses where id = :'losby'), 'Losby/course/-/' || :'u7',
                   'Frida legger inn Losby i det felles biblioteket (navnet trimmes, hun står som den som la inn)');
select pg_temp.lik((select count(*) || '/' || sum(par) from public.course_holes where course_id = :'losby'), '18/69',
                   'alle 18 hullene kom med i samme kall');
select pg_temp.feil($$select public.save_library_course(null, 'Halv', 'course', null, null,
  (select jsonb_agg(jsonb_build_object('hole_number', h, 'par', 4)) from generate_series(1, 8) h))$$, '22023');
select pg_temp.lik(public.save_library_course(:'losby', 'Losby Golfklubb', 'course', 71.2, 128::smallint,
         (select jsonb_agg(jsonb_build_object('hole_number', h, 'par', 4, 'stroke_index', h)) from generate_series(1, 9) h))::text,
                   :'losby', 'Frida retter sin egen bane (ny navn, 9 hull)');
select pg_temp.lik((select count(*) from public.course_holes where course_id = :'losby'), 9::bigint,
                   'hullene som ikke står i lista, er slettet');
select public.save_library_course(:'losby', 'Losby', 'course', 71.2, 128::smallint,
         (select jsonb_agg(jsonb_build_object('hole_number', h, 'par', case when h % 6 = 0 then 3 else 4 end,
                                              'stroke_index', h, 'length_m', 300 + h))
          from generate_series(1, 18) h)) is not null as tilbake \gset
reset role;
select pg_temp.som(:'u8'); set role authenticated;
select pg_temp.feil($$select public.save_library_course('$$ || :'losby' || $$', 'Gunnars', 'course', null, null,
  (select jsonb_agg(jsonb_build_object('hole_number', h, 'par', 3)) from generate_series(1, 9) h))$$, '42501');
select pg_temp.feil($$select public.save_library_course('$$ || :'bane' || $$', 'Kapret', 'course', null, null,
  (select jsonb_agg(jsonb_build_object('hole_number', h, 'par', 3)) from generate_series(1, 9) h))$$, '42501');
reset role;
select pg_temp.lik((select name || '/' || (select sum(par) from public.course_holes where course_id = :'losby')
                    from public.courses where id = :'losby'), 'Losby/69', 'Gunnar kan ikke endre Fridas bane');
select pg_temp.lik((select name from public.courses where id = :'bane'), 'Marco Simone', 'heller ikke klubbens bane');

-- === D. start_loose_round: alt oppsett i ett kall =============================
select pg_temp.som(:'u7'); set role authenticated;
select pg_temp.feil($$select public.start_loose_round('$$ || jsonb_build_object(
  'course_id', :'losby', 'players', jsonb_build_array(jsonb_build_object('guest_name', 'Per'),
                                                     jsonb_build_object('profile_id', :'u1')))::text || $$')$$, '42501');
select pg_temp.feil($$select public.start_loose_round('$$ || jsonb_build_object(
  'course_id', :'losby', 'me', jsonb_build_object('bay_no', 1, 'is_marker', true),
  'players', jsonb_build_array(jsonb_build_object('guest_name', 'Per', 'bay_no', 1, 'is_marker', true)))::text || $$')$$, '23505');
select pg_temp.feil($$select public.start_loose_round('$$ || jsonb_build_object(
  'course_id', :'bane', 'players', '[]'::jsonb)::text || $$')$$, '22023');
select pg_temp.feil($$select public.start_loose_round('$$ || jsonb_build_object(
  'course_id', :'losby', 'players', jsonb_build_array(jsonb_build_object('guest_name', '  ')))::text || $$')$$, '22023');
select pg_temp.feil($$select public.start_loose_round('$$ || jsonb_build_object(
  'course_id', :'losby', 'players', jsonb_build_array(jsonb_build_object('guest_name', 'Per')),
  'matches', jsonb_build_array(jsonb_build_object('a', 0, 'b', 5)))::text || $$')$$, '23514');
select pg_temp.lik((select count(*) from public.rounds where club_id is null), 0::bigint, 'avviste oppsett rulles helt tilbake');

select public.start_loose_round(jsonb_build_object(
  'course_id', :'losby', 'hole_count', 18, 'first_hole', 1, 'format', 'match', 'venue', 'course',
  'handicap_allowance', 1.0, 'external_handicap', false,
  'ld_enabled', false, 'kp_enabled', true, 'kp_hole_index', 5,
  'me', jsonb_build_object('bay_no', 1, 'is_marker', true),
  'players', jsonb_build_array(
     jsonb_build_object('guest_name', 'Per', 'handicap_index', 12.4, 'bay_no', 1),
     jsonb_build_object('guest_name', 'Kari', 'bay_no', 1)),
  'matches', jsonb_build_array(jsonb_build_object('a', 0, 'b', 1)))) as svar \gset
select (:'svar'::jsonb) ->> 'round_id' as fr \gset
select (:'svar'::jsonb) -> 'participants' -> 0 ->> 'id' as frida_p \gset
select (:'svar'::jsonb) -> 'participants' -> 1 ->> 'id' as per \gset
select (:'svar'::jsonb) -> 'participants' -> 2 ->> 'id' as kari \gset
select pg_temp.lik((select string_agg(e ->> 'display_name', ',' order by o) from jsonb_array_elements((:'svar'::jsonb) -> 'participants')
                    with ordinality as x(e, o)), 'Frida,Per,Kari', 'svaret har deltakerne i lista sin rekkefølge, Frida først');
select pg_temp.lik((select status || '/' || format || '/' || venue || '/' || handicap_allowance || '/' || ld_enabled || '/' || kp_enabled
                           || '/' || kp_hole_index || '/' || (par_confirmed_at is not null) || '/' || coalesce(par_confirmed_by::text, '-')
                           || '/' || owner_id
                    from public.rounds where id = :'fr'),
                   'active/match/course/1.000/false/true/5/true/-/' || :'u7',
                   'runden er startet med form, sted, andel, sidepremier og bekreftet par, og Frida eier');
select pg_temp.lik((select string_agg(coalesce(bay_no::text, '-') || ':' || is_marker || ':' || coalesce(handicap_index::text, '-'), ','
                                      order by array_position(array[:'frida_p', :'per', :'kari']::uuid[], member_id))
                    from public.round_players where round_id = :'fr'),
                   '1:true:22.0,1:false:12.4,1:false:-', 'alle i flight 1, Frida markør, handicapet frosset');
select pg_temp.lik((select player_a::text || '/' || player_b::text || '/' || coalesce(player_c::text, '-') from public.round_matches where round_id = :'fr'),
                   :'frida_p' || '/' || :'per' || '/-', 'matchen peker på Frida og Per (indeks 0 og 1)');

-- Koden.
select public.loose_round_invite(:'fr') ->> 'code' as kode \gset
select pg_temp.lik(:'kode' ~ '^[0-9A-HJKMNP-TV-Z]{10}$', true, 'Frida får en kode');
select pg_temp.lik(public.loose_round_invite(:'fr') ->> 'code', :'kode', 'samme kode neste gang');
select pg_temp.lik((select count(*) from public.round_invites), 1::bigint, 'Frida ser koden til runden sin');
select pg_temp.feil($$insert into public.round_invites (round_id, code, expires_at) values ('$$ || :'fr' || $$', 'AAAAAAAAAA', now())$$, '42501');
select pg_temp.feil($$update public.round_invites set expires_at = now() + interval '1 year'$$, '42501');
select pg_temp.feil($$select public.loose_round_invite('$$ || :'r3' || $$')$$, 'P0002');
reset role;

-- === E. Gunnar har koden og tar plassen til Per («Er du Per?») ===============
select pg_temp.som(:'u8'); set role authenticated;
select pg_temp.lik((select count(*) from public.rounds where id = :'fr'), 0::bigint, 'Gunnar ser ikke runden før han er med');
select pg_temp.lik((select count(*) from public.round_invites), 0::bigint, 'Gunnar ser ingen koder');
select pg_temp.feil($$select public.loose_round_invite('$$ || :'fr' || $$')$$, 'P0002');
select pg_temp.feil($$select public.round_invite_preview('ZZZZZZZZZZ')$$, 'P0002');
select pg_temp.lik((select (p ->> 'course_name') || '/' || (p ->> 'owner_name') || '/' || (p ->> 'status') || '/'
                           || coalesce(p ->> 'my_participant_id', '-') || '/' ||
                           (select string_agg((e ->> 'display_name') || ':' || (e ->> 'is_guest'), ',' order by o)
                            from jsonb_array_elements(p -> 'players') with ordinality x(e, o))
                    from public.round_invite_preview(lower(substr(:'kode', 1, 5)) || '-' || substr(:'kode', 6)) p),
                   'Losby/Frida/active/-/Frida:false,Kari:true,Per:true',
                   'forhåndsvisningen (kode med små bokstaver og bindestrek): bane, eier først, så gjesteplassene');
select pg_temp.lik(public.claim_round_invite(:'kode', :'per') ->> 'joined', 'guest', 'Gunnar tar plassen til Per');
select pg_temp.lik(public.claim_round_invite(:'kode', :'kari') ->> 'joined', 'already', 'han er med fra før: ingenting skjer');
select pg_temp.lik((select count(*) from public.rounds where id = :'fr'), 1::bigint, 'nå ser Gunnar runden');
select pg_temp.lik((select display_name || ':' || is_guest from public.round_roster where round_id = :'fr' and player_id = :'per'),
                   'Gunnar:false', 'plassen heter Gunnar og er ikke en gjest lenger');
select pg_temp.lik((select handicap_index from public.round_players where round_id = :'fr' and member_id = :'per'), 12.4,
                   'handicapet som ble frosset for plassen, står');
select pg_temp.lik((select count(*) from public.profiles where id = :'u7'), 1::bigint, 'Gunnar ser Fridas profil nå');
select pg_temp.lik((select count(*) from public.round_invites), 1::bigint, 'og koden, så han kan dele den videre');
reset role;

-- === F. Hege prøver samme plass, så blir hun med som ny =======================
select pg_temp.som(:'u9'); set role authenticated;
select pg_temp.feil($$select public.claim_round_invite('$$ || :'kode' || $$', '$$ || :'per' || $$')$$, '55000');
select pg_temp.feil($$select public.claim_round_invite('$$ || :'kode' || $$', '$$ || :'r3' || $$')$$, 'P0002');
select pg_temp.lik(public.claim_round_invite(:'kode') ->> 'joined', 'new', 'Hege blir med som ny deltaker');
select id as hege from public.round_participants where round_id = :'fr' and profile_id = :'u9' \gset
select pg_temp.lik((select coalesce(bay_no::text, '-') || ':' || is_marker from public.round_players where round_id = :'fr' and member_id = :'hege'),
                   '2:false', 'Hege får en egen flight (fører selv)');
select pg_temp.lik(public.claim_round_invite(:'kode') ->> 'joined', 'already', 'Hege to ganger: ingenting skjer');

-- === G. Hvem fører for hvem ===================================================
select pg_temp.lik(jsonb_array_length(public.save_hole(:'fr', 0, jsonb_build_array(jsonb_build_object('member_id', :'hege', 'strokes', 5)))), 1,
                   'Hege fører sitt eget kort');
select pg_temp.feil($$select public.save_hole('$$ || :'fr' || $$', 0, '[{"member_id": "$$ || :'kari' || $$", "strokes": 4}]')$$, '42501');
select pg_temp.lik((public.confirm_round_par(:'fr')) is not null, true, 'Hege (egen flight, ingen markør) kan bekrefte parene');
reset role;
select pg_temp.som(:'u8'); set role authenticated;
select pg_temp.feil($$select public.save_hole('$$ || :'fr' || $$', 0, '[{"member_id": "$$ || :'per' || $$", "strokes": 4}]')$$, '42501');
select pg_temp.feil($$select public.confirm_round_par('$$ || :'fr' || $$')$$, '42501');
select pg_temp.feil($$select public.finish_loose_round('$$ || :'fr' || $$')$$, '42501');
reset role;
select pg_temp.som(:'u7'); set role authenticated;
select pg_temp.lik(jsonb_array_length(public.save_hole(:'fr', 0, jsonb_build_array(
                     jsonb_build_object('member_id', :'frida_p', 'strokes', 4),
                     jsonb_build_object('member_id', :'per', 'strokes', 5),
                     jsonb_build_object('member_id', :'kari', 'strokes', 6)))), 3,
                   'Frida (markør i flight 1) fører for seg selv, Gunnar og gjesten Kari');
select pg_temp.lik(jsonb_array_length(public.save_hole(:'fr', 1, jsonb_build_array(jsonb_build_object('member_id', :'hege', 'strokes', 4)))), 1,
                   'Frida (eier) kan rette Heges kort');
reset role;

-- === H. Par-bekreftelsen: løs kladd og klubbrunder som før ====================
select pg_temp.som(:'u7'); set role authenticated;
select (public.start_loose_round(jsonb_build_object('course_id', :'losby', 'start', false))) ->> 'round_id' as kladd \gset
select pg_temp.lik((select status || '/' || (par_confirmed_at is null) from public.rounds where id = :'kladd'), 'draft/true',
                   'start = false: kladd, parene ikke bekreftet');
select pg_temp.lik((public.confirm_round_par(:'kladd')) is not null, true, 'eieren bekrefter parene i kladden');
select pg_temp.lik((select par_confirmed_by from public.rounds where id = :'kladd'), null::uuid,
                   'par_confirmed_by står tom i en løs runde (den peker på klubbmedlemmer)');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.feil($$select public.confirm_round_par('$$ || :'r3' || $$')$$, '42501');
reset role;
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik((public.confirm_round_par(:'r3')) is not null, true, 'Bjørn (markør i r3) bekrefter parene som før');
reset role;
select pg_temp.som('');
select pg_temp.lik((select par_confirmed_by from public.rounds where id = :'r3'), :'bjorn'::uuid,
                   'klubbrunden: par_confirmed_by er Bjørns medlems-id, som før');

-- === I. Frida avslutter runden ================================================
select pg_temp.som(:'u7'); set role authenticated;
select public.finish_loose_round(:'fr') as laast \gset
select pg_temp.lik((select status from public.rounds where id = :'fr'), 'locked', 'runden er låst');
select pg_temp.lik(public.finish_loose_round(:'fr')::text, :'laast', 'avslutt to ganger: samme tidspunkt');
select pg_temp.lik((select count(*) from public.round_invites where round_id = :'fr'), 0::bigint, 'koden er slettet');
select pg_temp.feil($$select public.loose_round_invite('$$ || :'fr' || $$')$$, '55000');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil($$select public.claim_round_invite('$$ || :'kode' || $$')$$, 'P0002');
select pg_temp.feil($$select public.round_invite_preview('$$ || :'kode' || $$')$$, 'P0002');
select pg_temp.feil($$select public.finish_loose_round('$$ || :'r3' || $$')$$, 'P0002');
reset role;

-- En kode som har gått ut, virker ikke, og en ny lages.
select pg_temp.som(:'u7'); set role authenticated;
select (public.start_loose_round(jsonb_build_object('course_id', :'losby'))) ->> 'round_id' as fr2 \gset
select public.loose_round_invite(:'fr2') ->> 'code' as kode2 \gset
reset role;
select pg_temp.som('');
update public.round_invites set expires_at = now() - interval '1 minute' where round_id = :'fr2';
select pg_temp.som(:'u9'); set role authenticated;
select pg_temp.feil($$select public.round_invite_preview('$$ || :'kode2' || $$')$$, 'P0002');
select pg_temp.feil($$select public.claim_round_invite('$$ || :'kode2' || $$')$$, 'P0002');
reset role;
select pg_temp.som(:'u7'); set role authenticated;
select pg_temp.lik((public.loose_round_invite(:'fr2') ->> 'code') <> :'kode2', true, 'utgått kode: Frida får en ny');
reset role;

-- === J. Uinnlogget (anon) og uten auth.uid() ==================================
select pg_temp.som('');
set role anon;
select pg_temp.feil($$select * from public.round_invites$$, '42501');
select pg_temp.feil($$select public.loose_round_invite(gen_random_uuid())$$, '42501');
select pg_temp.feil($$select public.round_invite_preview('X')$$, '42501');
select pg_temp.feil($$select public.claim_round_invite('X')$$, '42501');
select pg_temp.feil($$select public.start_loose_round('{}')$$, '42501');
select pg_temp.feil($$select public.finish_loose_round(gen_random_uuid())$$, '42501');
select pg_temp.feil($$select public.save_library_course(null, 'x', 'course', null, null, '[]')$$, '42501');
select pg_temp.feil($$select public.round_invite_code()$$, '42501');
reset role;
set role authenticated;
select pg_temp.feil($$select public.round_invite_code()$$, '42501');
select pg_temp.feil($$select public.round_invite_normalize('x')$$, '42501');
select pg_temp.feil($$select public.claim_round_invite('X')$$, '42501');
select pg_temp.feil($$select public.start_loose_round('{}')$$, '42501');
reset role;
