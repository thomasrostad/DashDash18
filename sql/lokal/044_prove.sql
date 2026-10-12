\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Prøve for 044_roller.sql. Kjøres etter lokal/044_for.sql og 044 (to ganger).
-- Alt rulles tilbake. Hver linje skal starte med "ok"; ingen "FEIL".
--
-- A: paritet. De samme prøvene som i 044_for (hjelpere, RPC-er og policyer, for hver
--    innlogging og uten innlogging) gir samme svar som før 044. Unntaket er
--    kassereren uten arrangør (Anders, u2), som får rettigheten money: der skal bare
--    prøver merket money, any eller read være ulike, og de listes.
-- B: malene og tildelingene fra flaggene, og flaggene er uendret.
-- C: RPC-ene: eier lager og endrer roller, andre får 42501; members-rettigheten gir
--    bare roller med egne rettigheter; bare eier gir Eier; siste eier kan ikke miste
--    rollen, arkiveres eller kobles fra; overføring; sletting av roller; konto-
--    sletting gir Eier videre; create_club gir maler, Eier og Arrangør.
-- D: en egen rolle med bare rounds kan starte og låse en runde og rette score, men
--    ikke lage turnering eller godkjenne medlemmer. Kasserer (money) kan avgjøre
--    veddemål og rapporter, men ikke starte en runde.
-- E: gamle bygg: is_organizer/is_treasurer via update gir og tar rollene.
-- F: kontrollen etterpå: flaggene er lik rollene, malene er der én gang.
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
create function pg_temp.som(p_uid text) returns text language sql as $$
  select 'som ' || coalesce(nullif(set_config('request.jwt.claim.sub', p_uid, false), ''), 'ingen');
$$;
grant execute on all functions in schema pg_temp to public;

\set u1  '00000000-0000-0000-0000-000000000001'
\set u2  '00000000-0000-0000-0000-000000000002'
\set u3  '00000000-0000-0000-0000-000000000003'
\set u4  '00000000-0000-0000-0000-000000000004'
\set u5  '00000000-0000-0000-0000-000000000005'
\set u7  '00000000-0000-0000-0000-000000000007'
\set G   'aaaaaaaa-0000-0000-0000-000000000001'
\set A   'aaaaaaaa-0000-0000-0000-000000000002'
\set S   'aaaaaaaa-0000-0000-0000-000000000003'
\set T   'aaaaaaaa-0000-0000-0000-000000000004'
\set m1  '11111111-0000-0000-0000-000000000001'
\set m2  '11111111-0000-0000-0000-000000000002'
\set m3  '11111111-0000-0000-0000-000000000003'
\set m5  '11111111-0000-0000-0000-000000000005'
\set m9  '11111111-0000-0000-0000-000000000009'
\set ola '22222222-0000-0000-0000-000000000004'
\set per '22222222-0000-0000-0000-0000000000a1'
\set liga 'bd7acc4c-f21f-4b49-bc06-d84d915c2579'
\set r3  'dddddddd-0000-0000-0000-000000000003'
\set bet 'b0000000-0000-0000-0000-0000000044b1'
\set rep '7e000000-0000-0000-0000-0000000044a1'

select id as g_eier from public.club_roles where club_id = :'G' and template_key = 'owner' \gset
select id as g_arr  from public.club_roles where club_id = :'G' and template_key = 'organizer' \gset
select id as g_kas  from public.club_roles where club_id = :'G' and template_key = 'treasurer' \gset
select id as g_sos  from public.club_roles where club_id = :'G' and template_key = 'committee' \gset

begin;

-- --- A: paritet ------------------------------------------------------------------
create table lokal44.etter_svar (uid text, probe integer, svar text, primary key (uid, probe));
grant select, insert on lokal44.etter_svar to authenticated;
create function lokal44.ta_etter(p_uid text) returns integer language plpgsql as $$
declare n integer;
begin
  insert into lokal44.etter_svar (uid, probe, svar)
  select p_uid, p.id, lokal44.prov(p.sql) from lokal44.prober p order by p.id;
  get diagnostics n = row_count;
  return n;
