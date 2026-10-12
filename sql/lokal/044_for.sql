\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Første halvdel av prøven for 044_roller.sql: «verden før». Kjøres på en kopi av
-- den lokale basen med hele kjeden 001–043 og 034 (verdenen fra lokal/033_for.sql og
-- 034), FØR 044. Lagres (ingen rollback), så bruk en kopi.
--
-- Legger til det testdataene mangler for rollene:
--   * Golfgutu: Bjørn (u3) er også arrangør, Anders (u2) er kasserer (uten å være
--     arrangør), et åpent veddemål og en åpen rapport om en melding;
--   * Andre: et eldre navn uten innlogging som er arrangør (Eier skal likevel til Ola);
--   * Tom klubb: bare Dag (u5), ingen arrangør (får ingen eier).
-- Så kjøres hver prøve i lokal44.prober som hver innlogging (og uten innlogging), og
-- svaret lagres i lokal44.for_svar. lokal/044_prove.sql kjører de samme prøvene etter
-- 044 og sammenligner.
--
-- En prøve er én SQL-setning som kjøres i en deltransaksjon som alltid rulles
-- tilbake. Svaret er «ok:<verdi>» eller «err:<SQLSTATE>». Merket (tag) sier hvilken
-- rettighet prøven hører til etter 044 (tournaments, rounds, members, money), any
-- (står på is_club_organizer) eller read (lesing).
-- ===========================================================================

create schema if not exists lokal44;
grant usage on schema lokal44 to authenticated;

-- --- Verdenen ------------------------------------------------------------------
update public.club_members set is_organizer = true where id = '11111111-0000-0000-0000-000000000003';
update public.club_members set is_treasurer = true where id = '11111111-0000-0000-0000-000000000002';
insert into public.club_members (id, club_id, user_id, display_name, is_organizer, status, created_at)
values ('22222222-0000-0000-0000-0000000000a1', 'aaaaaaaa-0000-0000-0000-000000000002', null, 'Gamle Per', true,
        'active', '2020-01-01')
on conflict do nothing;
insert into public.clubs (id, name) values ('aaaaaaaa-0000-0000-0000-000000000004', 'Tom klubb')
on conflict do nothing;
insert into public.club_members (id, club_id, user_id, display_name, status)
values ('44444444-0000-0000-0000-000000000005', 'aaaaaaaa-0000-0000-0000-000000000004',
        '00000000-0000-0000-0000-000000000005', 'Dag', 'active')
on conflict do nothing;
insert into public.bets (id, club_id, season_id, event_id, creator_id, question)
values ('b0000000-0000-0000-0000-0000000044b1', 'aaaaaaaa-0000-0000-0000-000000000001',
        '5eeeeeee-0000-0000-0000-000000002026', null, '11111111-0000-0000-0000-000000000003',
        'Bjørn slår Thomas')
on conflict do nothing;
insert into public.thread_messages (id, club_id, event_id, member_id, body)
values ('70000000-0000-0000-0000-0000000044a1', 'aaaaaaaa-0000-0000-0000-000000000001',
        'eeeeeeee-0000-0000-0000-000000000003', '11111111-0000-0000-0000-000000000003', 'Stygg melding')
on conflict do nothing;
insert into public.content_reports (id, reporter_id, kind, target_id, club_id, reason)
values ('7e000000-0000-0000-0000-0000000044a1', '00000000-0000-0000-0000-000000000002', 'message',
        '70000000-0000-0000-0000-0000000044a1', 'aaaaaaaa-0000-0000-0000-000000000001', 'offensive')
on conflict do nothing;

-- --- Prøvene ---------------------------------------------------------------------
create table if not exists lokal44.prober (id serial primary key, tag text not null, hva text not null, sql text not null);
create table if not exists lokal44.for_svar (uid text, probe integer, svar text, primary key (uid, probe));
grant select on lokal44.prober to authenticated;
grant select, insert on lokal44.for_svar to authenticated;
truncate lokal44.prober, lokal44.for_svar;

create or replace function lokal44.prov(p_sql text) returns text language plpgsql as $$
declare
  v text;
begin
  begin
    execute p_sql into v;
    raise exception using errcode = 'DDOK1', message = coalesce(v, 'null');
  exception when others then
    if sqlstate = 'DDOK1' then return 'ok:' || sqlerrm; end if;
    return 'err:' || sqlstate;
  end;
end $$;
grant execute on function lokal44.prov(text) to authenticated;

