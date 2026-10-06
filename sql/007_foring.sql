-- ===========================================================================
-- 007 – FØRING: MARKØREN BEKREFTER PAR (FORSLAG, IKKE KJØRT)
-- ===========================================================================
-- Status: FORSLAG til godkjenning. Ikke kjørt noe sted.
--
-- Hvorfor: Før første hull skal noen i båsen si at parene stemmer med
-- simulatorskjermen («Stemmer dette med skjermen?», PWA: parBekreftetAv og
-- kanBekrefteBaneoppsett). I dag kan bare arrangøren skrive rounds
-- (rounds_update), så appen viser knappen bare for arrangøren. I PWA-en kan
-- også en markør bekrefte. En policy som lar markøren oppdatere rounds ville
-- gitt ham alle kolonnene; denne RPC-en rører bare de to feltene.
--
-- Regel: arrangøren, eller en markør i runden. Runden må gå (active).
-- Allerede bekreftet: ingenting endres, og den første bekreftelsen står.
--
-- Appen (DashDash18/Features/Runde) bruker i dag en vanlig update for
-- arrangøren. Når denne er kjørt, byttes den ut med ett kall til
-- confirm_round_par, og knappen vises også for markøren.

begin;

create or replace function public.confirm_round_par(p_round_id uuid)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_round   public.rounds%rowtype;
  v_member  uuid;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  select * into v_round from public.rounds r where r.id = p_round_id for update;
  if not found or not public.can_read_round(p_round_id) then
    raise exception 'Fant ikke runden' using errcode = 'P0002';
  end if;

  v_member := public.my_member_id(v_round.club_id);

  if not public.is_club_organizer(v_round.club_id) then
    if v_round.status <> 'active' then
      raise exception 'Runden er ikke i gang' using errcode = '55000';
    end if;
    if not exists (select 1 from public.round_players rp
                   where rp.round_id = p_round_id
                     and rp.member_id = v_member
                     and rp.is_marker) then
      raise exception 'Bare arrangøren eller en markør kan bekrefte parene' using errcode = '42501';
    end if;
  end if;

  if v_round.par_confirmed_at is null then
    update public.rounds
       set par_confirmed_by = v_member,
           par_confirmed_at = now()
     where id = p_round_id;
    return now();
  end if;
  return v_round.par_confirmed_at;
end;
$$;
revoke all on function public.confirm_round_par(uuid) from public, anon;
grant execute on function public.confirm_round_par(uuid) to authenticated;

commit;

-- Tilbakerulling:
-- drop function if exists public.confirm_round_par(uuid);
