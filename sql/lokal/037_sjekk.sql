-- Bare lesing: sammenligner RPC-ene fra 037 med RLS-spørringene for hver bruker. Rulles tilbake.
begin;
create temp table sjekk (del text, brukere int, like_svar int, rader_rpc bigint, rader_rls bigint) on commit drop;
create temp table rad (u uuid, del text, a text, b text, na int, nb int) on commit drop;
grant all on sjekk, rad to authenticated;
do $$
declare u uuid; klubber uuid[];
begin
  select coalesce(array_agg(id), '{}') into klubber from public.clubs;
  for u in select p.id from public.profiles p loop
    perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    insert into rad
    select u, 'known_profiles',
           (select string_agg(id::text, ',' order by id) from public.known_profiles()),
           (select string_agg(id::text, ',' order by id) from public.profiles where id <> u),
           (select count(*) from public.known_profiles()), (select count(*) from public.profiles where id <> u)
    union all
    select u, 'my_loose_rounds',
           (select string_agg(id::text, ',' order by id) from public.my_loose_rounds()),
           (select string_agg(id::text, ',' order by id) from public.rounds where club_id is null and status <> 'draft'),
           (select count(*) from public.my_loose_rounds()),
           (select count(*) from public.rounds where club_id is null and status <> 'draft')
    union all
    select u, 'my_competitions',
           (select string_agg(id::text, ',' order by id) from public.my_competitions()),
           (select string_agg(id::text, ',' order by id) from public.competitions),
           (select count(*) from public.my_competitions()), (select count(*) from public.competitions)
    union all
    select u, 'my_activity',
           (select string_agg(id::text, ',' order by id) from public.my_activity(klubber, '-infinity')),
           (select string_agg(id::text, ',' order by id) from public.activity where club_id = any (klubber)),
           (select count(*) from public.my_activity(klubber, '-infinity')),
           (select count(*) from public.activity where club_id = any (klubber));
    execute 'reset role';
  end loop;
end $$;
insert into sjekk
select del, count(*), count(*) filter (where a is not distinct from b), sum(na), sum(nb) from rad group by del;
select * from sjekk order by del;
rollback;