end $$;
grant execute on function lokal44.ta_etter(text) to authenticated;

select pg_temp.som('');    set role authenticated; select lokal44.ta_etter('ingen') > 0; reset role;
select pg_temp.som(:'u1'); set role authenticated; select lokal44.ta_etter('u1') > 0; reset role;
select pg_temp.som(:'u2'); set role authenticated; select lokal44.ta_etter('u2') > 0; reset role;
select pg_temp.som(:'u3'); set role authenticated; select lokal44.ta_etter('u3') > 0; reset role;
select pg_temp.som(:'u4'); set role authenticated; select lokal44.ta_etter('u4') > 0; reset role;
select pg_temp.som(:'u5'); set role authenticated; select lokal44.ta_etter('u5') > 0; reset role;
select pg_temp.som(:'u7'); set role authenticated; select lokal44.ta_etter('u7') > 0; reset role;
select pg_temp.som('');

select case when count(*) filter (where f.svar is distinct from e.svar) = 0
            then 'ok A1 ' || f.uid || ': ' || count(*) || ' av ' || count(*) || ' prøver gir samme svar som før 044'
            else 'FEIL A1 ' || f.uid || ': ' || count(*) filter (where f.svar is distinct from e.svar) || ' ulike av ' || count(*) end
  from lokal44.for_svar f join lokal44.etter_svar e using (uid, probe)
 where f.uid <> 'u2'
 group by f.uid order by f.uid;
select pg_temp.lik((select count(*)::int from lokal44.etter_svar), (select count(*)::int from lokal44.for_svar),
                   'A2 like mange svar før og etter');
-- Kassereren: bare money, any og read kan endre seg.
select case when p.tag in ('money', 'any', 'read')
            then 'ok A3 kasserer (ventet, ' || p.tag || ') ' || p.hva || ': ' || f.svar || ' -> ' || e.svar
            when f.svar like 'err:%' and e.svar like 'err:%'
            then 'ok A3 kasserer (fortsatt nektet, ny lesing) ' || p.hva || ': ' || f.svar || ' -> ' || e.svar
            else 'FEIL A3 kasserer (' || p.tag || ') ' || p.hva || ': ' || f.svar || ' -> ' || e.svar end
  from lokal44.for_svar f join lokal44.etter_svar e using (uid, probe) join lokal44.prober p on p.id = f.probe
 where f.uid = 'u2' and f.svar is distinct from e.svar
 order by p.id;
select pg_temp.lik((select count(*)::int from lokal44.for_svar f join lokal44.etter_svar e using (uid, probe)
                    join lokal44.prober p on p.id = f.probe
                    where f.uid = 'u2' and p.tag not in ('money', 'any', 'read') and f.svar is distinct from e.svar
                      and not (f.svar like 'err:%' and e.svar like 'err:%')), 0,
                   'A4 kassereren: ingen ny tillatelse utenfor money, any og read');
select pg_temp.lik((select e.svar from lokal44.etter_svar e join lokal44.prober p on p.id = e.probe
                    where e.uid = 'u2' and p.hva = 'resolve_report ' || :'rep'), 'ok:dismissed',
                   'A5 kassereren kan avgjøre rapporten nå');

-- --- B: malene og tildelingene ------------------------------------------------------
select pg_temp.lik((select count(*)::int from public.club_roles where template_key is not null), 16, 'B1 fire maler i hver av de fire klubbene');
select pg_temp.lik((select string_agg(m.display_name || ':' || r.template_key, ' ' order by m.display_name, r.sort_order)
                      from public.club_member_roles mr join public.club_members m on m.id = mr.member_id
                      join public.club_roles r on r.id = mr.role_id where mr.club_id = :'G'),
                   'Anders:treasurer Bjørn:organizer Thomas:owner Thomas:organizer', 'B2 Golfgutu: Thomas eier, Bjørn arrangør, Anders kasserer');