-- Hjelperne per klubb, runde og turnering.
insert into lokal44.prober (tag, hva, sql)
select 'any', 'is_club_organizer ' || c.name, format('select public.is_club_organizer(%L)::text', c.id) from public.clubs c
union all
select 'rounds', 'is_round_organizer ' || r.id, format('select public.is_round_organizer(%L)::text', r.id) from public.rounds r
union all
select 'rounds', 'can_link_round ' || r.id, format('select public.can_link_round(%L)::text', r.id) from public.rounds r
union all
select 'read', 'can_read_round ' || r.id, format('select public.can_read_round(%L)::text', r.id) from public.rounds r
union all
select 'rounds', 'can_score ' || r.id || ' ' || m.display_name, format('select public.can_score(%L, %L)::text', r.id, m.id)
  from public.rounds r join public.club_members m on m.club_id = r.club_id
union all
select 'tournaments', 'is_competition_admin ' || c.id, format('select public.is_competition_admin(%L)::text', c.id) from public.competitions c;

-- RPC-ene.
insert into lokal44.prober (tag, hva, sql)
select 'tournaments', 'create_competition ' || c.name,
       format($q$select (public.create_competition('fun', 'Prøve', %L) is not null)::text$q$, c.id) from public.clubs c
union all
select 'rounds', 'save_course ' || c.name,
       format($q$select (public.save_course(%L, null, 'Prøvebane', null, null, null, true, '[]') is not null)::text$q$, c.id) from public.clubs c
union all
select 'any', 'push_status ' || c.name, format('select count(*)::text from public.push_status(%L)', c.id) from public.clubs c
union all
select 'rounds', 'delete_round ' || r.id, format('select public.delete_round(%L)::text', r.id) from public.rounds r where r.club_id is not null
union all
select 'rounds', 'set_round_setup ' || r.id, format($q$select public.set_round_setup(%L, '[]')::text$q$, r.id) from public.rounds r where r.club_id is not null
union all
select 'rounds', 'start_round ' || r.id, format($q$select public.start_round(%L, '[]')::text$q$, r.id) from public.rounds r where r.club_id is not null
union all
select 'rounds', 'confirm_round_par ' || r.id, format('select (public.confirm_round_par(%L) is not null)::text', r.id) from public.rounds r where r.club_id is not null
union all
select 'tournaments', 'set_event_committee ' || e.id, format($q$select public.set_event_committee(%L, '{}')::text$q$, e.id) from public.events e
union all
select 'rounds', 'confirm_course ' || c.id, format('select (public.confirm_course(%L) is not null)::text', c.id) from public.courses c where c.club_id is not null
union all
select 'money', 'resolve_bet ' || b.id, format($q$select (public.resolve_bet(%L, 'no')).status$q$, b.id) from public.bets b
union all
select 'money', 'settle_bet ' || b.id, format($q$select (public.settle_bet(%L, 'no')).status$q$, b.id) from public.bets b
union all
select 'money', 'mark_bets_closed ' || b.id, format('select public.mark_bets_closed(array[%L]::uuid[])::text', b.id) from public.bets b
union all
select 'money', 'resolve_report ' || r.id, format($q$select public.resolve_report(%L, 'dismiss') ->> 'status'$q$, r.id) from public.content_reports r;

