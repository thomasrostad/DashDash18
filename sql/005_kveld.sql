-- ===========================================================================
-- 005 – KVELD: SOSIALKOMITEEN I ÉN TRANSAKSJON (FORSLAG, IKKE KJØRT)
-- ===========================================================================
-- Status: FORSLAG til godkjenning (ROADMAP B5). Ikke kjørt noe sted.
--
-- Hvorfor: Policyene i 001 gir allerede det terminlista og påmeldingen trenger
-- (events/event_committee: les medlem, skriv arrangør; signups: egen rad eller
-- arrangør). Ingen tillatelse mangler. Men å endre sosialkomiteen for en kveld
-- er i dag to kall fra appen (slett de som er tatt ut, legg til de nye). Feiler
-- det andre, står kvelden med en halv komité. CLAUDE.md sier at en handling som
-- skriver flere rader skal være én RPC. Denne gjør byttet i én transaksjon.
--
-- Appen bruker foreløpig de to kallene (TerminlisteModel.setCommittee). Når
-- denne er kjørt, byttes de ut med ett kall til set_event_committee.
--
-- security invoker: RLS-policyene på event_committee gjelder som før, så bare
-- arrangøren i kveldens klubb kan endre. Funksjonen sjekker det likevel først,
-- for å gi en norsk feilmelding i stedet for en stille null-rader-endring.

begin;

create or replace function public.set_event_committee(p_event_id uuid, p_member_ids uuid[])
returns uuid[]
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_club    uuid;
  v_wanted  uuid[] := coalesce(p_member_ids, '{}');
  v_result  uuid[];
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  select e.club_id into v_club from public.events e where e.id = p_event_id;
  if not found then
    raise exception 'Fant ikke kvelden' using errcode = 'P0002';
  end if;
  if not public.is_club_organizer(v_club) then
    raise exception 'Bare en arrangør kan sette sosialkomiteen' using errcode = '42501';
  end if;
  if exists (
    select 1 from unnest(v_wanted) as w(member_id)
    where not exists (select 1 from public.club_members m
                      where m.id = w.member_id and m.club_id = v_club and m.status = 'active')
  ) then
    raise exception 'Alle i komiteen må være aktive medlemmer av klubben' using errcode = '22023';
  end if;

  delete from public.event_committee c
   where c.event_id = p_event_id
     and not (c.member_id = any (v_wanted));

  insert into public.event_committee (event_id, member_id, club_id)
  select p_event_id, w.member_id, v_club
    from (select distinct unnest(v_wanted) as member_id) w
  on conflict (event_id, member_id) do nothing;

  select coalesce(array_agg(c.member_id order by c.member_id), '{}')
    into v_result
    from public.event_committee c
   where c.event_id = p_event_id;
  return v_result;
end;
$$;
revoke all on function public.set_event_committee(uuid, uuid[]) from public, anon;
grant execute on function public.set_event_committee(uuid, uuid[]) to authenticated;

commit;

-- --- Kontroll (kjør etter, én om gangen) -----------------------------------
-- 1. anon kan ikke kjøre funksjonen (forventet: false).
-- select has_function_privilege('anon', 'public.set_event_committee(uuid, uuid[])', 'execute') as anon_kan;
-- 2. authenticated kan (forventet: true).
-- select has_function_privilege('authenticated', 'public.set_event_committee(uuid, uuid[])', 'execute') as innlogget_kan;

-- --- Rullebakke ---------------------------------------------------------------
-- drop function if exists public.set_event_committee(uuid, uuid[]);