select pg_temp.lik((select string_agg(m.display_name || ':' || r.template_key, ' ' order by m.display_name, r.sort_order)
                      from public.club_member_roles mr join public.club_members m on m.id = mr.member_id
                      join public.club_roles r on r.id = mr.role_id where mr.club_id = :'A'),
                   'Gamle Per:organizer Ola:owner Ola:organizer', 'B3 Andre: Eier til Ola (med innlogging), ikke eldre Gamle Per uten');
select pg_temp.lik((select count(*)::int from public.club_member_roles where club_id = :'T'), 0, 'B4 Tom klubb: ingen roller, ingen eier');
select pg_temp.lik((select string_agg(display_name || ':' || is_organizer || '/' || is_treasurer, ' ' order by club_id, display_name)
                      from public.club_members),
                   'Anders:false/true Bjørn:true/false Carl:false/false Dag:false/false Thomas:true/false Gamle Per:true/false Ola:true/false Siv:true/false Dag:false/false',
                   'B5 flaggene er som før');
select pg_temp.som(:'u7'); set role authenticated;
select pg_temp.lik((select count(*)::int from public.club_roles where club_id = :'G'), 0, 'B6 andre klubber ser ikke rollene');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik((select count(*)::int from public.club_roles where club_id = :'G'), 4, 'B7 medlemmet ser klubbens roller');
select pg_temp.lik((select count(*)::int from public.club_member_roles where club_id = :'G'), 4, 'B8 medlemmet ser tildelingene');
select pg_temp.feil($$insert into public.club_member_roles (club_id, member_id, role_id)
                      select club_id, '11111111-0000-0000-0000-000000000002', id from public.club_roles
                       where club_id = 'aaaaaaaa-0000-0000-0000-000000000001' and is_owner$$, '42501');
select pg_temp.lik((select count(*)::int from (select private.has_club_right(:'G', 'money') where true) x), 1, 'B9 authenticated kan kalle has_club_right');
reset role;
select pg_temp.lik(has_function_privilege('anon', 'private.has_club_right(uuid, text)', 'execute'), false, 'B10 anon kan ikke kalle has_club_right');

