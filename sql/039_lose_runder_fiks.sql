-- 039: my_loose_rounds raskere (fase 24, funn i lasttesten 09.10.2026).
--
-- Lasttesten (sql/lokal/lasttest_fase24.sql, 22 000 runder hvorav 2 000 løse) viste at
-- my_loose_rounds() fra 037 brukte ~300 ms, mot ~40 ms for spørringen den erstattet. Planleggeren
-- sjekket can_read_round på ALLE løse runder i basen før den koblet mot kandidatene, og
-- spilledag-grenen leste hele rounds. Her tas kandidatene først som materialiserte mengder
-- (kandidatene, så de løse av dem som ikke er kladd), og can_read_round kjøres bare på dem.
-- Lokalt (lasttest_fase24.sql): 289 ms → 5,7 ms, samme rader.
-- Samme svar som før: samme kandidater og samme sjekk.
--
-- Bare en ny utgave av funksjonen. Idempotent. Rullebakke: kjør definisjonen fra 037 igjen.

create or replace function public.my_loose_rounds()
returns setof public.rounds
language sql
stable
security definer
set search_path = ''
as $$
  with candidates as materialized (
    select x.id from public.rounds x where x.club_id is null and x.owner_id = auth.uid()
    union
    select p.round_id from public.round_participants p where p.profile_id = auth.uid()
    union
    select cr.round_id from public.competition_rounds cr
     where cr.competition_id = any (public.my_competition_ids())
    union
    select x.id from public.rounds x
     where x.club_id is null
       and x.event_id in (select e.id from public.events e
                           where e.competition_id = any (public.my_entered_competition_ids()
                                                         || public.my_staff_competition_ids()))
  ),
  -- Egen materialisert mengde, så can_read_round ikke flyttes inn i skanningen av alle løse runder.
  mine as materialized (
    select r.*
      from candidates c
      join public.rounds r on r.id = c.id
     where r.club_id is null
       and r.status <> 'draft'
  )
  select m.* from mine m where public.can_read_round(m.id);
$$;

revoke all on function public.my_loose_rounds() from public, anon;
grant execute on function public.my_loose_rounds() to authenticated;
