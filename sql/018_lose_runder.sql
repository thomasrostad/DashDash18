-- ===========================================================================
-- 018 – LØSE RUNDER MED VENNER (FASE 13) – FORSLAG, IKKE KJØRT
-- ===========================================================================
-- Status: FORSLAG til godkjenning (ROADMAP B5). Ikke kjørt mot Supabase, verken
-- test eller prod. Prøvd lokalt (lokal/018_prove.sql). Krever 001–017.
-- Nummer: 019 er satt av til banerettelser, 020 til fase 14 og 021 til fase 16.
--
-- Hvorfor (docs/visjon-apen-app.md, fase 13, og docs/datamodell-v2.md kap. 5):
-- «Ny runde» med venner på sekunder, invitasjon med lenke eller QR, gjester
-- med bare navn, og en bane fra det felles biblioteket. 017 la grunnmuren
-- (løse runder, deltakere og gjester, felles bibliotek og RLS). Denne fila
-- legger til det appen trenger for å bruke den:
--
--   * round_invites: én kode per løs runde (10 tegn, Crockford base32, 50
--     bit tilfeldighet, utløper etter 7 dager). Lenken er
--     dashdash://runde/<KODE>. Bare den som er med i runden, ser koden.
--   * loose_round_invite(runde): koden for runden (lages eller fornyes).
--   * round_invite_preview(kode): hva du blir med i: banen, eieren og hvem som
--     står på lista, med gjesteplassene («Er du Per?»).
--   * claim_round_invite(kode, plass): blir med i én transaksjon. Med plass:
--     gjesteplassen kobles til profilen din. Uten: du legges til som ny
--     deltaker. Er du med fra før, skjer ingenting.
--   * start_loose_round(oppsett): ny løs runde med deltakere, flighter,
--     markører, matcher, handicapandel og sidepremier, startet, i ett kall.
--     (create_loose_round fra 017 står, men tar ikke oppsettet.)
--   * finish_loose_round(runde): eieren avslutter (låser) runden, og koden
--     slettes.
--   * confirm_round_par: virker også i løse runder (eieren, eller en deltaker
--     etter samme regel som 014). For klubbrunder er den uendret.
--   * save_library_course: ny eller endret bane i det felles biblioteket med
--     alle hullene i én transaksjon (save_course fra 002 er bare for klubber).
--
-- Trusselmodellen (datamodell-v2 kap. 2) står: en fremmed kommer bare inn i
-- en runde med koden, og koden ser bare de som er med. Koden kan ikke gjettes
-- (50 bit), utløper, og slettes når runden avsluttes. Forhåndsvisningen viser
-- navnene i runden til den som har koden; det er det eieren deler.
--
-- Mønsteret fra 001–017 følges: én transaksjon, idempotent, `set search_path
-- = ''`, `revoke … from public, anon` ETTER hver create or replace.
-- ===========================================================================

begin;


-- ===========================================================================
-- 1. INVITASJONSKODER
-- ===========================================================================
create table if not exists public.round_invites (
  round_id    uuid primary key references public.rounds(id) on delete cascade,
  -- Crockford base32 uten I, L, O og U: 10 tegn = 50 bit.
  code        text not null unique check (code ~ '^[0-9A-HJKMNP-TV-Z]{10}$'),
  created_by  uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null
);
comment on table public.round_invites is
  'Invitasjonskoden til en løs runde (dashdash://runde/<kode>). Skrives bare av RPC-ene.';

alter table public.round_invites enable row level security;
drop policy if exists round_invites_select on public.round_invites;
-- Eieren og deltakerne (profiler) ser koden, så de kan dele den videre.
create policy round_invites_select on public.round_invites
  for select to authenticated
  using (public.is_round_organizer(round_id) or public.is_round_participant(round_id));
revoke all on table public.round_invites from public, anon, authenticated;
grant select on table public.round_invites to authenticated;

-- Ny kode: 10 tegn fra 10 tilfeldige byte (gen_random_uuid er kryptografisk
-- tilfeldig). Byte 6 og 8 i en uuid har faste versjons- og variantbit, så de
-- hoppes over. Hvert tegn bruker de 5 laveste bitene.
create or replace function public.round_invite_code()
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_alphabet constant text := '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  v_bytes    bytea := uuid_send(gen_random_uuid());
  v_code     text := '';
  v_pos      integer;