-- --- C: RPC-ene -------------------------------------------------------------------------
select pg_temp.som(:'u1'); set role authenticated;
create temp table c_rolle as select (public.club_role_save(:'G', null, 'Rundeleder', array['rounds'])).id;
select pg_temp.lik((select rights from public.club_roles where id = (select id from c_rolle)), array['rounds'], 'C1 eieren lager rollen Rundeleder (rounds)');
select pg_temp.lik((public.club_role_save(:'G', (select id from c_rolle), ' Runder ', null)).name, 'Runder', 'C2 eieren gir den nytt navn');
select pg_temp.feil($$select public.club_role_save('aaaaaaaa-0000-0000-0000-000000000001', null, 'kasserer', '{}')$$, '23505');
select pg_temp.feil(format($$select public.club_role_save('aaaaaaaa-0000-0000-0000-000000000001', %L, 'Eier', array['money'])$$, :'g_eier'), '22023');
select pg_temp.lik((public.club_role_save(:'G', :'g_eier', 'Sjef', array['money', 'rounds', 'tournaments', 'members'])).name, 'Sjef', 'C3 eierrollen kan få nytt navn');
select pg_temp.feil($$select public.club_role_save('aaaaaaaa-0000-0000-0000-000000000001', null, 'Rar', array['alt'])$$, '22023');
select pg_temp.feil($$select public.club_role_save('aaaaaaaa-0000-0000-0000-000000000001', null, '  ', '{}')$$, '22023');
create temp table c_medl as select (public.club_role_save(:'G', null, 'Medlemsansvar', array['members'])).id;
reset role;
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.feil($$select public.club_role_save('aaaaaaaa-0000-0000-0000-000000000001', null, 'Bjørns rolle', '{}')$$, '42501');
-- Bjørn (Arrangør: alle fire) gir Arrangør til Anders.
select pg_temp.lik(cardinality(public.club_member_set_roles(:'m2', array[:'g_kas', :'g_arr']::uuid[])), 2, 'C4 arrangør (alle rettigheter) gir Arrangør');
select pg_temp.lik((select is_organizer from public.club_members where id = :'m2'), true, 'C5 flagget følger (is_organizer)');
select pg_temp.feil(format($$select public.club_member_set_roles('11111111-0000-0000-0000-000000000003', array[%L, %L]::uuid[])$$, :'g_arr', :'g_eier'), '42501');
select pg_temp.feil(format($$select public.club_member_set_roles('11111111-0000-0000-0000-000000000001', array[%L]::uuid[])$$, :'g_arr'), '42501');
-- Tilbake: Anders bare kasserer.
select pg_temp.lik(cardinality(public.club_member_set_roles(:'m2', array[:'g_kas']::uuid[])), 1, 'C6 arrangør tar Arrangør igjen');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik(cardinality(public.club_member_set_roles(:'m2', array[:'g_kas', (select id from c_medl)]::uuid[])), 2, 'C7 eieren gir Anders Medlemsansvar');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
-- Anders har members og money: Arrangør (alle fire) kan han ikke gi.
select pg_temp.feil(format($$select public.club_member_set_roles('11111111-0000-0000-0000-000000000009', array[%L]::uuid[])$$, :'g_arr'), '42501');
select pg_temp.feil(format($$select public.club_member_set_roles('11111111-0000-0000-0000-000000000003', array[]::uuid[])$$), '42501');
select pg_temp.lik(cardinality(public.club_member_set_roles(:'m9', array[:'g_kas']::uuid[])), 1, 'C8 members+money gir Kasserer (egne rettigheter)');
select pg_temp.lik(cardinality(public.club_member_set_roles(:'m9', array[]::uuid[])), 0, 'C9 … og tar den igjen');
select pg_temp.feil($$select public.club_role_save('aaaaaaaa-0000-0000-0000-000000000001', null, 'Min', '{}')$$, '42501');
reset role;
select pg_temp.som(:'u7'); set role authenticated;
select pg_temp.feil(format($$select public.club_member_set_roles('11111111-0000-0000-0000-000000000009', array[%L]::uuid[])$$, :'g_kas'), 'P0002');
reset role;
-- Siste eier.
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil(format($$select public.club_member_set_roles('11111111-0000-0000-0000-000000000001', array[%L]::uuid[])$$, :'g_arr'), '42501');
select pg_temp.feil($$update public.club_members set user_id = null where id = '11111111-0000-0000-0000-000000000001'$$, '42501');
reset role;
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.feil($$update public.club_members set status = 'archived' where id = '11111111-0000-0000-0000-000000000001'$$, '42501');
select pg_temp.feil($$update public.club_members set is_organizer = false where id = '11111111-0000-0000-0000-000000000001'$$, '42501');
select pg_temp.feil($$select public.club_transfer_ownership('aaaaaaaa-0000-0000-0000-000000000001', '11111111-0000-0000-0000-000000000003')$$, '42501');
reset role;
-- Overføring.
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil($$select public.club_transfer_ownership('aaaaaaaa-0000-0000-0000-000000000001', '11111111-0000-0000-0000-000000000005')$$, '22023');
select pg_temp.feil($$select public.club_transfer_ownership('aaaaaaaa-0000-0000-0000-000000000001', '11111111-0000-0000-0000-000000000009')$$, '22023');
select pg_temp.feil($$select public.club_transfer_ownership('aaaaaaaa-0000-0000-0000-000000000001', '11111111-0000-0000-0000-000000000001')$$, '22023');
select pg_temp.feil($$select public.club_transfer_ownership('aaaaaaaa-0000-0000-0000-000000000001', '22222222-0000-0000-0000-000000000004')$$, 'P0002');
select 'ok C9b eieren gir eierskapet til Bjørn' from (select public.club_transfer_ownership(:'G', :'m3')) x;
select pg_temp.lik(private.is_club_owner(:'G'), false, 'C10 Thomas er ikke eier etter overføringen');
select pg_temp.lik(private.has_club_right(:'G', 'members'), true, 'C11 … men har Arrangør');
select pg_temp.feil($$select public.club_role_save('aaaaaaaa-0000-0000-0000-000000000001', null, 'Etterpå', '{}')$$, '42501');
reset role;
select pg_temp.lik((select string_agg(m.display_name, ',') from public.club_member_roles mr join public.club_members m on m.id = mr.member_id
                     where mr.role_id = :'g_eier'), 'Bjørn', 'C12 Bjørn er eier');
