-- 059_deltakere.sql — deltakere i klubbturneringer (ikke medlemmer) og NGF-medlemsnummer.
-- Til godkjenning (retningen godkjent 20.10.2026). Ikke kjørt på test eller prod.
--
-- Bakgrunn: en spiller i en runde må stå i klubbens tropp (round_players → club_members). Den som
-- melder seg på en åpen klubbturnering uten å være medlem, ble bare `competition_participants.profile_id`
-- og kunne ikke settes i en runde. Nå skilles det mellom å være medlem i klubben og å være deltaker i en
-- turnering, og det er plass til NGF-medlemsnummeret (samme person på tvers av klubber og turneringer).
--
-- Hva som endres:
-- * club_members.kind: 'member' (som før) eller 'participant' (deltaker). Alle rader som finnes er 'member'.
-- * club_members.ngf_number og profiles.ngf_number: valgfritt NGF-medlemsnummer. Unikt per klubb
--   (blant rader som ikke er arkivert) og unikt per profil.
-- * Navn er unike bare blant medlemmene. En deltaker kan hete det samme som et medlem.
-- * Medlemskapet gjelder bare kind = 'member': is_club_member, my_member_id, owns_member,
--   is_club_organizer og private.has_club_right. En deltaker ser derfor ikke klubbens feed, tråd, tips,
--   kvelder eller andre turneringer, og kan ikke få roller.
-- * Det deltakeren trenger, er åpnet eksplisitt:
--   - turneringen og rundene (som før via is_competition_participant og can_read_round, som bruker
--     my_member_ids: alle aktive rader, også deltakere),
--   - navnene på spillerne i rundene og deltakerlistene den kan lese (club_members_select),
--   - banene rundene spilles på (courses, course_holes, course_tees),
--   - føre sitt eget kort (owns_round_player) og bekrefte par uten markør (confirm_round_par).
-- * Påmelding: en profil som meldes på en klubbturnering (competition_signup, ventelista, arrangøren)
--   blir deltaker i klubben av seg selv (trigger på competition_participants). Har profilen en aktiv rad i
--   klubben fra før (medlem eller deltaker), brukes den. Har den en ventende eller arkivert rad, blir den
--   stående som profil-deltaker som før.
-- * join_club: en deltaker som bruker klubbkoden, får beskjed om å be arrangøren gjøre ham til medlem
--   (én rad per innlogging i klubben). Arrangøren endrer kind i troppen.
-- * guard_club_members: bare arrangøren endrer kind.
-- * Påmeldte profiler i klubbturneringer (0 på test 20.10.2026) flyttes over til deltakere.
--
-- Ikke endret: løse runder (round_participants), turneringer uten klubb, spill og veddemål, sidepremier
-- (en deltaker kan ikke melde LD/KP selv ennå; arrangøren kan), og hvem som kan føre for andre (can_score).
--
-- Appen må lese kind (ClubModel viser bare medlemskap, Troppen viser deltakere for seg). Kjør denne før
-- appversjonen som leser kolonnen.
--
-- Krever 032, 044 og 058. Idempotent. Kontroll og rullebakk nederst.

begin;

-- --- Kolonnene ------------------------------------------------------------------
alter table public.club_members add column if not exists kind text not null default 'member';
alter table public.club_members add column if not exists ngf_number text;
alter table public.profiles add column if not exists ngf_number text;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'club_members_kind_check') then
    alter table public.club_members add constraint club_members_kind_check
      check (kind in ('member', 'participant'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'club_members_ngf_number_check') then
    alter table public.club_members add constraint club_members_ngf_number_check
      check (ngf_number ~ '^[0-9]{1,12}(-[0-9]{1,12})?$');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'profiles_ngf_number_check') then
    alter table public.profiles add constraint profiles_ngf_number_check
      check (ngf_number ~ '^[0-9]{1,12}(-[0-9]{1,12})?$');
  end if;