begin
  foreach v_pos in array array[0, 1, 2, 3, 4, 5, 9, 10, 11, 12] loop
    v_code := v_code || substr(v_alphabet, (get_byte(v_bytes, v_pos) % 32) + 1, 1);
  end loop;
  return v_code;
end;
$$;
revoke all on function public.round_invite_code() from public, anon, authenticated;

-- Koden slik den skrives inn: store bokstaver, uten mellomrom og bindestrek,
-- og O → 0, I/L → 1 (Crockford). Tom tekst gir null.
create or replace function public.round_invite_normalize(p_code text)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(translate(upper(regexp_replace(coalesce(p_code, ''), '[[:space:]-]', '', 'g')), 'OIL', '011'), '');
$$;
revoke all on function public.round_invite_normalize(text) from public, anon, authenticated;


-- --- loose_round_invite: koden til runden ------------------------------------
-- Eieren eller en deltaker (profil). Gir koden som finnes, eller lager en ny
-- når den mangler eller har gått ut. Ikke for avsluttede runder.
-- Returnerer {round_id, code, expires_at}.
create or replace function public.loose_round_invite(p_round_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_round  public.rounds%rowtype;
  v_row    public.round_invites%rowtype;
  v_try    integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  select * into v_round from public.rounds r where r.id = p_round_id for update;
  if not found or v_round.club_id is not null
     or not (v_round.owner_id = auth.uid() or public.is_round_participant(p_round_id)) then
    raise exception 'Fant ikke runden' using errcode = 'P0002';
  end if;
  if v_round.status = 'locked' then
    raise exception 'Runden er avsluttet' using errcode = '55000';
  end if;

  perform public.ensure_profile();

  select * into v_row from public.round_invites i where i.round_id = p_round_id;
  if found and v_row.expires_at > now() then
    return jsonb_build_object('round_id', v_row.round_id, 'code', v_row.code, 'expires_at', v_row.expires_at);
  end if;

  loop
    v_try := v_try + 1;
    begin
      insert into public.round_invites as i (round_id, code, created_by, expires_at)
      values (p_round_id, public.round_invite_code(), auth.uid(), now() + interval '7 days')
      on conflict (round_id) do update
        set code = excluded.code, created_by = excluded.created_by,
            created_at = now(), expires_at = excluded.expires_at
      returning * into v_row;
      exit;
    exception when unique_violation then
      -- To runder fikk samme kode (1 av 2^50): prøv en ny.
      if v_try >= 5 then
        raise;
      end if;
    end;
  end loop;

  return jsonb_build_object('round_id', v_row.round_id, 'code', v_row.code, 'expires_at', v_row.expires_at);
end;
$$;
revoke all on function public.loose_round_invite(uuid) from public, anon;
grant execute on function public.loose_round_invite(uuid) to authenticated;


-- --- round_invite_preview: hva du blir med i ---------------------------------
-- Alle innloggede som har koden. Gir banen, eieren, statusen og deltakerne
-- (navn, og om plassen er en gjest uten profil; eieren først, så profilene,
-- så gjestene), pluss plassen din om du er med fra før. P0002 = ukjent eller utgått kode, 55000 = runden er avsluttet.
create or replace function public.round_invite_preview(p_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_round  public.rounds%rowtype;
  v_code   text := public.round_invite_normalize(p_code);
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  select r.* into v_round
  from public.round_invites i
  join public.rounds r on r.id = i.round_id
  where i.code = v_code and i.expires_at > now() and r.club_id is null;
  if not found then
    raise exception 'Fant ingen runde med den koden. Den kan ha gått ut.' using errcode = 'P0002';
  end if;
  if v_round.status = 'locked' then
    raise exception 'Runden er avsluttet' using errcode = '55000';
  end if;

  return jsonb_build_object(
    'round_id',    v_round.id,
    'status',      v_round.status,
    'hole_count',  v_round.hole_count,
    'first_hole',  v_round.first_hole,
    'format',      v_round.format,
    'venue',       v_round.venue,
    'started_at',  v_round.started_at,
    'course_name', (select c.name from public.courses c where c.id = v_round.course_id),
    'owner_name',  (select p.display_name from public.profiles p where p.id = v_round.owner_id),
    'my_participant_id', (select pa.id from public.round_participants pa
                          where pa.round_id = v_round.id and pa.profile_id = auth.uid()),
    'players', coalesce((
      select jsonb_agg(jsonb_build_object(
               'participant_id', pa.id,
               'display_name',   coalesce(pf.display_name, pa.display_name),
               'is_guest',       pa.profile_id is null)
             -- Eieren først, så profilene, så gjestene, hver for seg etter navn.
             order by pa.profile_id is not distinct from v_round.owner_id desc, pa.profile_id is null,
                      lower(coalesce(pf.display_name, pa.display_name)), pa.id)
      from public.round_participants pa
      left join public.profiles pf on pf.id = pa.profile_id
      where pa.round_id = v_round.id), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.round_invite_preview(text) from public, anon;
grant execute on function public.round_invite_preview(text) to authenticated;


-- --- claim_round_invite: bli med ----------------------------------------------
-- Én transaksjon. Er du med fra før: ingenting skjer. Med p_participant_id:
-- gjesteplassen kobles til profilen din («Er du Per?»), med handicapet fra
-- profilen når gjesten ikke hadde noe. Uten: du legges til som ny deltaker,
-- i en egen flight når runden har flighter, så du fører ditt eget kort.
-- Returnerer {round_id, participant_id, joined: already | guest | new}.
create or replace function public.claim_round_invite(p_code text, p_participant_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me     public.profiles;
  v_round  public.rounds%rowtype;
  v_code   text := public.round_invite_normalize(p_code);
  v_part   public.round_participants%rowtype;
  v_id     uuid;
  v_bay    integer;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  select r.* into v_round
  from public.round_invites i
  join public.rounds r on r.id = i.round_id
  where i.code = v_code and i.expires_at > now() and r.club_id is null;
  if not found then
    raise exception 'Fant ingen runde med den koden. Den kan ha gått ut.' using errcode = 'P0002';
  end if;
  -- Lås runden, så to som blir med samtidig ikke tar samme plass eller flight.
  select * into v_round from public.rounds r where r.id = v_round.id for update;
  if v_round.status = 'locked' then
    raise exception 'Runden er avsluttet' using errcode = '55000';
  end if;

  v_me := public.ensure_profile();

  select pa.id into v_id from public.round_participants pa
  where pa.round_id = v_round.id and pa.profile_id = v_me.id;
  if v_id is not null then
    return jsonb_build_object('round_id', v_round.id, 'participant_id', v_id, 'joined', 'already');
  end if;

  if p_participant_id is not null then
    select * into v_part from public.round_participants pa
    where pa.id = p_participant_id and pa.round_id = v_round.id
    for update;
    if not found then
      raise exception 'Fant ikke plassen i runden' using errcode = 'P0002';
    end if;
    if v_part.profile_id is not null then
      raise exception 'Plassen er allerede tatt av en annen' using errcode = '55000';
    end if;

    update public.round_participants
       set profile_id = v_me.id,
           handicap_index = coalesce(handicap_index, v_me.handicap_index)
     where id = v_part.id;
    -- Handicapet er frosset ved start. En gjest uten handicap får profilens.
    update public.round_players rp
       set handicap_index = coalesce(rp.handicap_index, v_me.handicap_index)
     where rp.round_id = v_round.id and rp.member_id = v_part.id;
    return jsonb_build_object('round_id', v_round.id, 'participant_id', v_part.id, 'joined', 'guest');
  end if;

  if (select count(*) from public.round_participants pa where pa.round_id = v_round.id) >= 48 then
    raise exception 'Runden er full' using errcode = '55000';
  end if;

  insert into public.round_participants (round_id, profile_id, display_name)
  values (v_round.id, v_me.id, coalesce(v_me.display_name, 'Spiller'))
  returning id into v_id;

  -- Har runden flighter, får du en egen (du fører selv). Høyst 12 (skjemaet).
  select max(rp.bay_no) + 1 into v_bay from public.round_players rp where rp.round_id = v_round.id;
  if v_bay is not null and v_bay <= 12 then
    update public.round_players rp set bay_no = v_bay
     where rp.round_id = v_round.id and rp.member_id = v_id;
  end if;

  return jsonb_build_object('round_id', v_round.id, 'participant_id', v_id, 'joined', 'new');
end;
$$;
revoke all on function public.claim_round_invite(text, uuid) from public, anon;
grant execute on function public.claim_round_invite(text, uuid) to authenticated;


-- ===========================================================================
-- 2. NY LØS RUNDE MED OPPSETT, I ETT KALL
-- ===========================================================================
-- p_setup (jsonb):
--   course_id, hole_count, first_hole, format, venue, handicap_allowance,
--   external_handicap, ld_enabled, ld_hole_index, kp_enabled, kp_hole_index,
--   me:      {bay_no, is_marker}                         – plassen din
--   players: [{profile_id} | {guest_name, handicap_index}, + bay_no, is_marker]
--   matches: [{a, b, c}]  – indekser i deltakerlista (0 = deg, 1… = players)
--   start:   true (standard) starter runden, fryser handicapet og bekrefter
--            parene (du valgte banen fra biblioteket).
-- Regelverdiene (andel, sidepremier, form) kommer fra appens regelsett; her
-- står bare skjemaets standard når de mangler.
-- Returnerer {round_id, status, participants: [{id, profile_id, display_name}]}
-- i samme rekkefølge som deltakerlista (du først).
create or replace function public.start_loose_round(p_setup jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me       public.profiles;
  v_round    uuid;
  v_players  jsonb;
  v_entry    jsonb;
  v_seats    jsonb := '[]'::jsonb;
  v_ids      uuid[] := '{}';
  v_prof     uuid;
  v_name     text;
  v_id       uuid;
  v_i        integer;
  v_m        jsonb;
  v_no       integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if jsonb_typeof(p_setup) is distinct from 'object' then
    raise exception 'Oppsettet mangler' using errcode = '22023';
  end if;
  v_players := coalesce(p_setup -> 'players', '[]'::jsonb);
  if jsonb_typeof(v_players) <> 'array' or jsonb_typeof(coalesce(p_setup -> 'matches', '[]'::jsonb)) <> 'array' then
    raise exception 'Spillerlista og matchlista må være lister' using errcode = '22023';
  end if;
  if jsonb_array_length(v_players) > 47 then
    raise exception 'For mange spillere i én runde' using errcode = '22023';
  end if;

  v_me := public.ensure_profile();

  insert into public.rounds (club_id, event_id, course_id, hole_count, first_hole, format, venue,
                             handicap_allowance, external_handicap, ld_enabled, ld_hole_index,
                             kp_enabled, kp_hole_index, status)
  values (null, null, (p_setup ->> 'course_id')::uuid,
          coalesce((p_setup ->> 'hole_count')::smallint, 18),
          coalesce((p_setup ->> 'first_hole')::smallint, 1),
          coalesce(p_setup ->> 'format', 'stableford'),
          coalesce(p_setup ->> 'venue', 'simulator'),
          coalesce((p_setup ->> 'handicap_allowance')::numeric, 1),
          coalesce((p_setup ->> 'external_handicap')::boolean, false),
          coalesce((p_setup ->> 'ld_enabled')::boolean, true),
          (p_setup ->> 'ld_hole_index')::smallint,
          coalesce((p_setup ->> 'kp_enabled')::boolean, true),
          (p_setup ->> 'kp_hole_index')::smallint,
          'draft')
  returning id into v_round;

  -- Deg først, så lista i rekkefølge. Indeksene i matchene peker hit.
  insert into public.round_participants (round_id, profile_id, display_name)
  values (v_round, v_me.id, coalesce(v_me.display_name, 'Meg'))
  returning id into v_id;
  v_ids := v_ids || v_id;
  v_seats := v_seats || jsonb_build_array(coalesce(p_setup -> 'me', '{}'::jsonb));

  for v_entry in select value from jsonb_array_elements(v_players) loop
    v_prof := nullif(v_entry ->> 'profile_id', '')::uuid;
    if v_prof is not null then
      if v_prof = v_me.id then
        raise exception 'Du står allerede først på lista' using errcode = '22023';
      end if;
      if not public.can_see_profile(v_prof) then
        raise exception 'Du kan bare legge til folk du kjenner fra en klubb, runde eller konkurranse'
          using errcode = '42501';
      end if;
      select p.display_name into v_name from public.profiles p where p.id = v_prof;
      insert into public.round_participants (round_id, profile_id, display_name)
      values (v_round, v_prof, coalesce(v_name, 'Spiller'))
      returning id into v_id;
    else
      v_name := btrim(coalesce(v_entry ->> 'guest_name', ''));
      if v_name = '' then
        raise exception 'En gjest må ha et navn' using errcode = '22023';
      end if;
      insert into public.round_participants (round_id, display_name, handicap_index)
      values (v_round, v_name, (v_entry ->> 'handicap_index')::numeric)
      returning id into v_id;
    end if;
    v_ids := v_ids || v_id;
    v_seats := v_seats || jsonb_build_array(v_entry);
  end loop;

  -- Flight og markør per deltaker (én markør per flight, sjekket av indeksen fra 001).
  for v_i in 1 .. cardinality(v_ids) loop
    update public.round_players rp
       set bay_no = (v_seats -> (v_i - 1) ->> 'bay_no')::smallint,
           is_marker = coalesce((v_seats -> (v_i - 1) ->> 'is_marker')::boolean, false)
     where rp.round_id = v_round and rp.member_id = v_ids[v_i];
  end loop;

  -- Matcher med indekser i deltakerlista. En indeks utenfor lista gir null, og
  -- da stopper sjekken på round_matches (minst to spillere).
  for v_m in select value from jsonb_array_elements(coalesce(p_setup -> 'matches', '[]'::jsonb)) loop
    v_no := v_no + 1;
    insert into public.round_matches (round_id, match_no, player_a, player_b, player_c)
    values (v_round, v_no,
            v_ids[(v_m ->> 'a')::integer + 1],
            v_ids[(v_m ->> 'b')::integer + 1],
            v_ids[(v_m ->> 'c')::integer + 1]);
  end loop;

  if coalesce((p_setup ->> 'start')::boolean, true) then
    -- rounds_freeze_participants (017) fryser handicapet.
    update public.rounds set status = 'active', par_confirmed_at = now() where id = v_round;
  end if;

  return jsonb_build_object(
    'round_id', v_round,
    'status', (select r.status from public.rounds r where r.id = v_round),
    'participants', (select jsonb_agg(jsonb_build_object('id', p.id, 'profile_id', p.profile_id,
                                                         'display_name', p.display_name)
                                      order by array_position(v_ids, p.id))
                     from public.round_participants p where p.round_id = v_round)
  );
end;
$$;
revoke all on function public.start_loose_round(jsonb) from public, anon;
grant execute on function public.start_loose_round(jsonb) to authenticated;


-- --- finish_loose_round: eieren avslutter runden -----------------------------
-- Låser runden (tidspunktet settes av rounds_before_write) og sletter koden.
-- Avsluttet fra før: gir tidspunktet. Returnerer locked_at.
create or replace function public.finish_loose_round(p_round_id uuid)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_round public.rounds%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select * into v_round from public.rounds r where r.id = p_round_id for update;
  if not found or v_round.club_id is not null or not public.can_read_round(p_round_id) then
    raise exception 'Fant ikke runden' using errcode = 'P0002';
  end if;
  if v_round.owner_id is distinct from auth.uid() then
    raise exception 'Bare den som startet runden, kan avslutte den' using errcode = '42501';
  end if;

  delete from public.round_invites i where i.round_id = p_round_id;
  if v_round.status = 'locked' then
    return v_round.locked_at;
  end if;
  update public.rounds set status = 'locked' where id = p_round_id
  returning locked_at into v_round.locked_at;
  return v_round.locked_at;
end;
$$;
revoke all on function public.finish_loose_round(uuid) from public, anon;
grant execute on function public.finish_loose_round(uuid) to authenticated;


-- ===========================================================================
-- 3. PAR-BEKREFTELSEN I LØSE RUNDER
-- ===========================================================================
-- Som 014 for klubbrunder (uendret). I en løs runde har eieren arrangørens
-- rett, og «meg i runden» er deltakeren med profilen min. par_confirmed_by
-- peker på et klubbmedlem og står tom i løse runder.
create or replace function public.confirm_round_par(p_round_id uuid)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_round   public.rounds%rowtype;
  v_member  uuid;
  v_boss    boolean;
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

  if v_round.club_id is null then
    select pa.id into v_member from public.round_participants pa
    where pa.round_id = p_round_id and pa.profile_id = auth.uid();
    v_boss := v_round.owner_id is not distinct from auth.uid();
  else
    v_member := public.my_member_id(v_round.club_id);
    v_boss := public.is_club_organizer(v_round.club_id);
  end if;

  if not v_boss then
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
       set par_confirmed_by = case when v_round.club_id is null then null else v_member end,
           par_confirmed_at = now()
     where id = p_round_id;
    return now();
  end if;
  return v_round.par_confirmed_at;
end;
$$;
revoke all on function public.confirm_round_par(uuid) from public, anon;
grant execute on function public.confirm_round_par(uuid) to authenticated;


-- ===========================================================================
-- 4. FELLES BANEBIBLIOTEK: LAGRE BANE OG HULL I ÉN TRANSAKSJON
-- ===========================================================================
-- Som save_course (002), men for det felles biblioteket. SECURITY INVOKER:
-- RLS fra 017 avgjør (alle kan legge inn, bare den som la inn en bane uten
-- kilde, kan endre den). p_course_id null = ny bane. p_holes:
-- [{hole_number, par, stroke_index, length_m}], 9 eller 18. Hull som ikke står
-- i lista, slettes. Returnerer banens id.
create or replace function public.save_library_course(
  p_course_id      uuid,
  p_name           text,
  p_kind           text,
  p_course_rating  numeric,
  p_slope_rating   smallint,
  p_holes          jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_holes, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_holes, '[]'::jsonb)) not in (9, 18) then
    raise exception 'En bane i biblioteket har 9 eller 18 hull med par' using errcode = '22023';
  end if;

  perform public.ensure_profile();

  if p_course_id is null then
    insert into public.courses (club_id, name, kind, course_rating, slope_rating, in_use)
    values (null, btrim(p_name), coalesce(p_kind, 'course'), p_course_rating, p_slope_rating, true)
    returning id into v_id;
  else
    update public.courses
       set name = btrim(p_name),
           kind = coalesce(p_kind, kind),
           course_rating = p_course_rating,
           slope_rating = p_slope_rating
     where id = p_course_id and club_id is null
    returning id into v_id;
    if v_id is null then
      raise exception 'Bare den som la inn banen, kan endre den' using errcode = '42501';
    end if;
  end if;

  delete from public.course_holes h
   where h.course_id = v_id
     and h.hole_number not in (
       select (e ->> 'hole_number')::smallint from jsonb_array_elements(p_holes) e);

  insert into public.course_holes (course_id, hole_number, par, stroke_index, length_m)
  select v_id,
         (e ->> 'hole_number')::smallint,
         (e ->> 'par')::smallint,
         (e ->> 'stroke_index')::smallint,
         (e ->> 'length_m')::smallint
    from jsonb_array_elements(p_holes) e
  on conflict (course_id, hole_number) do update
     set par = excluded.par,
         stroke_index = excluded.stroke_index,
         length_m = excluded.length_m;

  return v_id;
end;
$$;
revoke all on function public.save_library_course(uuid, text, text, numeric, smallint, jsonb) from public, anon;
grant execute on function public.save_library_course(uuid, text, text, numeric, smallint, jsonb) to authenticated;

commit;


-- ===========================================================================
-- KONTROLL (kjør i SQL Editor etter fila, som én kjøring). Én rad per sjekk,
-- alle skal ha ok = true.
-- ===========================================================================
-- with f as (
--   select p.proname,
--          has_function_privilege('anon', p.oid, 'execute') as anon_kan,
--          has_function_privilege('authenticated', p.oid, 'execute') as auth_kan
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public'
--     and p.proname in ('round_invite_code', 'round_invite_normalize', 'loose_round_invite',
--                       'round_invite_preview', 'claim_round_invite', 'start_loose_round',
--                       'finish_loose_round', 'confirm_round_par', 'save_library_course'))
-- select 1 as nr, 'round_invites finnes med RLS' as sjekk,
--        coalesce((select relrowsecurity from pg_class where oid = 'public.round_invites'::regclass), false) as ok
-- union all
-- select 2, 'anon har ingen rettigheter på round_invites',
--        not exists (select 1 from information_schema.role_table_grants
--                    where table_schema = 'public' and table_name = 'round_invites'
--                      and grantee in ('anon', 'PUBLIC'))
-- union all
-- select 3, 'authenticated kan bare lese round_invites (RPC-ene skriver)',
--        (select coalesce(array_agg(privilege_type::text order by privilege_type::text), '{}')
--         from information_schema.role_table_grants
--         where table_schema = 'public' and table_name = 'round_invites' and grantee = 'authenticated') = array['SELECT']
-- union all
-- select 4, 'Alle ni funksjonene finnes', (select count(*) = 9 from f)
-- union all
-- select 5, 'anon kan ikke kjøre noen av dem', not exists (select 1 from f where anon_kan)
-- union all
-- select 6, 'authenticated kan kjøre de 7 RPC-ene, ikke kodelageren og normaliseringen',
--        (select count(*) filter (where auth_kan) = 7
--            and bool_and(not auth_kan) filter (where proname in ('round_invite_code', 'round_invite_normalize'))
--         from f)
-- union all
-- select 7, 'Kodene har riktig form (10 tegn Crockford base32)',
--        (select bool_and(public.round_invite_code() ~ '^[0-9A-HJKMNP-TV-Z]{10}$') from generate_series(1, 200))
-- union all
-- select 8, 'Normaliseringen tåler mellomrom, bindestrek, små bokstaver, O, I og L',
--        public.round_invite_normalize(' abcde-fghil o ') = 'ABCDEFGH110'
-- union all
-- select 9, 'Ingen klubbrunde har en invitasjonskode',
--        not exists (select 1 from public.round_invites i join public.rounds r on r.id = i.round_id
--                    where r.club_id is not null)
-- union all
-- select 10, 'round_invites er ikke med i realtime (koden skal ikke sendes rundt)',
--        not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime'
--                      and schemaname = 'public' and tablename = 'round_invites')
-- order by nr;


-- ===========================================================================
-- RULLEBAKKE (bare test). Fjerner kodene og RPC-ene fra 018. Løse runder og
-- baner som er laget, står (de hører til 017). Slå av LooseRoundsFeature i
-- appen først (den er av fra start).
-- ===========================================================================
-- begin;
-- drop function if exists public.save_library_course(uuid, text, text, numeric, smallint, jsonb);
-- drop function if exists public.finish_loose_round(uuid);
-- drop function if exists public.start_loose_round(jsonb);
-- drop function if exists public.claim_round_invite(text, uuid);
-- drop function if exists public.round_invite_preview(text);
-- drop function if exists public.loose_round_invite(uuid);
-- drop table if exists public.round_invites;
-- drop function if exists public.round_invite_normalize(text);
-- drop function if exists public.round_invite_code();
-- -- confirm_round_par tilbake til 014 (bare klubbrunder).
-- create or replace function public.confirm_round_par(p_round_id uuid)
-- returns timestamptz language plpgsql security definer set search_path = '' as $f$
-- declare
--   v_round public.rounds%rowtype; v_member uuid; v_bay integer; v_marker uuid;
-- begin
--   if auth.uid() is null then
--     raise exception 'Du må være logget inn' using errcode = '42501';
--   end if;
--   select * into v_round from public.rounds r where r.id = p_round_id for update;
--   if not found or not public.can_read_round(p_round_id) then
--     raise exception 'Fant ikke runden' using errcode = 'P0002';
--   end if;
--   v_member := public.my_member_id(v_round.club_id);
--   if not public.is_club_organizer(v_round.club_id) then
--     if v_round.status <> 'active' then
--       raise exception 'Runden er ikke i gang' using errcode = '55000';
--     end if;
--     if not exists (select 1 from public.round_players rp
--                    where rp.round_id = p_round_id and rp.member_id = v_member) then
--       raise exception 'Bare arrangøren eller en markør kan bekrefte parene' using errcode = '42501';
--     end if;
--     select rp.bay_no into v_bay from public.round_players rp
--      where rp.round_id = p_round_id and rp.member_id = v_member;
--     if v_bay is not null and v_bay >= 1 then
--       select rp.member_id into v_marker from public.round_players rp
--        where rp.round_id = p_round_id and rp.bay_no = v_bay and rp.is_marker limit 1;
--       if v_marker is not null and v_marker <> v_member then
--         raise exception 'Bare arrangøren eller en markør kan bekrefte parene' using errcode = '42501';
--       end if;
--     end if;
--   end if;
--   if v_round.par_confirmed_at is null then
--     update public.rounds set par_confirmed_by = v_member, par_confirmed_at = now() where id = p_round_id;
--     return now();
--   end if;
--   return v_round.par_confirmed_at;
-- end $f$;
-- revoke all on function public.confirm_round_par(uuid) from public, anon;
-- grant execute on function public.confirm_round_par(uuid) to authenticated;
-- commit;