-- Nå kan Thomas arkiveres av Bjørn (ikke siste eier) – prøves og rulles tilbake.
select pg_temp.som(:'u3'); set role authenticated;
savepoint c_ark;
update public.club_members set status = 'archived' where id = :'m1';
select pg_temp.lik((select status from public.club_members where id = :'m1'), 'archived', 'C13 en arrangør som ikke er siste eier kan arkiveres');
select pg_temp.lik((select count(*)::int from public.club_member_roles where member_id = :'m1'), 0, 'C13c den arkiverte mister rollene');
rollback to savepoint c_ark;
-- Slette roller.
select pg_temp.feil(format($$select public.club_role_delete(%L)$$, :'g_eier'), '22023');
select pg_temp.feil(format($$select public.club_role_delete(%L)$$, :'g_kas'), '22023');
select 'ok C13b eieren sletter Runder' from (select public.club_role_delete((select id from c_rolle))) x;
select pg_temp.lik((select count(*)::int from public.club_roles where id = (select id from c_rolle)), 0, 'C14 eieren sletter en rolle ingen har');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil(format($$select public.club_role_delete(%L)$$, :'g_sos'), '42501');
reset role;
-- Konto slettes: Bjørn er siste eier, Thomas (eldste arrangør) overtar.
select pg_temp.som('');
savepoint c_konto;
select pg_temp.lik((public.delete_account_data(:'u3') ->> 'owners_promoted')::int, 1, 'C15 delete_account_data gir Eier videre');
select pg_temp.lik((select string_agg(m.display_name, ',') from public.club_member_roles mr join public.club_members m on m.id = mr.member_id
                     where mr.role_id = :'g_eier'), 'Thomas', 'C16 Thomas er eier igjen');
select pg_temp.lik((select count(*)::int from public.club_member_roles where member_id = :'m3'), 0, 'C17 den slettede har ingen roller');
select pg_temp.lik((select is_organizer from public.club_members where id = :'m3'), false, 'C18 og ikke arrangørflagget');
rollback to savepoint c_konto;
-- create_club.
select pg_temp.som(:'u5'); set role authenticated;
create temp table c_klubb as select public.create_club('Dags klubb', 'Dag') as id;
reset role;
select pg_temp.lik((select string_agg(r.template_key, ',' order by r.sort_order) from public.club_member_roles mr
                      join public.club_roles r on r.id = mr.role_id where mr.club_id = (select id from c_klubb)),
                   'owner,organizer', 'C19 create_club: Dag er Eier og Arrangør');
select pg_temp.lik((select count(*)::int from public.club_roles where club_id = (select id from c_klubb)), 4, 'C20 create_club: fire maler');
select pg_temp.lik((select is_organizer from public.club_members where club_id = (select id from c_klubb)), true, 'C21 create_club: is_organizer');
select pg_temp.som(:'u5'); set role authenticated;
select pg_temp.lik((select count(*)::int from public.clubs where id = (select id from c_klubb) and org_number is null), 1, 'C22 org_number er tom');
select pg_temp.feil($$update public.clubs set org_number = '12345' where name = 'Dags klubb'$$, '23514');
update public.clubs set org_number = '987654321' where id = (select id from c_klubb);
select pg_temp.lik((select org_number from public.clubs where id = (select id from c_klubb)), '987654321', 'C23 org_number med 9 siffer');
reset role;
select pg_temp.som('');
delete from public.clubs where id = (select id from c_klubb);
select pg_temp.lik((select count(*)::int from public.club_roles where club_id = (select id from c_klubb)), 0, 'C24 klubben slettes med rollene');

