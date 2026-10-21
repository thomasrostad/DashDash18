\set ON_ERROR_STOP on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Første halvdel av prøven for 067_varsel_ventende_medlem.sql: «verden før». Kjøres på en kopi
-- med hele kjeden til og med 066, FØR 067. Lagres (ingen rollback), så bruk en kopi.
--
-- To som ventet før 067 (join_club med nytt navn):
--   * Gamle Gunnar i klubben «Før-klubben», der Frøydis er arrangør (Medlemmer og invitasjon).
--     067 skal gi én linje i bjella til Frøydis, med tiden raden ble laget.
--   * Hanne i «Klubb uten arrangør» (ingen med rettigheten). Ingen linje.
-- lokal/067_prove.sql sjekker begge.
-- ===========================================================================

\set uf  '00000000-0000-0000-0000-0000000067f1'
\set ug  '00000000-0000-0000-0000-0000000067f2'
\set uh  '00000000-0000-0000-0000-0000000067f3'
\set KF  'aaaaaaaa-0000-0000-0000-0000000067f1'
\set KU  'aaaaaaaa-0000-0000-0000-0000000067f2'

begin;
select set_config('request.jwt.claim.sub', '', false);
insert into auth.users (id) values (:'uf'), (:'ug'), (:'uh');
insert into public.clubs (id, name, join_code) values (:'KF', 'Før-klubben', 'FOERKLUBB67'),
                                                       (:'KU', 'Klubb uten arrangør', 'UTENARR67');
insert into public.club_members (club_id, user_id, display_name, is_organizer, status)
values (:'KF', :'uf', 'Frøydis', true, 'active');

select set_config('request.jwt.claim.sub', :'ug', false);
set role authenticated;
select public.join_club('FOERKLUBB67', null, 'Gamle Gunnar', 12.3);
reset role;
select set_config('request.jwt.claim.sub', :'uh', false);
set role authenticated;
select public.join_club('UTENARR67', null, 'Hanne', null);
reset role;
select set_config('request.jwt.claim.sub', '', false);
-- Raden ble laget for to timer siden.
update public.club_members set created_at = now() - interval '2 hours'
 where club_id in (:'KF', :'KU') and status = 'pending';
commit;
