-- ===========================================================================
-- 014 – PAR-BEKREFTELSEN UTEN MARKØR (FORSLAG, IKKE KJØRT)
-- ===========================================================================
-- Status: FORSLAG til godkjenning. Ikke kjørt noe sted.
-- Nummer: 014 fordi en annen gjennomgang kan ha brukt 013 samtidig.
--
-- Hvorfor: confirm_round_par (007) lar bare arrangøren eller en markør
-- bekrefte parene. I en runde uten båser (alle fører selv) finnes ingen
-- markør, så bare arrangøren kan starte føringen. Er han ikke med, eller har
-- han ikke dekning, står hullkortet sperret for alle. PWA-en
-- (kanBekrefteBaneoppsett, app-nytt.js 5829) lar da hvem som helst bekrefte:
--
--   arrangør, eller runden har ikke båser → ja
--   ellers: jeg står ikke i en bås, båsen min har ikke markør, eller jeg er
--   markøren → ja
--
-- Denne fila gjør regelen i databasen lik PWA-en, men krever i tillegg at den
-- som bekrefter spiller i runden (PWA-en har ikke runder med tilskuere).
--
-- Appen må følge med etter at fila er kjørt: RoundGame.canConfirmPar
-- (DashDash18/Features/Runde/ForingLogic.swift) får samme regel, og testen
-- ForingParTests.utenBaaserIngenMarkor snus. Ikke endre appen før fila er kjørt,
-- ellers får spillerne 42501 når de trykker.
-- ===========================================================================

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
  v_bay     integer;
  v_marker  uuid;
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
                   where rp.round_id = p_round_id and rp.member_id = v_member) then
      raise exception 'Bare arrangøren eller en markør kan bekrefte parene' using errcode = '42501';
    end if;

    select rp.bay_no into v_bay
      from public.round_players rp
     where rp.round_id = p_round_id and rp.member_id = v_member;

    if v_bay is not null and v_bay >= 1 then
      select rp.member_id into v_marker
        from public.round_players rp
       where rp.round_id = p_round_id and rp.bay_no = v_bay and rp.is_marker
       limit 1;
      if v_marker is not null and v_marker <> v_member then
        raise exception 'Bare arrangøren eller en markør kan bekrefte parene' using errcode = '42501';
      end if;
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

-- Kontroll (les): anon skal ikke kunne kjøre funksjonen.
-- select has_function_privilege('anon', 'public.confirm_round_par(uuid)', 'execute') as anon_kan;  -- false
--
-- Tilbakerulling: kjør create or replace-blokken fra 007_foring.sql på nytt.