-- --- D: egne roller ------------------------------------------------------------------
-- Dag (u5) blir aktiv i Golfgutu med en rolle som bare har rounds.
select pg_temp.som(:'u3'); set role authenticated;
update public.club_members set status = 'active' where id = :'m5';
create temp table d_rolle as select (public.club_role_save(:'G', null, 'Rundeleder', array['rounds'])).id;
select pg_temp.lik(cardinality(public.club_member_set_roles(:'m5', array[(select id from d_rolle)]::uuid[])), 1, 'D0 Dag får Rundeleder');
reset role;
select pg_temp.som('');
insert into public.events (id, club_id, event_date, competition_id)
values ('eeeeeeee-0000-0000-0000-0000000044d1', :'G', '2031-02-01', :'liga');
insert into public.rounds (id, club_id, event_id, status)
values ('dddddddd-0000-0000-0000-0000000044d1', :'G', 'eeeeeeee-0000-0000-0000-0000000044d1', 'draft');
insert into public.club_members (id, club_id, user_id, display_name, status)
values ('11111111-0000-0000-0000-0000000044d1', :'G', :'u7', 'Ventende Siv', 'pending');
select pg_temp.som(:'u5'); set role authenticated;
select pg_temp.lik(public.is_club_organizer(:'G'), true, 'D1 Rundeleder: is_club_organizer');
select pg_temp.lik((public.start_round('dddddddd-0000-0000-0000-0000000044d1', '[]') ->> 'status'), 'active', 'D2 Rundeleder starter runden');
with u as (update public.rounds set status = 'locked' where id = 'dddddddd-0000-0000-0000-0000000044d1' returning 1)
select pg_temp.lik((select count(*)::int from u), 1, 'D3 Rundeleder låser runden');
select pg_temp.lik(public.can_score(:'r3', :'m1'), true, 'D4 Rundeleder kan rette score (can_score)');
with u as (update public.hole_scores set strokes = strokes where round_id = :'r3' returning 1)
select pg_temp.lik((select count(*)::int > 0 from u), true, 'D5 Rundeleder retter score i en annens runde');
select pg_temp.feil($$select public.create_competition('fun', 'Dags cup', 'aaaaaaaa-0000-0000-0000-000000000001')$$, '42501');
select pg_temp.feil($$insert into public.seasons (club_id, name, status, rules) values ('aaaaaaaa-0000-0000-0000-000000000001', 'Dags sesong', 'planned', '{"version": 2}')$$, '42501');
with u as (update public.club_members set status = 'active' where id = '11111111-0000-0000-0000-0000000044d1' returning 1)
select pg_temp.lik((select count(*)::int from u), 0, 'D6 Rundeleder kan ikke godkjenne medlemmer');
select pg_temp.feil(format($$select public.resolve_bet(%L, 'no')$$, :'bet'), '42501');
reset role;
select pg_temp.lik((select is_organizer from public.club_members where id = :'m5'), false, 'D7 Rundeleder er ikke arrangør for gamle bygg (ingen tournaments)');
-- Kasserer (Anders: money og Medlemsansvar fra C7; ta Medlemsansvar først).
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik(cardinality(public.club_member_set_roles(:'m2', array[:'g_kas']::uuid[])), 1, 'D8 Anders er bare kasserer');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.feil($$select public.start_round('dddddddd-0000-0000-0000-000000000004', '[]')$$, '42501');
select pg_temp.feil($$select public.save_course('aaaaaaaa-0000-0000-0000-000000000001', null, 'Kassererbane', null, null, null, true, '[]')$$, '42501');
select pg_temp.lik((public.resolve_bet(:'bet', 'no')).status, 'resolved', 'D9 Kasserer avgjør veddemålet');
select pg_temp.lik(public.resolve_report(:'rep', 'remove') ->> 'status', 'removed', 'D10 Kasserer fjerner meldingen etter rapporten');
reset role;

