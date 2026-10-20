-- 060_deltakerinvitasjon.sql — arrangøren legger inn deltakere uten innlogging, og deltakerne tar
-- plassen sin med turneringens lenke (og lager bruker i appen).
-- Godkjent og kjørt på test 20.10.2026 (rolleprøve i transaksjon som ble rullet tilbake: ok). Ikke kjørt på prod.
--
-- Bakgrunn: med 059 kan en klubbturnering ha deltakere som ikke er medlemmer. Men en deltaker fantes
-- bare når personen selv meldte seg på i appen. En klubb som kjører turnering, har ofte lista fra før
-- (påmelding på e-post, GolfBox, et regneark). Nå kan arrangøren legge dem inn, og hver deltaker kan ta
-- plassen sin og få en bruker i appen. Det gir flere brukere.
--
-- Hva som endres:
-- * add_competition_participants(turnering, navn[]): arrangøren (is_competition_admin) legger inn
--   deltakere med navn, valgfritt handicap og NGF-nummer. Hver blir en ledig deltakerrad i klubben
--   (club_members, kind = participant, uten innlogging) og påmeldt turneringen. Bare klubbturneringer.
--   Høyst 300 om gangen.
-- * competition_invite: også klubbturneringer, men bare arrangøren får koden (ikke deltakerne).
-- * competition_invite_preview: også klubbturneringer. Svarer i tillegg med klubbnavnet og de ledige
--   deltakernavnene i turneringen («Er du en av disse?»).
-- * claim_competition_invite(kode, deltaker): for en klubbturnering
--   - har du en aktiv rad i klubben (medlem eller deltaker): du meldes på med den;
--   - velger du et ledig deltakernavn: raden blir din (innloggingen kobles til navnet);
--   - ellers: du meldes på som ny deltaker (som 059).
--   For turneringer uten klubb er alt som før.
-- * club_preview (klubbkoden): viser bare ledige medlemsnavn, ikke ledige deltakere.
--
-- Ikke endret: åpen påmelding (competition_signup), klubbkoden (join_club), RLS.
--
-- Krever 022, 032 og 059. Idempotent. Kontroll og rullebakk nederst.

begin;