-- Policyene (hvor mange rader du ser eller får skrive, per klubb).
insert into lokal44.prober (tag, hva, sql)
select x.tag, x.hva || ' ' || c.name, format(x.sql, c.id)
  from public.clubs c
 cross join (values
   ('tournaments', 'events_update',        'with u as (update public.events set note = note where club_id = %L returning 1) select count(*)::text from u'),
   ('tournaments', 'events_insert',        $q$with u as (insert into public.events (club_id, event_date) values (%L, '2031-01-01') returning 1) select count(*)::text from u$q$),
   ('tournaments', 'seasons_update',       'with u as (update public.seasons set name = name where club_id = %L returning 1) select count(*)::text from u'),
   ('tournaments', 'seasons_delete',       $q$with u as (delete from public.seasons where club_id = %L and status = 'planned' returning 1) select count(*)::text from u$q$),
   ('tournaments', 'competitions_update',  'with u as (update public.competitions set name = name where club_id = %L returning 1) select count(*)::text from u'),
   ('tournaments', 'competitions_delete',  'with u as (delete from public.competitions where club_id = %L and season_id is null returning 1) select count(*)::text from u'),
   ('tournaments', 'signups_update',       'with u as (update public.signups set member_id = member_id where club_id = %L returning 1) select count(*)::text from u'),
   ('rounds',      'rounds_update',        'with u as (update public.rounds set name = name where club_id = %L returning 1) select count(*)::text from u'),
   ('rounds',      'rounds_insert',        $q$with u as (insert into public.rounds (club_id, status) values (%L, 'draft') returning 1) select count(*)::text from u$q$),
   ('rounds',      'rounds_delete',        $q$with u as (delete from public.rounds where club_id = %L and status = 'draft' returning 1) select count(*)::text from u$q$),
   ('rounds',      'courses_update',       'with u as (update public.courses set name = name where club_id = %L returning 1) select count(*)::text from u'),
   ('rounds',      'course_holes_update',  'with u as (update public.course_holes h set par = par from public.courses c where c.id = h.course_id and c.club_id = %L returning 1) select count(*)::text from u'),
   ('rounds',      'round_players_update', 'with u as (update public.round_players set team_no = team_no where club_id = %L returning 1) select count(*)::text from u'),
   ('rounds',      'hole_scores_update',   'with u as (update public.hole_scores s set strokes = strokes from public.rounds r where r.id = s.round_id and r.club_id = %L returning 1) select count(*)::text from u'),
   ('members',     'club_members_update',  'with u as (update public.club_members set handicap_index = handicap_index where club_id = %L returning 1) select count(*)::text from u'),
   ('members',     'club_members_approve', $q$with u as (update public.club_members set status = 'active' where club_id = %L and status = 'pending' returning 1) select count(*)::text from u$q$),
   ('members',     'club_members_seed',    'with u as (update public.club_members set seed_group = 1 where club_id = %L and user_id is null returning 1) select count(*)::text from u'),
   ('members',     'club_members_insert',  $q$with u as (insert into public.club_members (club_id, display_name) values (%L, 'Ny spiller') returning 1) select count(*)::text from u$q$),
   ('members',     'club_members_delete',  'with u as (delete from public.club_members where club_id = %L and user_id is null returning 1) select count(*)::text from u'),
   ('members',     'club_members_kasserer', 'with u as (update public.club_members set is_treasurer = true where club_id = %L and user_id is null returning 1) select count(*)::text from u'),
   ('money',       'content_reports_select', 'select count(*)::text from public.content_reports where club_id = %L'),
   ('money',       'thread_messages_delete', 'with u as (delete from public.thread_messages where club_id = %L returning 1) select count(*)::text from u'),
   ('any',         'clubs_update',          'with u as (update public.clubs set name = name where id = %L returning 1) select count(*)::text from u'),
   ('any',         'activity_select',       'select count(*)::text from public.activity where club_id = %L'),
   ('any',         'entitlements_select',   'select count(*)::text from public.entitlements where club_id = %L'),
   ('read',        'rounds_select',         'select count(*)::text from public.rounds where club_id = %L')
 ) as x(tag, hva, sql);

-- --- Bildet før ------------------------------------------------------------------
create or replace function lokal44.ta_bilde(p_uid text) returns integer language plpgsql as $$
declare n integer;
begin
  insert into lokal44.for_svar (uid, probe, svar)
  select p_uid, p.id, lokal44.prov(p.sql) from lokal44.prober p order by p.id;
  get diagnostics n = row_count;
  return n;
end $$;
grant execute on function lokal44.ta_bilde(text) to authenticated;

select set_config('request.jwt.claim.sub', '', false);
set role authenticated; select 'ingen innlogging: ' || lokal44.ta_bilde('ingen'); reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
set role authenticated; select 'u1: ' || lokal44.ta_bilde('u1'); reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', false);
set role authenticated; select 'u2: ' || lokal44.ta_bilde('u2'); reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
set role authenticated; select 'u3: ' || lokal44.ta_bilde('u3'); reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
set role authenticated; select 'u4: ' || lokal44.ta_bilde('u4'); reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', false);
set role authenticated; select 'u5: ' || lokal44.ta_bilde('u5'); reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000007', false);
set role authenticated; select 'u7: ' || lokal44.ta_bilde('u7'); reset role;
select set_config('request.jwt.claim.sub', '', false);

select 'prøver: ' || count(*) || ', svar: ' || (select count(*) from lokal44.for_svar)
       || ', tillatt: ' || (select count(*) from lokal44.for_svar where svar not like 'err:42501' and svar not in ('ok:0', 'ok:false'))
  from lokal44.prober;