-- --- E: gamle bygg -----------------------------------------------------------------
select pg_temp.som(:'u1'); set role authenticated;
update public.club_members set is_organizer = true where id = :'m9';
select pg_temp.lik((select count(*)::int from public.club_member_roles where member_id = :'m9' and role_id = :'g_arr'), 1, 'E1 is_organizer = true gir Arrangør');
update public.club_members set is_organizer = false where id = :'m9';
select pg_temp.lik((select count(*)::int from public.club_member_roles where member_id = :'m9'), 0, 'E2 is_organizer = false tar den');
update public.club_members set is_treasurer = true where id = :'m5';
select pg_temp.lik((select count(*)::int from public.club_member_roles where member_id = :'m5' and role_id = :'g_kas'), 1, 'E3 is_treasurer = true gir Kasserer');
update public.club_members set is_treasurer = false where id = :'m5';
select pg_temp.lik((select count(*)::int from public.club_member_roles where member_id = :'m5' and role_id = :'g_kas'), 0, 'E4 is_treasurer = false tar den');
insert into public.club_members (id, club_id, display_name, is_organizer, status)
values ('11111111-0000-0000-0000-0000000044e1', :'G', 'Ny arrangør', true, 'active');
select pg_temp.lik((select string_agg(r.template_key, ',') from public.club_member_roles mr join public.club_roles r on r.id = mr.role_id
                     where mr.member_id = '11111111-0000-0000-0000-0000000044e1'), 'organizer', 'E5 nytt medlem med is_organizer får Arrangør (ikke Eier)');
-- is_organizer = false tar også egne roller med tournaments.
reset role;
select pg_temp.som(:'u3'); set role authenticated;
create temp table e_rolle as select (public.club_role_save(:'G', null, 'Turneringsleder', array['tournaments'])).id;
select cardinality(public.club_member_set_roles(:'m9', array[(select id from e_rolle)]::uuid[])) = 1;
reset role;
select pg_temp.lik((select is_organizer from public.club_members where id = :'m9'), true, 'E6 egen rolle med tournaments gir is_organizer');
select pg_temp.som(:'u1'); set role authenticated;
update public.club_members set is_organizer = false where id = :'m9';
select pg_temp.lik((select count(*)::int from public.club_member_roles where member_id = :'m9'), 0, 'E7 is_organizer = false tar alle roller med tournaments');
reset role;
-- Den som bare har rounds kan ikke endre flaggene (guard: members).
select pg_temp.som(:'u5'); set role authenticated;
with u as (update public.club_members set is_organizer = true where id = '11111111-0000-0000-0000-000000000009' returning 1)
select pg_temp.lik((select count(*)::int from u), 0, 'E8 uten members: flaggene kan ikke endres (RLS)');
reset role;
-- Eieren endrer rettighetene på Arrangør: flaggene følger.
select pg_temp.som(:'u3'); set role authenticated;
select (public.club_role_save(:'G', :'g_arr', 'Arrangør', array['rounds', 'members', 'money'])).id is not null;
reset role;
select pg_temp.lik((select is_organizer from public.club_members where id = '11111111-0000-0000-0000-0000000044e1'), false,
                   'E9 Arrangør uten tournaments: is_organizer følger');
select pg_temp.lik((select is_organizer from public.club_members where id = :'m3'), true, 'E10 eieren er fortsatt arrangør');

-- --- F: kontrollen etterpå ----------------------------------------------------------
select pg_temp.lik((select count(*)::int from public.club_members m, lateral private.member_flags(m.id) f
                    where m.is_organizer <> f.is_organizer or m.is_treasurer <> f.is_treasurer), 0,
                   'F1 flaggene er lik rollene etter alt over');
select pg_temp.lik((select count(*)::int from public.club_roles where template_key is not null group by club_id, template_key having count(*) > 1 limit 1), null::int,
                   'F2 ingen mal to ganger (044 kjørt to ganger)');
select pg_temp.lik((select count(*)::int from public.clubs c
                    where exists (select 1 from public.club_members m where m.club_id = c.id and m.is_organizer)
                      and not exists (select 1 from public.club_member_roles mr join public.club_roles r on r.id = mr.role_id
                                      where mr.club_id = c.id and r.is_owner)), 0, 'F3 hver klubb med arrangør har eier');

rollback;
