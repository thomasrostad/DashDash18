-- 069: forlat en klubb selv, eller trekk en forespørsel som venter. IKKE KJØRT.
--
-- Bakgrunn: en spiller kan være med i flere klubber, men kunne ikke gå ut av en. Bare en
-- arrangør kunne arkivere raden (Arrangør → Troppen), og guard_club_members (059) stopper alle
-- andre som endrer status. En forespørsel som venter, kunne heller ikke trekkes.
--
-- Hva (Thomas 22.10.2026):
--   * Ny RPC leave_club(p_club_id uuid), for den innloggede, i én transaksjon:
--       - Venter du (status 'pending'): raden slettes. Triggeren club_members_pending_cleanup
--         (067) tar varselet til arrangørene. Har raden historikk (en arrangør har satt en
--         tidligere aktiv rad tilbake til 'pending': runder, påmeldinger, meldinger,
--         kommentarer eller veddemål), arkiveres den i stedet, så ingenting slettes med den.
--       - Er du aktiv: raden arkiveres ('archived'), som når en arrangør arkiverer. Navnet,
--         rundene, statistikken og innloggingen (user_id) står, så arrangøren kan gjenopprette
--         raden i Troppen som i dag. Rollene (club_member_roles) og flaggene is_organizer og
--         is_treasurer tas, og varselvalgene for klubben (push_preferences) slettes.
--         Varslene stopper fordi mottakerne er aktive medlemmer.
--       - Den siste eieren (private.member_is_last_owner, 044) kan ikke gå: 55000 «Du er den
--         siste eieren …». Gi eierskapet videre først (Arrangør → Troppen → medlemmet).
--       - Deltakere (kind = 'participant', 059) er ikke med i klubben og får P0002, som en
--         som ikke er med.
--     Svar: {"result": "withdrawn" | "left", "member_id": …}.
--   * Ingen endring i guard_club_members. Funksjonen skriver raden med dd18.roles_sync = 'on'
--     for transaksjonen, samme bryter som private.sync_member_flags (044) bruker når den
--     skriver flaggene. Da slipper guard_club_members, club_members_roles_inactive og
--     club_members_roles_mirror den gjennom. Reglene de ellers ville sjekket, står i
--     funksjonen: bare din egen rad, bare 'archived', siste eier stoppes, klubben låses
--     (for update) som i club_transfer_ownership, så to eiere ikke kan gå samtidig.
--   * Kalt uten klubb (p_club_id er default null) svarer den 22023 «Mangler klubb» før noe
--     skjer. Appen bruker det til å sjekke om 069 er kjørt (PGRST202 = funksjonen finnes ikke).
--
-- Ikke med: påmeldinger til kommende kvelder står som før (som når en arrangør arkiverer).
-- Å bli med igjen: join_club svarer med den arkiverte raden; arrangøren gjenoppretter den.
--
-- Krever: 044 (roller, member_is_last_owner, roles_sync), 059 (kind), 067 (opprydding av
-- varselet for ventende).
--
-- Mønsteret fra 001–068: én transaksjon, idempotent, search_path = '', revoke etter
-- create or replace, kontroll og rullebakke nederst.

begin;

