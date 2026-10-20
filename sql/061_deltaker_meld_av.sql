-- 061_deltaker_meld_av.sql — en deltaker (sql/059) kan melde seg av med leave_competition.
-- Godkjent (Thomas kjører SQL på test denne økten, 20.10.2026). Ikke kjørt på prod.
--
-- leave_competition (fra 022) brukte owns_member, som etter 059 bare gjelder medlemmer. En deltaker ble
-- derfor ikke meldt av på den gamle veien (TournamentCore av). Nå gjelder alle dine aktive rader i
-- klubben (my_member_ids), som i competition_withdraw. Ellers uendret.
--
-- Krever 022 og 059. Idempotent. Rullebakk: kjør leave_competition fra 022_konkurranser.sql på nytt.

create or replace function public.leave_competition(p_competition_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_n integer;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  update public.competition_participants p
     set status = 'withdrawn'
   where p.competition_id = p_competition_id and p.status = 'active'
     and (p.profile_id = auth.uid() or p.member_id = any (public.my_member_ids()));   -- 061
  get diagnostics v_n = row_count;
  return v_n > 0;
end;
$$;

-- Kontroll: select prosrc like '%my_member_ids%' from pg_proc where proname = 'leave_competition'; -- true