-- --- Arrangøren legger inn deltakere ------------------------------------------------
-- p_entries: [{"display_name": "Kari Nordmann", "handicap_index": 18.4, "ngf_number": "12-3456"}]
create or replace function public.add_competition_participants(p_competition_id uuid, p_entries jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_c      public.competitions;
  v_entry  jsonb;
  v_name   text;
  v_ngf    text;
  v_hcp    numeric;
  v_member uuid;
  v_prev   text;
  v_added  integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select * into v_c from public.competitions c where c.id = p_competition_id for update;
  if v_c.id is null or not public.is_competition_admin(v_c.id) then
    raise exception 'Fant ikke turneringen' using errcode = 'P0002';
  end if;
  if v_c.club_id is null then
    raise exception 'Bare klubbturneringer har deltakere uten innlogging' using errcode = '22023';
  end if;
  if v_c.status = 'finished' then
    raise exception 'Turneringen er ferdig' using errcode = '55000';
  end if;
  if jsonb_typeof(p_entries) is distinct from 'array' or jsonb_array_length(p_entries) = 0 then
    raise exception 'Ingen navn å legge inn' using errcode = '22023';
  end if;
  if jsonb_array_length(p_entries) > 300 then
    raise exception 'Høyst 300 om gangen' using errcode = '54000';
  end if;

  v_prev := current_setting('dd18.participant_sync', true);
  perform set_config('dd18.participant_sync', 'on', true);
  for v_entry in select value from jsonb_array_elements(p_entries) loop
    v_name := btrim(coalesce(v_entry ->> 'display_name', ''));
    if char_length(v_name) not between 1 and 40 then
      raise exception 'Ugyldig navn: «%»', left(v_name, 50) using errcode = '22023';
    end if;
    v_ngf := nullif(btrim(coalesce(v_entry ->> 'ngf_number', '')), '');
    v_hcp := (v_entry ->> 'handicap_index')::numeric;

    -- Samme NGF-nummer i klubben: samme person (raden brukes). Ellers en ny ledig deltakerrad.
    v_member := null;
    if v_ngf is not null then
      select m.id into v_member from public.club_members m
       where m.club_id = v_c.club_id and m.ngf_number = v_ngf and m.status = 'active';
    end if;
    if v_member is null then
      insert into public.club_members (club_id, display_name, handicap_index, status, kind, ngf_number)
      values (v_c.club_id, v_name, v_hcp, 'active', 'participant', v_ngf)
      returning id into v_member;
    end if;

    if not exists (select 1 from public.competition_participants p
                    where p.competition_id = v_c.id and p.member_id = v_member) then
      insert into public.competition_participants (competition_id, member_id) values (v_c.id, v_member);
      v_added := v_added + 1;
    else
      update public.competition_participants set status = 'active'
       where competition_id = v_c.id and member_id = v_member and status <> 'active';
      if found then v_added := v_added + 1; end if;
    end if;
  end loop;
  perform set_config('dd18.participant_sync', coalesce(v_prev, ''), true);
  return v_added;
end;
$$;
revoke all on function public.add_competition_participants(uuid, jsonb) from public, anon;
grant execute on function public.add_competition_participants(uuid, jsonb) to authenticated;

-- --- Koden: også klubbturneringer (bare arrangøren) -----------------------------------
create or replace function public.competition_invite(p_competition_id uuid, p_renew boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_c      public.competitions;
  v_admin  boolean;
  v_row    public.competition_invites%rowtype;
  v_try    integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  select * into v_c from public.competitions c where c.id = p_competition_id for update;
  if v_c.id is null or not public.can_read_competition(v_c.id) then
    raise exception 'Fant ikke konkurransen' using errcode = 'P0002';
  end if;
  v_admin := public.is_competition_admin(v_c.id);
  -- 060: i en klubbturnering deler arrangøren lenken, ikke deltakerne.
  if v_c.club_id is not null and not v_admin then
    raise exception 'Bare arrangøren deler lenken til en klubbturnering' using errcode = '42501';
  end if;
  if not (v_admin or public.is_competition_participant(v_c.id)) then
    raise exception 'Fant ikke konkurransen' using errcode = 'P0002';
  end if;
  if coalesce(p_renew, false) and not v_admin then
    raise exception 'Bare eieren kan lage en ny kode' using errcode = '42501';
  end if;
  if v_c.club_id is null and v_c.kind not in ('league', 'cup', 'fun') then
    raise exception 'Bare en liga, cup eller morroturnering kan deles med kode' using errcode = '22023';
  end if;
  if v_c.kind = 'game' then
    raise exception 'Et spill deles fra runden' using errcode = '22023';
  end if;
  if v_c.status = 'finished' then
    raise exception 'Konkurransen er ferdig' using errcode = '55000';
  end if;
  if v_c.kind = 'cup' and exists (select 1 from public.competition_matches where competition_id = v_c.id) then
    raise exception 'Cupen er trukket. Ingen nye kan bli med.' using errcode = '55000';
  end if;

  select * into v_row from public.competition_invites i where i.competition_id = v_c.id;
  if found and v_row.expires_at > now() and not coalesce(p_renew, false) then
    return jsonb_build_object('competition_id', v_row.competition_id, 'code', v_row.code, 'expires_at', v_row.expires_at);
  end if;
  if not v_admin then
    raise exception 'Ingen gyldig kode. Be eieren lage en ny.' using errcode = '55000';
  end if;

  perform public.ensure_profile();
  loop
    v_try := v_try + 1;
    begin
      insert into public.competition_invites as i (competition_id, code, created_by, expires_at)
      values (v_c.id, public.round_invite_code(), auth.uid(),
              -- 060: en klubbturnering varer lenger enn en uke.
              now() + case when v_c.club_id is null then interval '7 days' else interval '60 days' end)
      on conflict (competition_id) do update
        set code = excluded.code, created_by = excluded.created_by,
            created_at = now(), expires_at = excluded.expires_at
      returning * into v_row;
      exit;
    exception when unique_violation then
      -- To konkurranser fikk samme kode (1 av 2^50): prøv en ny.
      if v_try >= 5 then
        raise;
      end if;
    end;
  end loop;

  return jsonb_build_object('competition_id', v_row.competition_id, 'code', v_row.code, 'expires_at', v_row.expires_at);
end;
$$;

-- --- Forhåndsvisningen: også klubbturneringer, med ledige navn ---------------------------
create or replace function public.competition_invite_preview(p_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_c       public.competitions;
  v_code    text := public.round_invite_normalize(p_code);
  v_entered boolean;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  select c.* into v_c
  from public.competition_invites i
  join public.competitions c on c.id = i.competition_id
  where i.code = v_code and i.expires_at > now();
  if not found then
    raise exception 'Fant ingen konkurranse med den koden. Den kan ha gått ut.' using errcode = 'P0002';
  end if;

  v_entered := exists (select 1 from public.competition_participants cp
                       where cp.competition_id = v_c.id and cp.status = 'active'
                         and (cp.profile_id = auth.uid() or cp.member_id = any (public.my_member_ids())));
  -- Blokkert (025): som en ukjent kode. Sjekkes før «ferdig», så svaret ikke
  -- røper at koden finnes.
  if not v_entered and v_c.club_id is null and v_c.owner_id is not null
     and public.blocked_between(v_c.owner_id) then
    raise exception 'Fant ingen konkurranse med den koden. Den kan ha gått ut.' using errcode = 'P0002';
  end if;
  if v_c.status = 'finished' then
    raise exception 'Konkurransen er ferdig' using errcode = '55000';
  end if;

  return jsonb_build_object(
    'competition_id', v_c.id,
    'name',           v_c.name,
    'kind',           v_c.kind,
    'owner_name',     (select p.display_name from public.profiles p where p.id = v_c.owner_id),
    'entrants',       (select count(*) from public.competition_participants cp
                       where cp.competition_id = v_c.id and cp.status = 'active'),
    'entered',        v_entered,
    -- 060
    'club_name',      (select cl.name from public.clubs cl where cl.id = v_c.club_id),
    'open_names',     case when v_c.club_id is null or v_entered then '[]'::jsonb else coalesce((
                        select jsonb_agg(jsonb_build_object('member_id', m.id, 'display_name', m.display_name)
                                         order by m.display_name)
                          from public.competition_participants cp
                          join public.club_members m on m.id = cp.member_id
                         where cp.competition_id = v_c.id and cp.status = 'active'
                           and m.user_id is null and m.status = 'active' and m.kind = 'participant'), '[]'::jsonb) end
  );
end;
$$;

-- --- Bli med: også klubbturneringer, og ta et ledig navn -------------------------------------
drop function if exists public.claim_competition_invite(text);
create or replace function public.claim_competition_invite(p_code text, p_member_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me     public.profiles;
  v_c      public.competitions;
  v_code   text := public.round_invite_normalize(p_code);
  v_row    public.competition_participants;
  v_mine   uuid;
  v_other  public.club_members;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  select c.* into v_c
  from public.competition_invites i
  join public.competitions c on c.id = i.competition_id
  where i.code = v_code and i.expires_at > now();
  if not found then
    raise exception 'Fant ingen konkurranse med den koden. Den kan ha gått ut.' using errcode = 'P0002';
  end if;
  -- Lås konkurransen, så trekningen og påmeldingen ikke krysser hverandre.
  select * into v_c from public.competitions c where c.id = v_c.id for update;
  v_me := public.ensure_profile();

  -- --- Uten klubb: som i 022 og 025 -------------------------------------------------
  if v_c.club_id is null then
    select * into v_row from public.competition_participants cp
    where cp.competition_id = v_c.id and cp.profile_id = v_me.id;
    if v_row.id is not null and v_row.status = 'active' then
      return jsonb_build_object('competition_id', v_c.id, 'participant_id', v_row.id, 'joined', 'already');
    end if;
    if v_c.owner_id is not null and public.blocked_between(v_c.owner_id) then
      raise exception 'Du kan ikke bli med i denne konkurransen' using errcode = 'DDB01';
    end if;
    if v_c.status = 'finished' then
      raise exception 'Konkurransen er ferdig' using errcode = '55000';
    end if;
    if v_c.kind = 'cup' and exists (select 1 from public.competition_matches where competition_id = v_c.id) then
      raise exception 'Cupen er trukket. Spør eieren.' using errcode = '55000';
    end if;
    if v_row.id is not null then
      update public.competition_participants set status = 'active' where id = v_row.id returning * into v_row;
      return jsonb_build_object('competition_id', v_c.id, 'participant_id', v_row.id, 'joined', 'rejoined');
    end if;
    insert into public.competition_participants (competition_id, profile_id)
    values (v_c.id, v_me.id) returning * into v_row;
    return jsonb_build_object('competition_id', v_c.id, 'participant_id', v_row.id, 'joined', 'new');
  end if;

  -- --- Klubbturnering (060) ---------------------------------------------------------
  v_mine := private.my_club_row_id(v_c.club_id);
  if v_mine is not null then
    select * into v_row from public.competition_participants cp
    where cp.competition_id = v_c.id and cp.member_id = v_mine;
    if v_row.id is not null and v_row.status = 'active' then
      return jsonb_build_object('competition_id', v_c.id, 'participant_id', v_row.id, 'joined', 'already');
    end if;
  end if;
  if v_c.status = 'finished' then
    raise exception 'Turneringen er ferdig' using errcode = '55000';
  end if;
  if v_c.kind = 'cup' and exists (select 1 from public.competition_matches where competition_id = v_c.id) then
    raise exception 'Cupen er trukket. Spør arrangøren.' using errcode = '55000';
  end if;

  if v_mine is not null then
    if v_row.id is not null then
      update public.competition_participants set status = 'active' where id = v_row.id returning * into v_row;
      return jsonb_build_object('competition_id', v_c.id, 'participant_id', v_row.id, 'joined', 'rejoined');
    end if;
    insert into public.competition_participants (competition_id, member_id)
    values (v_c.id, v_mine) returning * into v_row;
    return jsonb_build_object('competition_id', v_c.id, 'participant_id', v_row.id, 'joined', 'new');
  end if;

  if p_member_id is not null then
    -- Én rad per innlogging i klubben: har du en ventende eller arkivert rad, må arrangøren ordne det.
    select * into v_other from public.club_members m
     where m.club_id = v_c.club_id and m.user_id = auth.uid();
    if found then
      raise exception 'Du har allerede en rad i klubben. Spør arrangøren.' using errcode = '55000';
    end if;
    update public.club_members m
       set user_id = auth.uid()
     where m.id = p_member_id and m.club_id = v_c.club_id
       and m.user_id is null and m.status = 'active' and m.kind = 'participant'
       and exists (select 1 from public.competition_participants cp
                    where cp.competition_id = v_c.id and cp.member_id = m.id and cp.status = 'active');
    if not found then
      raise exception 'Navnet er tatt eller finnes ikke lenger' using errcode = '55000';
    end if;
    select * into v_row from public.competition_participants cp
     where cp.competition_id = v_c.id and cp.member_id = p_member_id;
    return jsonb_build_object('competition_id', v_c.id, 'participant_id', v_row.id, 'joined', 'claimed');
  end if;

  -- Ny deltaker: profilen meldes på, og 059-triggeren lager deltakerraden.
  insert into public.competition_participants (competition_id, profile_id)
  values (v_c.id, v_me.id) returning * into v_row;
  return jsonb_build_object('competition_id', v_c.id, 'participant_id', v_row.id, 'joined', 'new');
end;
$$;
revoke all on function public.claim_competition_invite(text, uuid) from public, anon;
grant execute on function public.claim_competition_invite(text, uuid) to authenticated;

-- --- Klubbkoden viser bare ledige medlemsnavn -----------------------------------------
-- Som i 001. Ledige deltakerrader (over) tas med turneringens lenke, ikke klubbkoden
-- (join_club tar bare kind = member, 059).
create or replace function public.club_preview(p_join_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_club  public.clubs%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  select * into v_club from public.clubs c where c.join_code = upper(btrim(p_join_code));
  if not found then
    return null;
  end if;

  return jsonb_build_object(
    'club_id', v_club.id,
    'name', v_club.name,
    'my_status', (select m.status from public.club_members m
                  where m.club_id = v_club.id and m.user_id = auth.uid()),
    'open_members', coalesce((
      select jsonb_agg(jsonb_build_object('id', m.id, 'display_name', m.display_name)
                       order by m.display_name)
      from public.club_members m
      where m.club_id = v_club.id and m.user_id is null and m.status = 'active'
        and m.kind = 'member'   -- 060
    ), '[]'::jsonb)
  );
end;
$$;

commit;

-- --- Kontroll (les) ------------------------------------------------------------
-- select proname, pg_get_function_identity_arguments(oid) from pg_proc
--  where proname in ('add_competition_participants', 'claim_competition_invite',
--                    'competition_invite', 'competition_invite_preview');      -- 4 rader, claim med (text, uuid)
-- select has_function_privilege('anon', 'public.add_competition_participants(uuid, jsonb)', 'execute');  -- false
-- select has_function_privilege('anon', 'public.claim_competition_invite(text, uuid)', 'execute');       -- false
-- select prosrc like '%open_names%' from pg_proc where proname = 'competition_invite_preview';         -- true

-- --- Rullebakk -------------------------------------------------------------------
-- begin;
-- drop function if exists public.add_competition_participants(uuid, jsonb);
-- drop function if exists public.claim_competition_invite(text, uuid);
-- -- Kjør claim_competition_invite(text), competition_invite og competition_invite_preview fra
-- -- 022_konkurranser.sql (med endringene i 025) på nytt.
-- commit;
-- Ledige deltakerrader som er lagt inn, blir stående (slett dem i Troppen ved behov).