end $$;
comment on column public.club_members.kind is
  'member: medlem i klubben. participant: deltaker i en av klubbens turneringer, ser bare den (sql/059).';

comment on column public.club_members.ngf_number is 'NGF-medlemsnummer (valgfritt, sql/059).';
comment on column public.profiles.ngf_number is 'NGF-medlemsnummer (valgfritt, sql/059).';

create unique index if not exists club_members_unique_ngf
  on public.club_members (club_id, ngf_number) where ngf_number is not null and status <> 'archived';
create unique index if not exists profiles_unique_ngf
  on public.profiles (ngf_number) where ngf_number is not null;

-- Navn er unike blant medlemmene (det er navnet folk velger ved første innlogging).
drop index if exists public.club_members_unique_name;
create unique index club_members_unique_name
  on public.club_members (club_id, lower(btrim(display_name))) where status <> 'archived' and kind = 'member';

-- --- Medlemskapet gjelder bare medlemmer ----------------------------------------
create or replace function public.is_club_member(p_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.club_members m
    where m.club_id = p_club_id
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.kind = 'member'
  );
$$;

create or replace function public.my_member_id(p_club_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.id
  from public.club_members m
  where m.club_id = p_club_id
    and m.user_id = auth.uid()
    and m.status = 'active'
    and m.kind = 'member';
$$;

create or replace function public.owns_member(p_member_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.club_members m
    where m.id = p_member_id
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.kind = 'member'
  );
$$;

create or replace function public.is_club_organizer(p_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.club_members m
      join public.club_member_roles mr on mr.member_id = m.id
      join public.club_roles r on r.id = mr.role_id
     where m.club_id = p_club_id
       and m.user_id = (select auth.uid())
       and m.status = 'active'
       and m.kind = 'member'
       and (r.is_owner or r.rights && array['tournaments', 'rounds', 'members', 'money']::text[])
  );
$$;

create or replace function private.has_club_right(p_club uuid, p_right text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.club_members m
      join public.club_member_roles mr on mr.member_id = m.id
      join public.club_roles r on r.id = mr.role_id
     where m.club_id = p_club
       and m.user_id = (select auth.uid())
       and m.status = 'active'
       and m.kind = 'member'
       and (r.is_owner or p_right = any (r.rights))
  );
$$;

-- Raden din i klubben, medlem eller deltaker (for runder: hvem som førte, par-bekreftelsen).
create or replace function private.my_club_row_id(p_club_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.id
  from public.club_members m
  where m.club_id = p_club_id
    and m.user_id = auth.uid()
    and m.status = 'active';
$$;
revoke all on function private.my_club_row_id(uuid) from public, anon;
grant execute on function private.my_club_row_id(uuid) to authenticated;

-- --- Det deltakeren kan lese --------------------------------------------------
-- En rad i troppen kan leses av den som kan lese en runde raden spiller i, eller en
-- turnering raden er påmeldt.
create or replace function private.can_read_member(p_member_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.round_players rp
                  where rp.member_id = p_member_id and public.can_read_round(rp.round_id))
      or exists (select 1 from public.competition_participants cp
                  where cp.member_id = p_member_id and cp.status = 'active'
                    and public.can_read_competition(cp.competition_id));
$$;
revoke all on function private.can_read_member(uuid) from public, anon;
grant execute on function private.can_read_member(uuid) to authenticated;

-- En bane kan leses av den som kan lese en runde som spilles på den.
create or replace function private.can_read_course(p_course_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.rounds r
                  where r.course_id = p_course_id and public.can_read_round(r.id));
$$;
revoke all on function private.can_read_course(uuid) from public, anon;
grant execute on function private.can_read_course(uuid) to authenticated;

drop policy if exists club_members_select on public.club_members;
create policy club_members_select on public.club_members
  for select to authenticated
  using (public.is_club_member(club_id) or user_id = auth.uid() or private.can_read_member(id));

drop policy if exists courses_select on public.courses;
create policy courses_select on public.courses
  for select to authenticated
  using (public.is_club_member(club_id) or club_id is null or private.can_read_course(id));

drop policy if exists course_holes_select on public.course_holes;
create policy course_holes_select on public.course_holes
  for select to authenticated
  using (exists (select 1 from public.courses c
                  where c.id = course_holes.course_id
                    and (public.is_club_member(c.club_id) or c.club_id is null))
         or private.can_read_course(course_id));

drop policy if exists course_tees_select on public.course_tees;
create policy course_tees_select on public.course_tees
  for select to authenticated
  using (exists (select 1 from public.courses c
                  where c.id = course_tees.course_id
                    and (public.is_club_member(c.club_id) or c.club_id is null))
         or private.can_read_course(course_id));

-- --- Føre sitt eget kort ----------------------------------------------------------
create or replace function public.owns_round_player(p_round_id uuid, p_player_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.owns_member(p_player_id)
      or exists (select 1 from public.round_participants p
                 where p.id = p_player_id and p.round_id = p_round_id
                   and p.profile_id = auth.uid())
      -- 059: deltakeren i klubbrunden.
      or exists (select 1 from public.club_members m
                 join public.round_players rp on rp.member_id = m.id and rp.round_id = p_round_id
                 where m.id = p_player_id and m.user_id = auth.uid()
                   and m.status = 'active' and m.kind = 'participant');
$$;

create or replace function public.hole_scores_before_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_club        uuid;
  v_hole_count  smallint;
begin
  select r.club_id, r.hole_count into v_club, v_hole_count
  from public.rounds r where r.id = new.round_id;

  if new.hole_index >= v_hole_count then
    raise exception 'Hull % finnes ikke i en runde på % hull', new.hole_index + 1, v_hole_count
      using errcode = '22023';
  end if;

  -- En klokke som går foran skal ikke kunne sperre senere rettinger.
  if new.recorded_at > now() then
    new.recorded_at := now();
  end if;

  new.updated_at := now();
  new.updated_by := private.my_club_row_id(v_club);   -- null fra SQL Editor. 059: også deltakeren
  return new;
end;
$$;

-- --- Par-bekreftelsen: også deltakeren (som 058, én linje er ny) ---------------------
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
    v_member := private.my_club_row_id(v_round.club_id);   -- 059: også deltakeren
    v_boss := private.has_club_right(v_round.club_id, 'rounds');
  end if;

  -- 058: funksjonæren for en gruppe i runden (fortsatt i staben) bekrefter som en markør.
  if not v_boss and v_round.status = 'active'
     and exists (select 1 from public.round_start_groups g
                  where g.round_id = p_round_id and g.scorer_id = auth.uid())
     and public.is_round_staff(p_round_id) then
    v_boss := true;
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

-- --- Påmelding gjør profilen til deltaker -----------------------------------------
-- Raden i klubben for profilen: den aktive som finnes (medlem eller deltaker), ellers en ny
-- deltaker. nil når profilen har en ventende eller arkivert rad (da står den som profil som før).
create or replace function private.ensure_participant(p_club_id uuid, p_profile_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row   public.club_members;
  v_me    public.profiles;
  v_prev  text;
  v_id    uuid;
begin
  select * into v_row from public.club_members m
   where m.club_id = p_club_id and m.user_id = p_profile_id;
  if found then
    return case when v_row.status = 'active' then v_row.id end;
  end if;

  select * into v_me from public.profiles p where p.id = p_profile_id;
  if not found then
    return null;
  end if;

  v_prev := current_setting('dd18.participant_sync', true);
  perform set_config('dd18.participant_sync', 'on', true);
  insert into public.club_members (club_id, user_id, display_name, handicap_index, status, kind, ngf_number)
  values (p_club_id, p_profile_id,
          left(coalesce(nullif(btrim(v_me.display_name), ''), 'Deltaker'), 40),
          v_me.handicap_index, 'active', 'participant',
          case when v_me.ngf_number is not null
                and not exists (select 1 from public.club_members m
                                 where m.club_id = p_club_id and m.ngf_number = v_me.ngf_number
                                   and m.status <> 'archived')
               then v_me.ngf_number end)
  returning id into v_id;
  perform set_config('dd18.participant_sync', coalesce(v_prev, ''), true);
  return v_id;
end;
$$;
revoke all on function private.ensure_participant(uuid, uuid) from public, anon, authenticated;

create or replace function private.competition_participant_as_member()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_club    uuid;
  v_member  uuid;
begin
  if new.profile_id is null then
    return new;
  end if;
  select c.club_id into v_club from public.competitions c where c.id = new.competition_id;
  if v_club is null then
    return new;
  end if;
  v_member := private.ensure_participant(v_club, new.profile_id);
  if v_member is not null
     and not exists (select 1 from public.competition_participants p
                      where p.competition_id = new.competition_id and p.member_id = v_member
                        and p.id is distinct from new.id) then
    new.member_id := v_member;
    new.profile_id := null;
  end if;
  return new;
end;
$$;

drop trigger if exists competition_participants_as_member on public.competition_participants;
create trigger competition_participants_as_member
  before insert on public.competition_participants
  for each row execute function private.competition_participant_as_member();

-- Påmeldte profiler i klubbturneringer fra før.
update public.competition_participants cp
   set member_id = x.member_id, profile_id = null
  from (select p.id, private.ensure_participant(c.club_id, p.profile_id) as member_id
          from public.competition_participants p
          join public.competitions c on c.id = p.competition_id
         where p.profile_id is not null and c.club_id is not null) x
 where cp.id = x.id and x.member_id is not null
   and not exists (select 1 from public.competition_participants o
                    where o.competition_id = cp.competition_id and o.member_id = x.member_id);

-- --- Klubbkoden for en deltaker ---------------------------------------------------
create or replace function public.join_club(p_join_code text, p_member_id uuid default null,
                                            p_display_name text default null,
                                            p_handicap_index numeric default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_club    uuid;
  v_member  uuid;
  v_status  text;
  v_kind    text;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  select c.id into v_club from public.clubs c where c.join_code = upper(btrim(p_join_code));
  if v_club is null then
    raise exception 'Fant ingen klubb med den koden' using errcode = 'P0002';
  end if;

  select m.id, m.status, m.kind into v_member, v_status, v_kind
  from public.club_members m
  where m.club_id = v_club and m.user_id = auth.uid();
  -- 059: en deltaker blir medlem når arrangøren sier det.
  if v_kind = 'participant' then
    raise exception 'Du er med i klubben som deltaker i en turnering. Be arrangøren gjøre deg til medlem.'
      using errcode = '55000';
  end if;
  if v_member is not null then
    return jsonb_build_object('member_id', v_member, 'status', v_status);
  end if;

  if p_member_id is not null then
    update public.club_members m
       set user_id = auth.uid()
     where m.id = p_member_id
       and m.club_id = v_club
       and m.user_id is null
       and m.status = 'active'
       and m.kind = 'member'
    returning m.id, m.status into v_member, v_status;
    if v_member is null then
      raise exception 'Navnet er tatt eller finnes ikke lenger' using errcode = '55000';
    end if;
  else
    if p_display_name is null or btrim(p_display_name) = '' then
      raise exception 'Skriv inn et navn' using errcode = '22023';
    end if;
    insert into public.club_members (club_id, user_id, display_name, handicap_index, status)
    values (v_club, auth.uid(), btrim(p_display_name), p_handicap_index, 'pending')
    returning id, status into v_member, v_status;
  end if;

  return jsonb_build_object('member_id', v_member, 'status', v_status);
end;
$$;

-- --- Bare arrangøren endrer kind --------------------------------------------------
-- Som 044, med tre nye sjekker merket «059».
create or replace function public.guard_club_members()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid        uuid := auth.uid();
  v_organizer  boolean;
  v_prev       text;
  v_flags      record;
begin
  if v_uid is null then
    return new;
  end if;
  -- 044: flaggene skrives fra rollene (private.sync_member_flags).
  if private.roles_syncing() then
    return new;
  end if;
  -- 059: deltakeren lages av påmeldingen (private.ensure_participant).
  if coalesce(current_setting('dd18.participant_sync', true), '') = 'on' then
    return new;
  end if;

  if tg_op = 'UPDATE' and new.club_id is distinct from old.club_id then
    raise exception 'Et medlem kan ikke flyttes til en annen klubb'
      using errcode = '42501';
  end if;

  -- NYTT (H1): ingen kan koble en annens innlogging til et navn. Bare
  -- personen selv (join_club, create_club), eller tømme (koble fra).
  if new.user_id is not null and new.user_id <> v_uid
     and (tg_op = 'INSERT' or new.user_id is distinct from old.user_id) then
    raise exception 'Bare personen selv kan koble innloggingen sin til et navn'
      using errcode = '42501';
  end if;

  -- 044: rettigheten «Medlemmer og invitasjon».
  v_organizer := private.has_club_right(new.club_id, 'members');

  if tg_op = 'INSERT' then
    if v_organizer then
      return new;
    end if;
    -- Oppstart: den første arrangøren i en ny klubb (create_club).
    if new.is_organizer
       and new.user_id = v_uid
       and new.status = 'active'
       and not exists (select 1 from public.club_members m
                       where m.club_id = new.club_id and m.is_organizer) then
      return new;
    end if;
    -- Ellers: bare deg selv, som ventende, uten roller (join_club).
    if new.user_id is distinct from v_uid
       or new.status <> 'pending'
       or new.kind <> 'member'
       or new.is_organizer or new.is_treasurer
       or new.seed_group is not null then
      raise exception 'Bare en arrangør kan legge til spillere eller gi roller'
        using errcode = '42501';
    end if;
    return new;
  end if;

  -- UPDATE
  if not v_organizer then
    if new.is_organizer is distinct from old.is_organizer
       or new.is_treasurer is distinct from old.is_treasurer then
      raise exception 'Bare en arrangør kan endre roller' using errcode = '42501';
    end if;
    if new.seed_group is distinct from old.seed_group then
      raise exception 'Bare en arrangør kan endre seedet gruppe' using errcode = '42501';
    end if;
    if new.status is distinct from old.status then
      raise exception 'Bare en arrangør kan godkjenne eller arkivere' using errcode = '42501';
    end if;
    -- 059: medlem eller deltaker.
    if new.kind is distinct from old.kind then
      raise exception 'Bare en arrangør kan gjøre en deltaker til medlem' using errcode = '42501';
    end if;
    -- user_id: uendret, eller en ledig rad som tas av deg selv (join_club).
    if new.user_id is distinct from old.user_id
       and not (old.user_id is null and new.user_id = v_uid) then
      raise exception 'Bare en arrangør kan koble en innlogging til eller fra et navn'
        using errcode = '42501';
    end if;
    -- NYTT (H2): et ledig navn med roller mister dem når det tas, så lenge
    -- klubben har en annen aktiv arrangør med innlogging som kan gi dem igjen.
    -- 044: rollene tas (ikke bare flaggene). Andre roller går når en annen aktiv med
    -- innlogging har members (eller er eier); Eier går bare når det finnes en annen eier.
    if old.user_id is null and new.user_id = v_uid
       and exists (select 1 from public.club_member_roles mr where mr.member_id = new.id) then
      v_prev := current_setting('dd18.roles_sync', true);
      perform set_config('dd18.roles_sync', 'on', true);
      if exists (select 1 from public.club_members m
                   join public.club_member_roles mr on mr.member_id = m.id
                   join public.club_roles r on r.id = mr.role_id
                  where m.club_id = new.club_id and m.id <> new.id
                    and m.status = 'active' and m.user_id is not null
                    and (r.is_owner or 'members' = any (r.rights))) then
        delete from public.club_member_roles mr
         where mr.member_id = new.id
           and mr.role_id in (select r.id from public.club_roles r where r.club_id = new.club_id and not r.is_owner);
      end if;
      if exists (select 1 from public.club_members m
                   join public.club_member_roles mr on mr.member_id = m.id
                   join public.club_roles r on r.id = mr.role_id and r.is_owner
                  where m.club_id = new.club_id and m.id <> new.id
                    and m.status = 'active' and m.user_id is not null) then
        delete from public.club_member_roles mr
         where mr.member_id = new.id
           and mr.role_id in (select r.id from public.club_roles r where r.club_id = new.club_id and r.is_owner);
      end if;
      perform set_config('dd18.roles_sync', coalesce(v_prev, ''), true);
      select * into v_flags from private.member_flags(new.id);
      new.is_organizer := v_flags.is_organizer;
      new.is_treasurer := v_flags.is_treasurer;
    end if;
  end if;

  -- 044: den siste eieren kan ikke arkiveres eller kobles fra (å miste rollen stoppes
  -- i speilingen og i RPC-ene). Nødutgang: SQL Editor.
  if private.member_is_last_owner(old.id)
     and (new.status <> 'active' or new.user_id is null) then
    raise exception 'Klubben må ha minst én eier. Gi eierskapet til en annen først.' using errcode = '42501';
  end if;

  return new;
end;
$$;

commit;

-- --- Kontroll (les) ------------------------------------------------------------
-- select count(*) filter (where kind = 'member'), count(*) filter (where kind = 'participant')
--   from public.club_members;                                                   -- alle medlemmer før påmelding
-- select indexdef from pg_indexes where indexname = 'club_members_unique_name';  -- ... and kind = 'member'
-- select prosrc like '%kind = ''member''%' from pg_proc
--  where proname in ('is_club_member', 'my_member_id', 'owns_member', 'is_club_organizer', 'has_club_right'); -- 5 × true
-- select tgname from pg_trigger where tgname = 'competition_participants_as_member';  -- 1 rad
-- select count(*) from public.competition_participants p join public.competitions c on c.id = p.competition_id
--  where p.profile_id is not null and c.club_id is not null;                   -- 0 (eller de med ventende rad)
-- select has_function_privilege('authenticated', 'private.ensure_participant(uuid, uuid)', 'execute'); -- false

-- --- Rullebakk -------------------------------------------------------------------
-- Deltakere må gjøres til medlemmer eller slettes først (de får ellers tilgang som medlemmer):
--   select id, club_id, display_name from public.club_members where kind = 'participant';
-- begin;
-- drop trigger if exists competition_participants_as_member on public.competition_participants;
-- drop function if exists private.competition_participant_as_member();
-- drop function if exists private.ensure_participant(uuid, uuid);
-- -- Kjør definisjonene fra 044 (is_club_member, my_member_id, owns_member, is_club_organizer,
-- -- has_club_right, owns_round_player, hole_scores_before_write, guard_club_members, join_club,
-- -- policyene club_members_select, courses_select, course_holes_select, course_tees_select) og
-- -- confirm_round_par fra 058 på nytt.
-- drop function if exists private.can_read_member(uuid);
-- drop function if exists private.can_read_course(uuid);
-- drop function if exists private.my_club_row_id(uuid);
-- drop index if exists public.club_members_unique_name;
-- create unique index club_members_unique_name
--   on public.club_members (club_id, lower(btrim(display_name))) where status <> 'archived';
-- drop index if exists public.club_members_unique_ngf;
-- drop index if exists public.profiles_unique_ngf;
-- alter table public.club_members drop column if exists ngf_number;
-- alter table public.profiles drop column if exists ngf_number;
-- alter table public.club_members drop column if exists kind;
-- commit;