create or replace function public.leave_club(p_club_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member  public.club_members;
  v_prev    text;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if p_club_id is null then
    raise exception 'Mangler klubb' using errcode = '22023';
  end if;

  -- Én endring av roller og eiere om gangen per klubb (som club_transfer_ownership).
  perform 1 from public.clubs c where c.id = p_club_id for update;

  select * into v_member
    from public.club_members m
   where m.club_id = p_club_id and m.user_id = auth.uid() and m.kind = 'member'
   for update;
  if not found or v_member.status = 'archived' then
    raise exception 'Du er ikke med i klubben' using errcode = 'P0002';
  end if;

  -- Den siste eieren går ikke (en som venter, er aldri eier).
  if private.member_is_last_owner(v_member.id) then
    raise exception 'Du er den siste eieren av klubben. Gi eierskapet til en annen under Arrangør → Troppen før du går ut.'
      using errcode = '55000';
  end if;

  -- Skriv raden forbi guard_club_members og rolletriggerne (som sync_member_flags, 044).
  v_prev := current_setting('dd18.roles_sync', true);
  perform set_config('dd18.roles_sync', 'on', true);

  delete from public.club_member_roles mr where mr.member_id = v_member.id;
  delete from public.push_preferences p where p.member_id = v_member.id;

  -- En forespørsel uten historikk slettes. Ellers arkiveres raden, og alt den har står.
  if v_member.status = 'pending'
     and not exists (select 1 from public.round_players rp where rp.member_id = v_member.id)
     and not exists (select 1 from public.signups s where s.member_id = v_member.id)
     and not exists (select 1 from public.thread_messages t where t.member_id = v_member.id)
     and not exists (select 1 from public.comments c where c.member_id = v_member.id)
     and not exists (select 1 from public.bet_stakes b where b.member_id = v_member.id) then
    delete from public.club_members m where m.id = v_member.id;
  else
    update public.club_members m
       set status = 'archived', is_organizer = false, is_treasurer = false
     where m.id = v_member.id;
  end if;

  perform set_config('dd18.roles_sync', coalesce(v_prev, ''), true);
  return jsonb_build_object('result', case when v_member.status = 'pending' then 'withdrawn' else 'left' end,
                            'member_id', v_member.id);
end;
$$;
revoke all on function public.leave_club(uuid) from public, anon;
grant execute on function public.leave_club(uuid) to authenticated;

comment on function public.leave_club(uuid) is
  'Den innloggede går ut av klubben (069): venter = raden slettes (eller arkiveres med historikk), '
  'aktiv = raden arkiveres uten roller og varselvalg; historikken og user_id står. Siste eier: 55000.';


-- ===========================================================================
-- KONTROLL (kjøres i samme transaksjon; feiler ved avvik)
-- ===========================================================================
do $$
declare
  v_ok int := 0;
begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname = 'leave_club'
                and p.prosecdef and p.proconfig @> array['search_path=""']) then
    v_ok := v_ok + 1;
  end if;
  if not has_function_privilege('anon', 'public.leave_club(uuid)', 'execute') then
    v_ok := v_ok + 1;
  end if;
  if has_function_privilege('authenticated', 'public.leave_club(uuid)', 'execute') then
    v_ok := v_ok + 1;
  end if;
  -- Det funksjonen bygger på, finnes.
  if to_regprocedure('private.member_is_last_owner(uuid)') is not null
     and to_regprocedure('private.roles_syncing()') is not null
     and exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'club_members' and column_name = 'kind') then
    v_ok := v_ok + 1;
  end if;
  if v_ok <> 4 then
    raise exception '069: kontroll % av 4', v_ok;
  end if;
  raise notice '069 kontroll: 4 av 4';
end $$;

commit;

-- KONTROLL ETTERPÅ (bare lesing)
-- 1) Funksjonen og rettighetene. Forventet: true, false, true.
-- select p.prosecdef,
--        has_function_privilege('anon', 'public.leave_club(uuid)', 'execute') as anon_kan,
--        has_function_privilege('authenticated', 'public.leave_club(uuid)', 'execute') as innlogget_kan
--   from pg_proc p where p.oid = 'public.leave_club(uuid)'::regprocedure;
-- 2) Etter en prøve i appen (Deg → Klubb → Forlat): raden er arkivert, uten roller og varselvalg.
--    Forventet: status archived, user_id satt, roller 0, varselvalg 0.
-- select m.status, m.user_id is not null as har_innlogging,
--        (select count(*) from public.club_member_roles mr where mr.member_id = m.id) as roller,
--        (select count(*) from public.push_preferences p where p.member_id = m.id) as varselvalg
--   from public.club_members m where m.id = '<member_id fra svaret>';

-- RULLEBAKKE
-- Raden som er arkivert, gjenopprettes av arrangøren i Troppen (rollene må gis på nytt).
-- drop function if exists public.leave_club(uuid);
