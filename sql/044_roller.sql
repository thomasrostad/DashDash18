-- 044: egne roller per klubb (gjennomføringsplanen steg 2, docs/roller.md). Godkjent og kjørt på test 12.10.2026.
--
-- Hva: klubben får egne roller med rettigheter i fire grupper, i stedet for de to
-- flaggene is_organizer og is_treasurer.
--
--   1. clubs.org_number (9 siffer, valgfri) for navn fra Enhetsregisteret.
--   2. club_roles (navn, rettigheter, eier, mal) og club_member_roles (hvem har hva).
--      RLS: medlemmene i klubben leser roller og tildelinger. Ingen skrivepolicyer;
--      alt skrives av RPC-ene i punkt 6 og triggerne i punkt 4 og 5.
--   3. Skjemaet private med private.has_club_right(klubb, rettighet) og
--      private.is_club_owner(klubb). Rettighetene er tournaments, rounds, members og
--      money. Eier har alle.
--   4. Malene Eier, Arrangør (alle fire), Kasserer (money) og Sosialkomité (ingen) lages
--      for hver klubb (template_key owner, organizer, treasurer, committee). Den som er
--      arrangør i dag får Arrangør, kasserer får Kasserer, og den eldste arrangøren i
--      klubben får Eier (aktive med innlogging først, så created_at og id). Klubber uten
--      arrangør får ingen eier (tallet står i kontrollen). Nye klubber får malene av en
--      trigger, og den som lager klubben (create_club) blir Eier og Arrangør.
--   5. Speiling for gamle bygg, begge veier:
--        * club_members.is_organizer = har en rolle med tournaments (eller Eier),
--          is_treasurer = har rollen med template_key treasurer. Flaggene skrives av
--          private.sync_member_flags når rollene endres.
--        * Endrer et gammelt bygg flaggene (insert eller update på club_members), gis
--          eller tas Arrangør- eller Kasserer-rollen (is_organizer = false tar alle
--          roller med tournaments, også Eier, med eierreglene under).
--      Et medlem som ikke er aktivt, har ingen roller (som flaggene i dag, se
--      club_members_roles_need_active): rollene tas når status endres.
--      Mot ring: synkroniseringen setter den lokale innstillingen dd18.roles_sync = on
--      mens den skriver, og triggerne på club_members hopper over da. Speilingen gjør
--      ingenting når flaggene alt er lik det rollene gir.
--   6. RPC-er (security definer, egne sjekker): club_role_save, club_role_delete,
--      club_member_set_roles, club_transfer_ownership. Du kan bare gi eller ta roller med
--      rettigheter du selv har (members kreves), og bare en eier gir eller tar Eier.
--      En klubb som har eier, beholder minst én (aktiv, med innlogging):
--      guard_club_members sier nå «minst én eier» i stedet for «minst én arrangør», og
--      delete_account_data gir Eier videre til den eldste gjenværende arrangøren.
--   7. is_club_organizer(klubb) betyr «har minst én av de fire rettighetene (eller er
--      eier)». Funksjoner og policyer som spurte om arrangør, spør nå etter rettigheten
--      i docs/roller.md:
--
--      Byttet til private.has_club_right(klubb, ...):
--        tournaments:
--          policyer: competitions_insert/_update/_delete (klubbgrenen), events_insert/
--            _update/_delete, seasons_insert/_update/_delete, event_committee_insert/
--            _update/_delete, signups_insert/_update/_delete (arrangørgrenen)
--          funksjoner: is_competition_admin (klubbgrenen; brukes av competition_*-
--            policyene, delete_tournament, draw_cup, record_cup_result, tv_code,
--            competition_invite, set_competition_signup, assign_purchase m.fl.),
--            create_competition, set_event_committee
--          via RLS: activate_season (seasons_update)
--        rounds:
--          policyer: rounds_insert/_update/_delete, courses_insert/_update/_delete,
--            course_holes_*, course_tees_*, course_corrections_* (arrangørgrenen)
--          funksjoner: is_round_organizer (klubbgrenen; brukes av round_players,
--            round_matches, round_holes, round_start_groups, round_participants,
--            side_claims og save_start_list, create_round_game, settle_round_game m.fl.),
--            can_score (rette score; hole_scores-policyene, save_hole m.fl.),
--            can_link_round, start_round, set_round_setup, delete_round,
--            confirm_round_par, save_course, confirm_course
--        members:
--          policyer: club_members_insert/_update/_delete
--          funksjoner: guard_club_members (legge til, godkjenne, arkivere, seeding,
--            koble innlogging, endre flaggene)
--        money:
--          policyer: content_reports_select (arrangørgrenen), thread_messages_delete,
--            tips_delete (arrangørgrenen)
--          funksjoner: resolve_bet, settle_bet, mark_bets_closed, resolve_report
--
--      Står på is_club_organizer (= en hvilken som helst rettighet), med grunn:
--        activity_select, my_activity, activity_before_insert: kunngjøringer, purring og
--          mottakerlister hører til varslene (steg 5), som bestemmer rettigheten.
--        rounds_select, can_read_round: bare lesing av kladder; alle med en
--          administrativ rolle ser kladdene, ingen får skrive mer.
--        clubs_update: klubbens navn, push-kategorier og org_number er ikke fordelt i
--          docs/roller.md (sletting av klubben er Eier, og finnes ikke ennå).
--        entitlements_select, push_status: kjøp og «hvem har push» er ikke fordelt
--          (App Store og varsler, senere steg).
--        storage_can_write: én hjelper for portretter (members) og trådbilder (money);
--          å dele den krever nye policyer på storage.objects. Tas når appen bruker rollene.
--      Leser det speilede is_organizer (= har tournaments), uendret:
--        profile_admins_competition og record_purchase (kjøp, App Store-steget),
--        push_job_payload (push til arrangører, steg 5), quota_guard (tak på nye klubber),
--        tavla_data, tv_board_data og tv_competition_data (flaggene i svaret),
--        create_club (setter is_organizer = true; speilingen gir Eier og Arrangør).
--
-- Trygt for gamle bygg: ingen kolonne fjernes, is_organizer og is_treasurer står og
-- speiles, og med dagens data gir hver sjekk samme svar som før (lokal/044_prove.sql
-- del A). Unntak, med vilje:
--   * et medlem som er kasserer uten å være arrangør, får nå rettigheten money
--     (avgjøre veddemål, rapporter, slette meldinger og tips), og is_club_organizer blir
--     sann for det, så det også får det som står på is_club_organizer over. Kontrollen
--     skriver hvor mange det gjelder;
--   * den siste eieren kan ikke slutte å være arrangør, arkiveres eller kobles fra, selv
--     om klubben har andre arrangører, og bare en eier kan ta arrangørflagget fra en eier.
--
-- Én transaksjon, idempotent. Kontrollblokk og rullebakke nederst.

begin;

-- ===========================================================================
-- 1. ORGANISASJONSNUMMER
-- ===========================================================================
alter table public.clubs add column if not exists org_number text;
do $$
begin
  if not exists (select 1 from pg_constraint
                 where conrelid = 'public.clubs'::regclass and conname = 'clubs_org_number_check') then
    alter table public.clubs add constraint clubs_org_number_check check (org_number ~ '^[0-9]{9}$');
  end if;
end $$;


-- ===========================================================================
-- 2. TABELLENE
-- ===========================================================================
-- Rollen og medlemmet må høre til samme klubb: sammensatte fremmednøkler.
do $$
begin
  if not exists (select 1 from pg_constraint
                 where conrelid = 'public.club_members'::regclass and conname = 'club_members_club_id_id_key') then
    alter table public.club_members add constraint club_members_club_id_id_key unique (club_id, id);
  end if;
end $$;

create table if not exists public.club_roles (
  id            uuid primary key default gen_random_uuid(),
  club_id       uuid not null references public.clubs (id) on delete cascade,
  name          text not null check (char_length(btrim(name)) between 1 and 40),
  rights        text[] not null default '{}'
                check (rights <@ array['tournaments', 'rounds', 'members', 'money']::text[]),
  is_owner      boolean not null default false,
  template_key  text check (template_key in ('owner', 'organizer', 'treasurer', 'committee')),
  sort_order    integer not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint club_roles_club_id_id_key unique (club_id, id),
  constraint club_roles_owner_is_template check (is_owner = (template_key is not distinct from 'owner'))
);
create unique index if not exists club_roles_name_per_club on public.club_roles (club_id, lower(btrim(name)));
create unique index if not exists club_roles_template_per_club on public.club_roles (club_id, template_key)
  where template_key is not null;

drop trigger if exists club_roles_set_updated_at on public.club_roles;
create trigger club_roles_set_updated_at before update on public.club_roles
  for each row execute function public.set_updated_at();

create table if not exists public.club_member_roles (
  club_id     uuid not null,
  member_id   uuid not null,
  role_id     uuid not null,
  created_at  timestamptz not null default now(),
  primary key (member_id, role_id),
  constraint club_member_roles_member_fkey foreign key (club_id, member_id)
    references public.club_members (club_id, id) on delete cascade,
  constraint club_member_roles_role_fkey foreign key (club_id, role_id)
    references public.club_roles (club_id, id) on delete cascade
);
create index if not exists club_member_roles_role_idx on public.club_member_roles (role_id);
create index if not exists club_member_roles_club_idx on public.club_member_roles (club_id);

alter table public.club_roles enable row level security;
alter table public.club_member_roles enable row level security;

-- Bare lesing for innloggede. Skriving går gjennom RPC-ene (security definer).
revoke all on public.club_roles, public.club_member_roles from anon;
revoke insert, update, delete, truncate, references, trigger on public.club_roles, public.club_member_roles from authenticated;
grant select on public.club_roles, public.club_member_roles to authenticated;

drop policy if exists club_roles_select on public.club_roles;
create policy club_roles_select on public.club_roles
  for select to authenticated using (public.is_club_member(club_id));
drop policy if exists club_member_roles_select on public.club_member_roles;
create policy club_member_roles_select on public.club_member_roles
  for select to authenticated using (public.is_club_member(club_id));


-- ===========================================================================
-- 3. SKJEMAET private OG RETTIGHETENE
-- ===========================================================================
create schema if not exists private;
revoke all on schema private from public;
revoke all on schema private from anon;
grant usage on schema private to authenticated, service_role;

-- Har den innloggede rettigheten i klubben? Eier har alle.
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
       and (r.is_owner or p_right = any (r.rights))
  );
$$;
revoke all on function private.has_club_right(uuid, text) from public, anon;
grant execute on function private.has_club_right(uuid, text) to authenticated, service_role;

create or replace function private.is_club_owner(p_club uuid)
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
       and r.is_owner
  );
$$;
revoke all on function private.is_club_owner(uuid) from public, anon;
grant execute on function private.is_club_owner(uuid) to authenticated, service_role;

-- Alle rettighetene den innloggede har i klubben (alle fire for eieren).
create or replace function private.my_club_rights(p_club uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when private.is_club_owner(p_club) then array['tournaments', 'rounds', 'members', 'money']::text[]
    else coalesce((
      select array_agg(distinct x order by x)
        from public.club_members m
        join public.club_member_roles mr on mr.member_id = m.id
        join public.club_roles r on r.id = mr.role_id
        cross join lateral unnest(r.rights) as x
       where m.club_id = p_club
         and m.user_id = (select auth.uid())
         and m.status = 'active'), '{}'::text[])
  end;
$$;
revoke all on function private.my_club_rights(uuid) from public, anon;
grant execute on function private.my_club_rights(uuid) to authenticated, service_role;

-- Flaggene rollene gir et medlem (det gamle bygg ser).
create or replace function private.member_flags(p_member uuid, out is_organizer boolean, out is_treasurer boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select
    exists (select 1 from public.club_member_roles mr join public.club_roles r on r.id = mr.role_id
             where mr.member_id = p_member and (r.is_owner or 'tournaments' = any (r.rights))),
    exists (select 1 from public.club_member_roles mr join public.club_roles r on r.id = mr.role_id
             where mr.member_id = p_member and r.template_key = 'treasurer');
$$;
revoke all on function private.member_flags(uuid) from public, anon, authenticated;

-- Er medlemmet den siste eieren i klubben (aktiv, med innlogging)?
create or replace function private.member_is_last_owner(p_member uuid)
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
      join public.club_roles r on r.id = mr.role_id and r.is_owner
     where m.id = p_member and m.status = 'active' and m.user_id is not null
       and not exists (
         select 1
           from public.club_members o
           join public.club_member_roles omr on omr.member_id = o.id
           join public.club_roles orr on orr.id = omr.role_id and orr.is_owner
          where o.club_id = m.club_id and o.id <> m.id
            and o.status = 'active' and o.user_id is not null)
  );
$$;
revoke all on function private.member_is_last_owner(uuid) from public, anon, authenticated;

-- Kan den innloggede gi eller ta denne rollen? Eier: bare en eier. Ellers kreves
-- members, og rollens rettigheter må være blant dine. Uten innlogging (server, SQL)
-- er det lov.
create or replace function private.assert_can_change_role(p_role public.club_roles)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    return;
  end if;
  if p_role.is_owner then
    if not private.is_club_owner(p_role.club_id) then
      raise exception 'Bare en eier kan gi eller ta eierrollen' using errcode = '42501';
    end if;
    return;
  end if;
  if not private.has_club_right(p_role.club_id, 'members') then
    raise exception 'Du har ikke lov til å gi eller ta roller' using errcode = '42501';
  end if;
  if not (p_role.rights <@ private.my_club_rights(p_role.club_id)) then
    raise exception 'Du kan bare gi eller ta roller med rettigheter du selv har (%)', p_role.name
      using errcode = '42501';
  end if;
end;
$$;
revoke all on function private.assert_can_change_role(public.club_roles) from public, anon, authenticated;


-- ===========================================================================
-- 4. SPEILING ROLLER → FLAGG, OG MALENE
-- ===========================================================================
create or replace function private.roles_syncing()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(current_setting('dd18.roles_sync', true), '') = 'on';
$$;
revoke all on function private.roles_syncing() from public, anon;
grant execute on function private.roles_syncing() to authenticated, service_role;

-- Skriver is_organizer og is_treasurer fra rollene, bare der de er ulike.
create or replace function private.sync_member_flags(p_members uuid[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prev text := current_setting('dd18.roles_sync', true);
begin
  perform set_config('dd18.roles_sync', 'on', true);
  update public.club_members m
     set is_organizer = f.is_organizer,
         is_treasurer = f.is_treasurer
    from (select x.id, (private.member_flags(x.id)).*
            from unnest(p_members) as x(id)) f
   where m.id = f.id
     and (m.is_organizer is distinct from f.is_organizer
          or m.is_treasurer is distinct from f.is_treasurer);
  perform set_config('dd18.roles_sync', coalesce(v_prev, ''), true);
end;
$$;
revoke all on function private.sync_member_flags(uuid[]) from public, anon, authenticated;

create or replace function private.club_member_roles_sync()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if private.roles_syncing() then
    return null;
  end if;
  perform private.sync_member_flags(array[case when tg_op = 'DELETE' then old.member_id else new.member_id end]);
  return null;
end;
$$;
revoke all on function private.club_member_roles_sync() from public, anon, authenticated;

drop trigger if exists club_member_roles_sync on public.club_member_roles;
create trigger club_member_roles_sync after insert or delete on public.club_member_roles
  for each row execute function private.club_member_roles_sync();

-- Endrer eieren rettighetene på en rolle, følger flaggene til alle som har den.
create or replace function private.club_roles_sync()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.rights is distinct from old.rights or new.is_owner is distinct from old.is_owner
     or new.template_key is distinct from old.template_key then
    perform private.sync_member_flags(
      (select coalesce(array_agg(mr.member_id), '{}') from public.club_member_roles mr where mr.role_id = new.id));
  end if;
  return null;
end;
$$;
revoke all on function private.club_roles_sync() from public, anon, authenticated;

drop trigger if exists club_roles_sync on public.club_roles;
create trigger club_roles_sync after update on public.club_roles
  for each row execute function private.club_roles_sync();

-- Malene for én klubb.
create or replace function private.ensure_role_templates(p_club uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.club_roles (club_id, name, rights, is_owner, template_key, sort_order)
  values (p_club, 'Eier',         array['tournaments', 'rounds', 'members', 'money'], true,  'owner',     0),
         (p_club, 'Arrangør',     array['tournaments', 'rounds', 'members', 'money'], false, 'organizer', 1),
         (p_club, 'Kasserer',     array['money'],                                     false, 'treasurer', 2),
         (p_club, 'Sosialkomité', '{}',                                               false, 'committee', 3)
  on conflict do nothing;
$$;
revoke all on function private.ensure_role_templates(uuid) from public, anon, authenticated;

create or replace function private.clubs_role_templates()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.ensure_role_templates(new.id);
  return null;
end;
$$;
revoke all on function private.clubs_role_templates() from public, anon, authenticated;

drop trigger if exists clubs_role_templates on public.clubs;
create trigger clubs_role_templates after insert on public.clubs
  for each row execute function private.clubs_role_templates();

-- Utfylling: malene for klubber som ikke har roller ennå.
do $$
begin
  perform private.ensure_role_templates(c.id)
     from public.clubs c
    where not exists (select 1 from public.club_roles r where r.club_id = c.id);
end $$;

-- Utfylling: tildelinger fra flaggene, bare i klubber uten tildelinger (så en ny
-- kjøring ikke endrer roller klubben har satt selv).
create temp table tmp_044_clubs on commit drop as
  select c.id from public.clubs c
   where not exists (select 1 from public.club_member_roles mr where mr.club_id = c.id);

insert into public.club_member_roles (club_id, member_id, role_id)
select m.club_id, m.id, r.id
  from public.club_members m
  join public.club_roles r on r.club_id = m.club_id and r.template_key = 'organizer'
 where m.is_organizer and m.club_id in (select id from tmp_044_clubs)
on conflict do nothing;

insert into public.club_member_roles (club_id, member_id, role_id)
select m.club_id, m.id, r.id
  from public.club_members m
  join public.club_roles r on r.club_id = m.club_id and r.template_key = 'treasurer'
 where m.is_treasurer and m.club_id in (select id from tmp_044_clubs)
on conflict do nothing;

-- Eier: den eldste arrangøren, aktive med innlogging først.
insert into public.club_member_roles (club_id, member_id, role_id)
select o.club_id, o.id, r.id
  from (select distinct on (m.club_id) m.club_id, m.id
          from public.club_members m
         where m.is_organizer and m.club_id in (select id from tmp_044_clubs)
         order by m.club_id, (m.status = 'active' and m.user_id is not null) desc, m.created_at, m.id) o
  join public.club_roles r on r.club_id = o.club_id and r.is_owner
on conflict do nothing;


-- ===========================================================================
-- 5. SPEILING FLAGG → ROLLER (gamle bygg skriver is_organizer og is_treasurer)
-- ===========================================================================
create or replace function private.club_members_mirror_roles()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_flags      record;
  v_role       public.club_roles;
  v_bootstrap  boolean;
begin
  if private.roles_syncing() then
    return null;
  end if;
  if tg_op = 'INSERT' and not (new.is_organizer or new.is_treasurer) then
    return null;
  end if;
  select * into v_flags from private.member_flags(new.id);
  if new.is_organizer = v_flags.is_organizer and new.is_treasurer = v_flags.is_treasurer then
    return null;
  end if;

  -- Én endring av roller om gangen per klubb.
  perform 1 from public.clubs c where c.id = new.club_id for update;
  -- Oppstart (create_club): klubben har ingen tildelinger ennå.
  v_bootstrap := tg_op = 'INSERT'
                 and not exists (select 1 from public.club_member_roles mr where mr.club_id = new.club_id);

  if new.is_organizer and not v_flags.is_organizer then
    select * into v_role from public.club_roles r where r.club_id = new.club_id and r.template_key = 'organizer';
    if v_role.id is null then
      raise exception 'Klubben har ikke lenger rollen Arrangør' using errcode = 'P0002';
    end if;
    if not v_bootstrap then
      perform private.assert_can_change_role(v_role);
    end if;
    insert into public.club_member_roles (club_id, member_id, role_id)
    values (new.club_id, new.id, v_role.id) on conflict do nothing;
    -- Den første arrangøren i en klubb uten eier blir eier.
    if tg_op = 'INSERT' and not exists (
         select 1 from public.club_member_roles mr join public.club_roles r on r.id = mr.role_id
          where mr.club_id = new.club_id and r.is_owner) then
      insert into public.club_member_roles (club_id, member_id, role_id)
      select new.club_id, new.id, r.id from public.club_roles r where r.club_id = new.club_id and r.is_owner
      on conflict do nothing;
    end if;
  elsif not new.is_organizer and v_flags.is_organizer then
    for v_role in
      select r.* from public.club_member_roles mr join public.club_roles r on r.id = mr.role_id
       where mr.member_id = new.id and (r.is_owner or 'tournaments' = any (r.rights))
       order by r.is_owner
    loop
      perform private.assert_can_change_role(v_role);
      if v_role.is_owner and private.member_is_last_owner(new.id) then
        raise exception 'Klubben må ha minst én eier. Gi eierskapet til en annen først.' using errcode = '42501';
      end if;
      delete from public.club_member_roles mr where mr.member_id = new.id and mr.role_id = v_role.id;
    end loop;
  end if;

  if new.is_treasurer is distinct from v_flags.is_treasurer then
    select * into v_role from public.club_roles r where r.club_id = new.club_id and r.template_key = 'treasurer';
    if v_role.id is null then
      raise exception 'Klubben har ikke lenger rollen Kasserer' using errcode = 'P0002';
    end if;
    if not v_bootstrap then
      perform private.assert_can_change_role(v_role);
    end if;
    if new.is_treasurer then
      insert into public.club_member_roles (club_id, member_id, role_id)
      values (new.club_id, new.id, v_role.id) on conflict do nothing;
    else
      delete from public.club_member_roles mr where mr.member_id = new.id and mr.role_id = v_role.id;
    end if;
  end if;
  return null;
end;
$$;
revoke all on function private.club_members_mirror_roles() from public, anon, authenticated;

drop trigger if exists club_members_roles_mirror on public.club_members;
create trigger club_members_roles_mirror after insert or update of is_organizer, is_treasurer on public.club_members
  for each row execute function private.club_members_mirror_roles();

-- Et medlem som ikke er aktivt (arkivert, ventende), har ingen roller: rollene tas
-- når status endres (som club_members_roles_need_active krever for flaggene). Du må
-- kunne ta hver av rollene; siste eier stoppes alt i guard_club_members. Kjører etter
-- guard (navnene sorteres).
create or replace function private.club_members_roles_inactive()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role  public.club_roles;
  v_prev  text;
begin
  if private.roles_syncing() or new.status = 'active'
     or not exists (select 1 from public.club_member_roles mr where mr.member_id = new.id) then
    return new;
  end if;
  for v_role in
    select r.* from public.club_member_roles mr join public.club_roles r on r.id = mr.role_id
     where mr.member_id = new.id
  loop
    perform private.assert_can_change_role(v_role);
  end loop;
  v_prev := current_setting('dd18.roles_sync', true);
  perform set_config('dd18.roles_sync', 'on', true);
  delete from public.club_member_roles mr where mr.member_id = new.id;
  perform set_config('dd18.roles_sync', coalesce(v_prev, ''), true);
  new.is_organizer := false;
  new.is_treasurer := false;
  return new;
end;
$$;
revoke all on function private.club_members_roles_inactive() from public, anon, authenticated;

drop trigger if exists club_members_roles_inactive on public.club_members;
create trigger club_members_roles_inactive before update of status on public.club_members
  for each row execute function private.club_members_roles_inactive();


-- ===========================================================================
-- 6a. guard_club_members: members-rettigheten, og «minst én eier»
-- ===========================================================================
-- Fra 024. Endret: v_organizer er nå rettigheten members; synkroniseringen av flaggene
-- slippes gjennom; H2 tar rollene (ikke bare flaggene) når et ledig navn tas; og
-- «minst én arrangør» er «minst én eier». Resten er som før.
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
revoke all on function public.guard_club_members() from public, anon, authenticated;


-- ===========================================================================
-- 6b. delete_account_data: Eier går videre
-- ===========================================================================
-- Fra 019. Nytt: er personen siste eier i en klubb, får den eldste gjenværende
-- arrangøren (aktiv, med innlogging) Eier, ellers det eldste aktive medlemmet med
-- innlogging; og personens roller slettes. Svaret har også owners_promoted.
create or replace function public.delete_account_data(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_members   uuid[];
  v_messages  integer := 0;
  v_promoted  integer := 0;
  v_owners    integer := 0;
  v_rounds    integer := 0;
  v_row       record;
  v_heir      uuid;
begin
  if p_user_id is null then
    raise exception 'Mangler bruker' using errcode = '22023';
  end if;

  select coalesce(array_agg(m.id), '{}') into v_members
  from public.club_members m where m.user_id = p_user_id;

  -- Klubben skal ikke stå uten arrangør: er dette den siste, overtar det
  -- eldste aktive medlemmet med innlogging.
  for v_row in
    select m.club_id from public.club_members m
    where m.user_id = p_user_id and m.is_organizer and m.status = 'active'
      and not exists (select 1 from public.club_members o
                      where o.club_id = m.club_id and o.id <> m.id and o.is_organizer
                        and o.status = 'active' and o.user_id is not null)
  loop
    update public.club_members o set is_organizer = true
     where o.id = (select n.id from public.club_members n
                   where n.club_id = v_row.club_id and n.status = 'active'
                     and n.user_id is not null and n.user_id <> p_user_id
                   order by n.created_at, n.id limit 1);
    if found then v_promoted := v_promoted + 1; end if;
  end loop;

  -- 044: og ikke uten eier. Den eldste gjenværende arrangøren overtar, ellers det
  -- eldste aktive medlemmet med innlogging.
  for v_row in
    select m.id, m.club_id from public.club_members m
    where m.user_id = p_user_id and private.member_is_last_owner(m.id)
  loop
    select n.id into v_heir from public.club_members n
     where n.club_id = v_row.club_id and n.status = 'active'
       and n.user_id is not null and n.user_id <> p_user_id
     order by n.is_organizer desc, n.created_at, n.id limit 1;
    if v_heir is not null then
      insert into public.club_member_roles (club_id, member_id, role_id)
      select v_row.club_id, v_heir, r.id from public.club_roles r
       where r.club_id = v_row.club_id and r.is_owner
      on conflict do nothing;
      v_owners := v_owners + 1;
    end if;
  end loop;
  delete from public.club_member_roles mr where mr.member_id = any (v_members);

  -- Innholdet personen har skrevet.
  delete from public.thread_messages t where t.member_id = any (v_members);
  get diagnostics v_messages = row_count;
  delete from public.activity_reactions r where r.member_id = any (v_members);
  delete from public.push_preferences p where p.member_id = any (v_members);
  delete from public.push_devices d where d.user_id = p_user_id;
  delete from public.user_blocks b where b.blocker_id = p_user_id or b.blocked_id = p_user_id;

  -- Troppen: navnet står som «Slettet spiller», arkivert (kan ikke tas av en
  -- annen innlogging), uten roller, portrett eller innlogging.
  update public.club_members m
     set display_name = 'Slettet spiller', avatar_path = null, is_organizer = false,
         is_treasurer = false, status = 'archived', user_id = null
   where m.id = any (v_members);

  -- Løse runder: deltakeren blir en gjest med navnet «Slettet spiller».
  update public.round_participants rp set display_name = 'Slettet spiller'
   where rp.profile_id = p_user_id;
  get diagnostics v_rounds = row_count;

  update public.profiles p
     set display_name = null, avatar_path = null, handicap_index = null
   where p.id = p_user_id;

  return jsonb_build_object('memberships', cardinality(v_members), 'messages', v_messages,
                            'loose_rounds', v_rounds, 'organizers_promoted', v_promoted,
                            'owners_promoted', v_owners);
end;
$$;
revoke all on function public.delete_account_data(uuid) from public, anon, authenticated;


-- ===========================================================================
-- 6c. RPC-ENE FOR ROLLER
-- ===========================================================================
-- Lag (p_role_id null) eller endre en rolle. Bare eieren. Eierrollens rettigheter
-- står (bare navnet kan endres). p_rights null = uendret.
create or replace function public.club_role_save(p_club_id uuid, p_role_id uuid, p_name text, p_rights text[])
returns public.club_roles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_all     constant text[] := array['tournaments', 'rounds', 'members', 'money'];
  v_role    public.club_roles;
  v_name    text := btrim(coalesce(p_name, ''));
  v_rights  text[];
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if p_club_id is null or not exists (select 1 from public.clubs c where c.id = p_club_id) then
    raise exception 'Fant ikke klubben' using errcode = 'P0002';
  end if;
  if not private.is_club_owner(p_club_id) then
    raise exception 'Bare en eier kan lage og endre roller' using errcode = '42501';
  end if;
  if char_length(v_name) not between 1 and 40 then
    raise exception 'Rollen må ha et navn (1–40 tegn)' using errcode = '22023';
  end if;
  if exists (select 1 from unnest(p_rights) x where x is null or not (x = any (v_all))) then
    raise exception 'Ukjent rettighet. Gyldige er tournaments, rounds, members og money' using errcode = '22023';
  end if;
  if p_rights is not null then
    select coalesce(array_agg(x order by array_position(v_all, x)), '{}') into v_rights
      from (select distinct x from unnest(p_rights) x) s;
  end if;

  perform 1 from public.clubs c where c.id = p_club_id for update;

  if p_role_id is null then
    insert into public.club_roles (club_id, name, rights, sort_order)
    values (p_club_id, v_name, coalesce(v_rights, '{}'),
            coalesce((select max(r.sort_order) + 1 from public.club_roles r where r.club_id = p_club_id), 0))
    returning * into v_role;
  else
    select * into v_role from public.club_roles r where r.id = p_role_id and r.club_id = p_club_id for update;
    if not found then
      raise exception 'Fant ikke rollen' using errcode = 'P0002';
    end if;
    if v_role.is_owner and v_rights is not null and v_rights is distinct from v_all then
      raise exception 'Eierrollen har alltid alle rettighetene. Bare navnet kan endres.' using errcode = '22023';
    end if;
    update public.club_roles r
       set name = v_name, rights = coalesce(v_rights, r.rights)
     where r.id = p_role_id
    returning * into v_role;
  end if;
  return v_role;
exception
  when unique_violation then
    raise exception 'Klubben har alt en rolle som heter «%»', v_name using errcode = '23505';
end;
$$;
revoke all on function public.club_role_save(uuid, uuid, text, text[]) from public, anon;
grant execute on function public.club_role_save(uuid, uuid, text, text[]) to authenticated;

-- Slett en rolle ingen har. Bare eieren, og ikke eierrollen.
create or replace function public.club_role_delete(p_role_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role public.club_roles;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select * into v_role from public.club_roles r where r.id = p_role_id;
  if not found or not public.is_club_member(v_role.club_id) then
    raise exception 'Fant ikke rollen' using errcode = 'P0002';
  end if;
  if not private.is_club_owner(v_role.club_id) then
    raise exception 'Bare en eier kan slette roller' using errcode = '42501';
  end if;
  if v_role.is_owner then
    raise exception 'Eierrollen kan ikke slettes' using errcode = '22023';
  end if;
  perform 1 from public.clubs c where c.id = v_role.club_id for update;
  if exists (select 1 from public.club_member_roles mr where mr.role_id = p_role_id) then
    raise exception 'Rollen er gitt til noen. Ta den fra dem først.' using errcode = '22023';
  end if;
  delete from public.club_roles r where r.id = p_role_id;
end;
$$;
revoke all on function public.club_role_delete(uuid) from public, anon;
grant execute on function public.club_role_delete(uuid) to authenticated;

-- Sett hele rollelista til et medlem. Krever members; du kan bare gi eller ta roller
-- med rettigheter du selv har, og bare en eier gir eller tar Eier. Svarer med rollene.
create or replace function public.club_member_set_roles(p_member_id uuid, p_role_ids uuid[])
returns uuid[]
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member  public.club_members;
  v_wanted  uuid[];
  v_role    public.club_roles;
  v_result  uuid[];
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select * into v_member from public.club_members m where m.id = p_member_id;
  if not found or not public.is_club_member(v_member.club_id) then
    raise exception 'Fant ikke medlemmet' using errcode = 'P0002';
  end if;
  if not private.has_club_right(v_member.club_id, 'members') then
    raise exception 'Du har ikke lov til å gi eller ta roller' using errcode = '42501';
  end if;

  select coalesce(array_agg(distinct x), '{}') into v_wanted from unnest(p_role_ids) x where x is not null;
  if exists (select 1 from unnest(v_wanted) x
             where not exists (select 1 from public.club_roles r where r.id = x and r.club_id = v_member.club_id)) then
    raise exception 'Rollen hører ikke til klubben' using errcode = '22023';
  end if;

  perform 1 from public.clubs c where c.id = v_member.club_id for update;

  -- Det som gis.
  for v_role in
    select r.* from public.club_roles r
     where r.id = any (v_wanted)
       and not exists (select 1 from public.club_member_roles mr where mr.member_id = p_member_id and mr.role_id = r.id)
  loop
    if v_member.status <> 'active' then
      raise exception 'Bare aktive medlemmer kan få roller' using errcode = '22023';
    end if;
    perform private.assert_can_change_role(v_role);
    insert into public.club_member_roles (club_id, member_id, role_id)
    values (v_member.club_id, p_member_id, v_role.id);
  end loop;

  -- Det som tas (eierrollen sist, når en eventuell ny eier alt er gitt).
  for v_role in
    select r.* from public.club_member_roles mr join public.club_roles r on r.id = mr.role_id
     where mr.member_id = p_member_id and not (r.id = any (v_wanted))
     order by r.is_owner
  loop
    perform private.assert_can_change_role(v_role);
    if v_role.is_owner and private.member_is_last_owner(p_member_id) then
      raise exception 'Klubben må ha minst én eier. Gi eierskapet til en annen først.' using errcode = '42501';
    end if;
    delete from public.club_member_roles mr where mr.member_id = p_member_id and mr.role_id = v_role.id;
  end loop;

  select coalesce(array_agg(mr.role_id order by r.sort_order, r.name), '{}') into v_result
    from public.club_member_roles mr join public.club_roles r on r.id = mr.role_id
   where mr.member_id = p_member_id;
  return v_result;
end;
$$;
revoke all on function public.club_member_set_roles(uuid, uuid[]) from public, anon;
grant execute on function public.club_member_set_roles(uuid, uuid[]) to authenticated;

-- Gi eierskapet til et annet aktivt medlem med innlogging. Du mister Eier, men
-- beholder de andre rollene dine.
create or replace function public.club_transfer_ownership(p_club_id uuid, p_to_member uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me     uuid;
  v_to     public.club_members;
  v_owner  uuid;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if p_club_id is null or not public.is_club_member(p_club_id) then
    raise exception 'Fant ikke klubben' using errcode = 'P0002';
  end if;
  if not private.is_club_owner(p_club_id) then
    raise exception 'Bare en eier kan gi bort eierskapet' using errcode = '42501';
  end if;
  select * into v_to from public.club_members m where m.id = p_to_member and m.club_id = p_club_id;
  if not found then
    raise exception 'Fant ikke medlemmet i klubben' using errcode = 'P0002';
  end if;
  if v_to.status <> 'active' or v_to.user_id is null then
    raise exception 'Eierskapet kan bare gis til et aktivt medlem med innlogging' using errcode = '22023';
  end if;
  v_me := public.my_member_id(p_club_id);
  if v_to.id = v_me then
    raise exception 'Du er alt eier' using errcode = '22023';
  end if;

  perform 1 from public.clubs c where c.id = p_club_id for update;
  select r.id into v_owner from public.club_roles r where r.club_id = p_club_id and r.is_owner;
  insert into public.club_member_roles (club_id, member_id, role_id)
  values (p_club_id, v_to.id, v_owner) on conflict do nothing;
  delete from public.club_member_roles mr where mr.member_id = v_me and mr.role_id = v_owner;
end;
$$;
revoke all on function public.club_transfer_ownership(uuid, uuid) from public, anon;
grant execute on function public.club_transfer_ownership(uuid, uuid) to authenticated;


-- ===========================================================================
-- 7a. is_club_organizer = minst én rettighet
-- ===========================================================================
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
       and (r.is_owner or r.rights && array['tournaments', 'rounds', 'members', 'money']::text[])
  );
$$;
revoke all on function public.is_club_organizer(uuid) from public, anon;
grant execute on function public.is_club_organizer(uuid) to authenticated, service_role;


-- ===========================================================================
-- 7b. HJELPERNE: tournaments og rounds
-- ===========================================================================
-- Fra 032. Bare klubbgrenen er endret.
create or replace function public.is_competition_admin(p_competition_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.competitions c
    where c.id = p_competition_id
      and (   (c.club_id is not null and private.has_club_right(c.club_id, 'tournaments'))
           or (c.club_id is null and c.owner_id = auth.uid())
           or exists (select 1 from public.competition_staff s
                       where s.competition_id = c.id and s.profile_id = auth.uid()
                         and s.role = 'organizer'))
  );
$$;
revoke all on function public.is_competition_admin(uuid) from public, anon;
grant execute on function public.is_competition_admin(uuid) to authenticated, service_role;

-- Fra 032. Bare klubbgrenen er endret.
create or replace function public.is_round_organizer(p_round_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.rounds r
    where r.id = p_round_id
      and (   private.has_club_right(r.club_id, 'rounds')
           or (r.club_id is null and r.owner_id = auth.uid())
           or (r.event_id is not null and public.is_round_staff(r.id, 'organizer')))
  );
$$;
revoke all on function public.is_round_organizer(uuid) from public, anon;
grant execute on function public.is_round_organizer(uuid) to authenticated, service_role;

-- Fra 017. Bare klubbgrenen er endret.
create or replace function public.can_link_round(p_round_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.rounds r
    where r.id = p_round_id
      and (   (r.club_id is not null and private.has_club_right(r.club_id, 'rounds'))
           or (r.club_id is null and r.owner_id = auth.uid()))
  );
$$;
revoke all on function public.can_link_round(uuid) from public, anon;
grant execute on function public.can_link_round(uuid) to authenticated, service_role;

-- Fra 032. Bare arrangørsjekken er endret (rette score = rounds).
create or replace function public.can_score(p_round_id uuid, p_member_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_found   boolean;
  v_club    uuid;
  v_status  text;
  v_owner   uuid;
  v_bay     smallint;
  v_marker  uuid;
begin
  if auth.uid() is null then
    return false;
  end if;

  select true, r.club_id, r.status, r.owner_id into v_found, v_club, v_status, v_owner
  from public.rounds r where r.id = p_round_id;
  if v_found is null then
    return false;
  end if;

  if v_club is not null then
    if private.has_club_right(v_club, 'rounds') then
      return true;
    end if;
  elsif v_owner = auth.uid() then
    return true;
  end if;

  -- 032: arrangøren i staben har arrangørens rett.
  if public.is_round_staff(p_round_id, 'organizer') then
    return true;
  end if;

  if v_status <> 'active' then
    return false;
  end if;

  select rp.bay_no into v_bay
  from public.round_players rp
  where rp.round_id = p_round_id and rp.member_id = p_member_id;

  if v_bay is not null then
    select rp.member_id into v_marker
    from public.round_players rp
    where rp.round_id = p_round_id and rp.bay_no = v_bay and rp.is_marker;
  end if;

  if v_marker is not null then
    return public.owns_round_player(p_round_id, v_marker)
        or public.is_group_scorer(p_round_id, v_bay);
  end if;

  return public.owns_round_player(p_round_id, p_member_id)
      or public.is_group_scorer(p_round_id, v_bay);
end;
$$;
revoke all on function public.can_score(uuid, uuid) from public, anon;
grant execute on function public.can_score(uuid, uuid) to authenticated, service_role;


-- ===========================================================================
-- 7c. RPC-ENE: rounds
-- ===========================================================================
-- Fra 006. Bare sjekken er endret.
create or replace function public.start_round(p_round_id uuid, p_players jsonb, p_matches jsonb default '[]'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_round  public.rounds%rowtype;
  v_setup  jsonb;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  select * into v_round from public.rounds r where r.id = p_round_id for update;
  if not found then
    raise exception 'Fant ikke runden' using errcode = 'P0002';
  end if;
  if not private.has_club_right(v_round.club_id, 'rounds') then
    raise exception 'Bare en arrangør kan starte runden' using errcode = '42501';
  end if;
  if v_round.status <> 'draft' then
    raise exception 'Bare en kladd kan startes' using errcode = '55000';
  end if;

  -- Samme sjekker og skriving som før (deltakere, båser, lag, matcher).
  v_setup := public.set_round_setup(p_round_id, p_players, p_matches);

  -- Den unike indeksen rounds_one_active_per_club gir 23505 hvis en annen
  -- runde går. Da ruller også oppsettet over tilbake.
  update public.rounds set status = 'active' where id = p_round_id;

  return v_setup || jsonb_build_object('status', 'active');
end;
$$;
revoke all on function public.start_round(uuid, jsonb, jsonb) from public, anon;
grant execute on function public.start_round(uuid, jsonb, jsonb) to authenticated, service_role;

-- Fra 001. Bare sjekken er endret.
create or replace function public.set_round_setup(p_round_id uuid, p_players jsonb, p_matches jsonb default '[]'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_round  public.rounds%rowtype;
  v_ids    uuid[];
  v_names  text;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  select * into v_round from public.rounds r where r.id = p_round_id for update;
  if not found then
    raise exception 'Fant ikke runden' using errcode = 'P0002';
  end if;
  if not private.has_club_right(v_round.club_id, 'rounds') then
    raise exception 'Bare en arrangør kan sette opp runden' using errcode = '42501';
  end if;
  if v_round.status = 'locked' then
    raise exception 'Runden er låst' using errcode = '55000';
  end if;
  if jsonb_typeof(p_players) is distinct from 'array' then
    raise exception 'Spillerlista mangler' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_matches, '[]'::jsonb)) <> 'array' then
    raise exception 'Matchlista må være en liste' using errcode = '22023';
  end if;

  select coalesce(array_agg(x.member_id), '{}') into v_ids
  from jsonb_to_recordset(p_players) as x(member_id uuid);

  if exists (select 1 from unnest(v_ids) i where i is null) then
    raise exception 'member_id mangler' using errcode = '22023';
  end if;
  if cardinality(v_ids) <> (select count(distinct i) from unnest(v_ids) i) then
    raise exception 'Samme spiller to ganger' using errcode = '22023';
  end if;

  -- Ingen fjerning av spillere som har ført noe.
  select string_agg(m.display_name, ', ' order by m.display_name) into v_names
  from public.round_players rp
  join public.club_members m on m.id = rp.member_id
  where rp.round_id = p_round_id
    and not (rp.member_id = any(v_ids))
    and (   exists (select 1 from public.hole_scores s
                    where s.round_id = rp.round_id and s.member_id = rp.member_id)
         or exists (select 1 from public.side_claims c
                    where c.round_id = rp.round_id and c.member_id = rp.member_id));
  if v_names is not null then
    raise exception 'Kan ikke ta ut % – det er ført scorer eller sidepremier. Slett dem først.', v_names
      using errcode = '55000';
  end if;

  -- 1. Matchene peker på deltakere, så de går først.
  delete from public.round_matches where round_id = p_round_id;

  -- 2. Ta ut dem som ikke er med lenger.
  delete from public.round_players rp
   where rp.round_id = p_round_id and not (rp.member_id = any(v_ids));

  -- 3. Nullstill markørene først: den unike indeksen (én markør per bås)
  --    kan ikke utsettes, og et markørbytte i samme bås ville ellers kollidere.
  update public.round_players set is_marker = false
   where round_id = p_round_id and is_marker;

  -- 4. Skriv deltakerne.
  insert into public.round_players as rp
         (round_id, member_id, club_id, bay_no, is_marker, team_no, playing_handicap)
  select p_round_id, x.member_id, v_round.club_id, x.bay_no,
         coalesce(x.is_marker, false), x.team_no, x.playing_handicap
  from jsonb_to_recordset(p_players)
       as x(member_id uuid, bay_no smallint, is_marker boolean, team_no smallint,
            playing_handicap smallint)
  on conflict (round_id, member_id) do update
    set bay_no           = excluded.bay_no,
        is_marker        = excluded.is_marker,
        team_no          = excluded.team_no,
        playing_handicap = excluded.playing_handicap;

  -- 5. Matchene.
  insert into public.round_matches
         (round_id, match_no, player_a, player_b, player_c, team_a, team_b, result)
  select p_round_id, x.match_no, x.player_a, x.player_b, x.player_c, x.team_a, x.team_b, x.result
  from jsonb_to_recordset(coalesce(p_matches, '[]'::jsonb))
       as x(match_no smallint, player_a uuid, player_b uuid, player_c uuid,
            team_a smallint, team_b smallint, result text);

  return jsonb_build_object(
    'players', (select count(*) from public.round_players where round_id = p_round_id),
    'matches', (select count(*) from public.round_matches where round_id = p_round_id)
  );
end;
$$;
revoke all on function public.set_round_setup(uuid, jsonb, jsonb) from public, anon;
grant execute on function public.set_round_setup(uuid, jsonb, jsonb) to authenticated, service_role;

-- Fra 001. Bare sjekken er endret.
create or replace function public.delete_round(p_round_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_round    public.rounds%rowtype;
  n_scores   integer;
  n_claims   integer;
  n_matches  integer;
  n_players  integer;
  n_holes    integer;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  select * into v_round from public.rounds r where r.id = p_round_id for update;
  if not found then
    raise exception 'Fant ingen runde å slette. Er den alt borte?' using errcode = 'P0002';
  end if;
  if not private.has_club_right(v_round.club_id, 'rounds') then
    raise exception 'Bare en arrangør kan slette en runde' using errcode = '42501';
  end if;
  if v_round.status = 'locked' then
    raise exception 'Runden er låst. En låst runde slettes ikke herfra.' using errcode = '55000';
  end if;

  delete from public.hole_scores   where round_id = p_round_id; get diagnostics n_scores  = row_count;
  delete from public.side_claims   where round_id = p_round_id; get diagnostics n_claims  = row_count;
  delete from public.round_matches where round_id = p_round_id; get diagnostics n_matches = row_count;
  delete from public.round_players where round_id = p_round_id; get diagnostics n_players = row_count;
  delete from public.round_holes   where round_id = p_round_id; get diagnostics n_holes   = row_count;
  delete from public.rounds        where id = p_round_id;

  return jsonb_build_object(
    'round_no', v_round.round_no,
    'name', v_round.name,
    'hole_scores', n_scores,
    'side_claims', n_claims,
    'matches', n_matches,
    'players', n_players,
    'round_holes', n_holes
  );
end;
$$;
revoke all on function public.delete_round(uuid) from public, anon;
grant execute on function public.delete_round(uuid) to authenticated, service_role;

-- Fra 018. Bare sjekken for klubbrunder er endret.
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
    v_boss := private.has_club_right(v_round.club_id, 'rounds');
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
grant execute on function public.confirm_round_par(uuid) to authenticated, service_role;

-- Fra 002. Bare sjekken er endret (security invoker som før).
create or replace function public.save_course(p_club_id uuid, p_course_id uuid, p_name text, p_external_name text,
                                              p_course_rating numeric, p_slope_rating smallint, p_in_use boolean,
                                              p_holes jsonb)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not private.has_club_right(p_club_id, 'rounds') then
    raise exception 'Bare arrangøren kan endre banene' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_holes, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_holes, '[]'::jsonb)) not in (0, 9, 18) then
    raise exception 'En bane har 9 eller 18 hull' using errcode = '22023';
  end if;

  if p_course_id is null then
    insert into public.courses (club_id, name, external_name, course_rating, slope_rating, in_use)
    values (p_club_id, btrim(p_name), nullif(btrim(p_external_name), ''),
            p_course_rating, p_slope_rating, coalesce(p_in_use, true))
    returning id into v_id;
  else
    update public.courses
       set name = btrim(p_name),
           external_name = nullif(btrim(p_external_name), ''),
           course_rating = p_course_rating,
           slope_rating = p_slope_rating,
           in_use = coalesce(p_in_use, true)
     where id = p_course_id and club_id = p_club_id
    returning id into v_id;
    if v_id is null then
      raise exception 'Fant ikke banen' using errcode = 'P0002';
    end if;
  end if;

  delete from public.course_holes h
   where h.course_id = v_id
     and h.hole_number not in (
       select (e->>'hole_number')::smallint from jsonb_array_elements(coalesce(p_holes, '[]'::jsonb)) e);

  insert into public.course_holes (course_id, hole_number, par, stroke_index, length_m)
  select v_id,
         (e->>'hole_number')::smallint,
         (e->>'par')::smallint,
         (e->>'stroke_index')::smallint,
         (e->>'length_m')::smallint
    from jsonb_array_elements(coalesce(p_holes, '[]'::jsonb)) e
  on conflict (course_id, hole_number) do update
     set par = excluded.par,
         stroke_index = excluded.stroke_index,
         length_m = excluded.length_m;

  return v_id;
end;
$$;
revoke all on function public.save_course(uuid, uuid, text, text, numeric, smallint, boolean, jsonb) from public, anon;
grant execute on function public.save_course(uuid, uuid, text, text, numeric, smallint, boolean, jsonb) to authenticated, service_role;

-- Fra 002. Bare sjekken er endret (security invoker som før).
create or replace function public.confirm_course(p_course_id uuid)
returns timestamptz
language plpgsql
set search_path = ''
as $$
declare
  v_at timestamptz;
begin
  update public.courses c
     set confirmed_by = public.my_member_id(c.club_id),
         confirmed_at = now()
   where c.id = p_course_id
     and private.has_club_right(c.club_id, 'rounds')
  returning c.confirmed_at into v_at;
  if v_at is null then
    raise exception 'Fant ikke banen, eller du er ikke arrangør' using errcode = '42501';
  end if;
  return v_at;
end;
$$;
revoke all on function public.confirm_course(uuid) from public, anon;
grant execute on function public.confirm_course(uuid) to authenticated, service_role;


-- ===========================================================================
-- 7d. RPC-ENE: tournaments
-- ===========================================================================
-- Fra 026. Bare sjekken er endret.
create or replace function public.create_competition(p_kind text, p_name text, p_club_id uuid default null,
                                                     p_entry text default 'listed', p_rules jsonb default null,
                                                     p_starts_on date default null, p_ends_on date default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_me public.profiles;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if p_kind is null or p_kind = 'season' then
    raise exception 'En serie med kvelder lages under «Ny turnering»' using errcode = '22023';
  end if;
  if p_club_id is not null and not private.has_club_right(p_club_id, 'tournaments') then
    raise exception 'Bare en arrangør kan lage en konkurranse i klubben' using errcode = '42501';
  end if;

  v_me := public.ensure_profile();

  insert into public.competitions (kind, name, club_id, owner_id, status, entry, rules, starts_on, ends_on)
  values (p_kind, btrim(p_name), p_club_id, case when p_club_id is null then v_me.id end,
          'active', coalesce(p_entry, 'listed'), coalesce(p_rules, '{"version": 1}'::jsonb),
          p_starts_on, p_ends_on)
  returning id into v_id;

  if p_club_id is null then
    insert into public.competition_participants (competition_id, profile_id) values (v_id, v_me.id);
  end if;
  return v_id;
end;
$$;
revoke all on function public.create_competition(text, text, uuid, text, jsonb, date, date) from public, anon;
grant execute on function public.create_competition(text, text, uuid, text, jsonb, date, date) to authenticated, service_role;

-- Fra 005. Bare sjekken er endret (security invoker som før).
create or replace function public.set_event_committee(p_event_id uuid, p_member_ids uuid[])
returns uuid[]
language plpgsql
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
  if not private.has_club_right(v_club, 'tournaments') then
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
grant execute on function public.set_event_committee(uuid, uuid[]) to authenticated, service_role;


-- ===========================================================================
-- 7e. RPC-ENE: money
-- ===========================================================================
-- Fra 012. Bare sjekken er endret.
create or replace function public.resolve_bet(p_bet_id uuid, p_resolution text)
returns public.bets
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_bet  public.bets%rowtype;
  v_me   uuid;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if p_resolution is null or p_resolution not in ('yes', 'no', 'void') then
    raise exception 'Utfallet må være yes, no eller void' using errcode = '22023';
  end if;
  select * into v_bet from public.bets b where b.id = p_bet_id for update;
  if not found or not public.is_club_member(v_bet.club_id) then
    raise exception 'Fant ikke veddemålet' using errcode = 'P0002';
  end if;
  if not private.has_club_right(v_bet.club_id, 'money') then
    raise exception 'Bare arrangøren avgjør veddemål' using errcode = '42501';
  end if;
  if v_bet.status <> 'open' then
    raise exception 'Veddemålet er alt avgjort' using errcode = '55000';
  end if;
  v_me := public.my_member_id(v_bet.club_id);
  if exists (select 1 from public.bet_stakes s where s.bet_id = p_bet_id and s.member_id = v_me) then
    raise exception 'Du har satset på dette veddemålet og kan ikke avgjøre det. En annen arrangør må gjøre det.'
      using errcode = '55000';
  end if;

  update public.bets b
     set status      = case when p_resolution = 'void' then 'void' else 'resolved' end,
         resolution  = case when p_resolution = 'void' then null else p_resolution end,
         resolved_by = v_me,
         resolved_at = now(),
         closed_at   = coalesce(b.closed_at, now())
   where b.id = p_bet_id
  returning * into v_bet;

  insert into public.activity (club_id, kind, category, data, event_id, round_id)
  values (v_bet.club_id, 'bet_resolved', 'bet',
          jsonb_build_object('bet_id', v_bet.id, 'question', v_bet.question, 'resolution', p_resolution),
          v_bet.event_id, v_bet.round_id);
  return v_bet;
end;
$$;
revoke all on function public.resolve_bet(uuid, text) from public, anon;
grant execute on function public.resolve_bet(uuid, text) to authenticated, service_role;

-- Fra 012. Bare sjekken er endret.
create or replace function public.settle_bet(p_bet_id uuid, p_resolution text)
returns public.bets
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_bet  public.bets%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if p_resolution is null or p_resolution not in ('yes', 'no', 'void') then
    raise exception 'Utfallet må være yes, no eller void' using errcode = '22023';
  end if;
  select * into v_bet from public.bets b where b.id = p_bet_id for update;
  if not found or not public.is_club_member(v_bet.club_id) then
    raise exception 'Fant ikke veddemålet' using errcode = 'P0002';
  end if;
  if not private.has_club_right(v_bet.club_id, 'money') then
    raise exception 'Bare arrangørens telefon avgjør veddemål automatisk' using errcode = '42501';
  end if;
  if v_bet.status <> 'open' then
    raise exception 'Veddemålet er alt avgjort' using errcode = '55000';
  end if;
  if v_bet.condition is null then
    raise exception 'Fri tekst avgjøres av arrangøren for hånd' using errcode = '22023';
  end if;
  if p_resolution = 'void' and v_bet.condition ->> 'kind' not in ('hole', 'beats', 'match') then
    raise exception 'Bare delt hull, delt match og likt resultat annulleres automatisk' using errcode = '22023';
  end if;
  if not public.bet_outcome_known(v_bet) then
    raise exception 'Utfallet er ikke kjent ennå' using errcode = '55000';
  end if;

  update public.bets b
     set status      = case when p_resolution = 'void' then 'void' else 'resolved' end,
         resolution  = case when p_resolution = 'void' then null else p_resolution end,
         resolved_by = null,
         resolved_at = now(),
         closed_at   = coalesce(b.closed_at, now())
   where b.id = p_bet_id
  returning * into v_bet;

  insert into public.activity (club_id, kind, category, data, event_id, round_id)
  values (v_bet.club_id, 'bet_resolved', 'bet',
          jsonb_build_object('bet_id', v_bet.id, 'question', v_bet.question, 'resolution', p_resolution,
                             'auto', true),
          v_bet.event_id, v_bet.round_id);
  return v_bet;
end;
$$;
revoke all on function public.settle_bet(uuid, text) from public, anon;
grant execute on function public.settle_bet(uuid, text) to authenticated, service_role;

-- Fra 012. Bare sjekken er endret.
create or replace function public.mark_bets_closed(p_bet_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  n integer;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if coalesce(cardinality(p_bet_ids), 0) > 200 then
    raise exception 'For mange veddemål på én gang' using errcode = '22023';
  end if;
  update public.bets b
     set closed_at = now()
   where b.id = any (p_bet_ids)
     and b.status = 'open'
     and b.closed_at is null
     and private.has_club_right(b.club_id, 'money');
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke all on function public.mark_bets_closed(uuid[]) from public, anon;
grant execute on function public.mark_bets_closed(uuid[]) to authenticated, service_role;

-- Fra 019. Bare sjekken er endret.
create or replace function public.resolve_report(p_report_id uuid, p_action text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_report  public.content_reports;
  v_image   text;
  v_status  text;
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if p_action is null or p_action not in ('remove', 'dismiss') then
    raise exception 'Handlingen må være remove eller dismiss' using errcode = '22023';
  end if;
  select * into v_report from public.content_reports r where r.id = p_report_id for update;
  if not found or v_report.club_id is null or not private.has_club_right(v_report.club_id, 'money') then
    raise exception 'Bare arrangøren i klubben kan avgjøre rapporten' using errcode = '42501';
  end if;
  if v_report.status <> 'open' then
    raise exception 'Rapporten er allerede avgjort' using errcode = '55000';
  end if;

  v_status := case p_action when 'remove' then 'removed' else 'dismissed' end;
  if p_action = 'remove' and v_report.kind in ('message', 'image') then
    delete from public.thread_messages t
     where t.id = v_report.target_id and t.club_id = v_report.club_id
    returning t.image_path into v_image;
  end if;

  -- Alle åpne rapporter om det samme innholdet avgjøres samtidig.
  update public.content_reports r
     set status = v_status, handled_by = v_uid, handled_at = now()
   where r.status = 'open' and r.target_id = v_report.target_id and r.club_id = v_report.club_id
     and (r.kind = v_report.kind or (r.kind in ('message', 'image') and v_report.kind in ('message', 'image')));

  return jsonb_build_object('status', v_status, 'image_path', v_image);
end;
$$;
revoke all on function public.resolve_report(uuid, text) from public, anon;
grant execute on function public.resolve_report(uuid, text) to authenticated, service_role;


-- ===========================================================================
-- 7f. POLICYENE (samme uttrykk, is_club_organizer byttet mot rettigheten)
-- ===========================================================================
-- members
drop policy if exists club_members_delete on public.club_members;
create policy club_members_delete on public.club_members
  for delete to authenticated
  using ((private.has_club_right(club_id, 'members') AND (user_id IS NULL)));
drop policy if exists club_members_insert on public.club_members;
create policy club_members_insert on public.club_members
  for insert to authenticated
  with check (private.has_club_right(club_id, 'members'));
drop policy if exists club_members_update on public.club_members;
create policy club_members_update on public.club_members
  for update to authenticated
  using ((private.has_club_right(club_id, 'members') OR (user_id = auth.uid())))
  with check ((private.has_club_right(club_id, 'members') OR (user_id = auth.uid())));

-- money
drop policy if exists content_reports_select on public.content_reports;
create policy content_reports_select on public.content_reports
  for select to authenticated
  using (((reporter_id = auth.uid()) OR ((club_id IS NOT NULL) AND private.has_club_right(club_id, 'money'))));
drop policy if exists thread_messages_delete on public.thread_messages;
create policy thread_messages_delete on public.thread_messages
  for delete to authenticated
  using ((public.owns_member(member_id) OR private.has_club_right(club_id, 'money')));
drop policy if exists tips_delete on public.tips;
create policy tips_delete on public.tips
  for delete to authenticated
  using (((public.owns_member(member_id) AND public.tips_open(event_id)) OR private.has_club_right(club_id, 'money')));

-- rounds
drop policy if exists course_corrections_delete on public.course_corrections;
create policy course_corrections_delete on public.course_corrections
  for delete to authenticated
  using (((profile_id = auth.uid()) OR ((club_id IS NOT NULL) AND private.has_club_right(club_id, 'rounds'))));
drop policy if exists course_corrections_insert on public.course_corrections;
create policy course_corrections_insert on public.course_corrections
  for insert to authenticated
  with check (((profile_id = auth.uid()) OR ((club_id IS NOT NULL) AND private.has_club_right(club_id, 'rounds'))));
drop policy if exists course_corrections_update on public.course_corrections;
create policy course_corrections_update on public.course_corrections
  for update to authenticated
  using (((profile_id = auth.uid()) OR ((club_id IS NOT NULL) AND private.has_club_right(club_id, 'rounds'))))
  with check (((profile_id = auth.uid()) OR ((club_id IS NOT NULL) AND private.has_club_right(club_id, 'rounds'))));
drop policy if exists course_holes_delete on public.course_holes;
create policy course_holes_delete on public.course_holes
  for delete to authenticated
  using ((EXISTS ( SELECT 1
   FROM public.courses c
  WHERE ((c.id = course_holes.course_id) AND (private.has_club_right(c.club_id, 'rounds') OR ((c.club_id IS NULL) AND (c.source IS NULL) AND (c.created_by_profile = auth.uid())))))));
drop policy if exists course_holes_insert on public.course_holes;
create policy course_holes_insert on public.course_holes
  for insert to authenticated
  with check ((EXISTS ( SELECT 1
   FROM public.courses c
  WHERE ((c.id = course_holes.course_id) AND (private.has_club_right(c.club_id, 'rounds') OR ((c.club_id IS NULL) AND (c.source IS NULL) AND (c.created_by_profile = auth.uid())))))));
drop policy if exists course_holes_update on public.course_holes;
create policy course_holes_update on public.course_holes
  for update to authenticated
  using ((EXISTS ( SELECT 1
   FROM public.courses c
  WHERE ((c.id = course_holes.course_id) AND (private.has_club_right(c.club_id, 'rounds') OR ((c.club_id IS NULL) AND (c.source IS NULL) AND (c.created_by_profile = auth.uid())))))))
  with check ((EXISTS ( SELECT 1
   FROM public.courses c
  WHERE ((c.id = course_holes.course_id) AND (private.has_club_right(c.club_id, 'rounds') OR ((c.club_id IS NULL) AND (c.source IS NULL) AND (c.created_by_profile = auth.uid())))))));
drop policy if exists course_tees_delete on public.course_tees;
create policy course_tees_delete on public.course_tees
  for delete to authenticated
  using (((source IS NULL) AND (EXISTS ( SELECT 1
   FROM public.courses c
  WHERE ((c.id = course_tees.course_id) AND (private.has_club_right(c.club_id, 'rounds') OR ((c.club_id IS NULL) AND (c.source IS NULL) AND (c.created_by_profile = auth.uid()))))))));
drop policy if exists course_tees_insert on public.course_tees;
create policy course_tees_insert on public.course_tees
  for insert to authenticated
  with check (((source IS NULL) AND (EXISTS ( SELECT 1
   FROM public.courses c
  WHERE ((c.id = course_tees.course_id) AND (private.has_club_right(c.club_id, 'rounds') OR ((c.club_id IS NULL) AND (c.source IS NULL) AND (c.created_by_profile = auth.uid()))))))));
drop policy if exists course_tees_update on public.course_tees;
create policy course_tees_update on public.course_tees
  for update to authenticated
  using (((source IS NULL) AND (EXISTS ( SELECT 1
   FROM public.courses c
  WHERE ((c.id = course_tees.course_id) AND (private.has_club_right(c.club_id, 'rounds') OR ((c.club_id IS NULL) AND (c.source IS NULL) AND (c.created_by_profile = auth.uid()))))))))
  with check (((source IS NULL) AND (EXISTS ( SELECT 1
   FROM public.courses c
  WHERE ((c.id = course_tees.course_id) AND (private.has_club_right(c.club_id, 'rounds') OR ((c.club_id IS NULL) AND (c.source IS NULL) AND (c.created_by_profile = auth.uid()))))))));
drop policy if exists courses_delete on public.courses;
create policy courses_delete on public.courses
  for delete to authenticated
  using ((private.has_club_right(club_id, 'rounds') OR ((club_id IS NULL) AND (source IS NULL) AND (created_by_profile = auth.uid()))));
drop policy if exists courses_insert on public.courses;
create policy courses_insert on public.courses
  for insert to authenticated
  with check ((private.has_club_right(club_id, 'rounds') OR ((club_id IS NULL) AND (source IS NULL) AND (created_by_profile = auth.uid()))));
drop policy if exists courses_update on public.courses;
create policy courses_update on public.courses
  for update to authenticated
  using ((private.has_club_right(club_id, 'rounds') OR ((club_id IS NULL) AND (source IS NULL) AND (created_by_profile = auth.uid()))))
  with check ((private.has_club_right(club_id, 'rounds') OR ((club_id IS NULL) AND (source IS NULL) AND (created_by_profile = auth.uid()))));
drop policy if exists rounds_delete on public.rounds;
create policy rounds_delete on public.rounds
  for delete to authenticated
  using (((private.has_club_right(club_id, 'rounds') OR ((club_id IS NULL) AND (owner_id = auth.uid()))) AND (status <> 'locked'::text)));
drop policy if exists rounds_insert on public.rounds;
create policy rounds_insert on public.rounds
  for insert to authenticated
  with check ((private.has_club_right(club_id, 'rounds') OR ((club_id IS NULL) AND (owner_id = auth.uid()))));
drop policy if exists rounds_update on public.rounds;
create policy rounds_update on public.rounds
  for update to authenticated
  using ((private.has_club_right(club_id, 'rounds') OR ((club_id IS NULL) AND (owner_id = auth.uid()))))
  with check ((private.has_club_right(club_id, 'rounds') OR ((club_id IS NULL) AND (owner_id = auth.uid()))));

-- tournaments
drop policy if exists competitions_delete on public.competitions;
create policy competitions_delete on public.competitions
  for delete to authenticated
  using (((season_id IS NULL) AND (((club_id IS NOT NULL) AND private.has_club_right(club_id, 'tournaments')) OR ((club_id IS NULL) AND (owner_id = auth.uid())))));
drop policy if exists competitions_insert on public.competitions;
create policy competitions_insert on public.competitions
  for insert to authenticated
  with check ((((club_id IS NOT NULL) AND private.has_club_right(club_id, 'tournaments')) OR ((club_id IS NULL) AND (owner_id = auth.uid()))));
drop policy if exists competitions_update on public.competitions;
create policy competitions_update on public.competitions
  for update to authenticated
  using ((((club_id IS NOT NULL) AND private.has_club_right(club_id, 'tournaments')) OR ((club_id IS NULL) AND (owner_id = auth.uid()))))
  with check ((((club_id IS NOT NULL) AND private.has_club_right(club_id, 'tournaments')) OR ((club_id IS NULL) AND (owner_id = auth.uid()))));
drop policy if exists event_committee_delete on public.event_committee;
create policy event_committee_delete on public.event_committee
  for delete to authenticated
  using (private.has_club_right(club_id, 'tournaments'));
drop policy if exists event_committee_insert on public.event_committee;
create policy event_committee_insert on public.event_committee
  for insert to authenticated
  with check (private.has_club_right(club_id, 'tournaments'));
drop policy if exists event_committee_update on public.event_committee;
create policy event_committee_update on public.event_committee
  for update to authenticated
  using (private.has_club_right(club_id, 'tournaments'))
  with check (private.has_club_right(club_id, 'tournaments'));
drop policy if exists events_delete on public.events;
create policy events_delete on public.events
  for delete to authenticated
  using (private.has_club_right(club_id, 'tournaments'));
drop policy if exists events_insert on public.events;
create policy events_insert on public.events
  for insert to authenticated
  with check (private.has_club_right(club_id, 'tournaments'));
drop policy if exists events_update on public.events;
create policy events_update on public.events
  for update to authenticated
  using (private.has_club_right(club_id, 'tournaments'))
  with check (private.has_club_right(club_id, 'tournaments'));
drop policy if exists seasons_delete on public.seasons;
create policy seasons_delete on public.seasons
  for delete to authenticated
  using ((private.has_club_right(club_id, 'tournaments') AND (status = 'planned'::text)));
drop policy if exists seasons_insert on public.seasons;
create policy seasons_insert on public.seasons
  for insert to authenticated
  with check (private.has_club_right(club_id, 'tournaments'));
drop policy if exists seasons_update on public.seasons;
create policy seasons_update on public.seasons
  for update to authenticated
  using (private.has_club_right(club_id, 'tournaments'))
  with check (private.has_club_right(club_id, 'tournaments'));
drop policy if exists signups_delete on public.signups;
create policy signups_delete on public.signups
  for delete to authenticated
  using ((public.owns_member(member_id) OR private.has_club_right(club_id, 'tournaments')));
drop policy if exists signups_insert on public.signups;
create policy signups_insert on public.signups
  for insert to authenticated
  with check ((public.owns_member(member_id) OR private.has_club_right(club_id, 'tournaments')));
drop policy if exists signups_update on public.signups;
create policy signups_update on public.signups
  for update to authenticated
  using ((public.owns_member(member_id) OR private.has_club_right(club_id, 'tournaments')))
  with check ((public.owns_member(member_id) OR private.has_club_right(club_id, 'tournaments')));


-- ===========================================================================
-- KONTROLL (kjøres i samme transaksjon; feiler ved avvik)
-- ===========================================================================
do $$
declare
  v_fail      text := '';
  v_no_owner  integer;
  v_treasurer integer;
begin
  -- 1. Tabellene finnes med RLS, uten skrivepolicyer, og anon har ingen rettigheter.
  if not (select relrowsecurity from pg_class where oid = 'public.club_roles'::regclass)
     or not (select relrowsecurity from pg_class where oid = 'public.club_member_roles'::regclass)
     or exists (select 1 from pg_policies where schemaname = 'public'
                and tablename in ('club_roles', 'club_member_roles') and cmd <> 'SELECT')
     or has_table_privilege('anon', 'public.club_roles', 'select')
     or has_table_privilege('authenticated', 'public.club_member_roles', 'insert') then
    v_fail := v_fail || ' 1';
  end if;
  -- 2. Hver klubb har de fire malene og nøyaktig én eierrolle med alle rettighetene.
  if exists (select 1 from public.clubs c
             where (select count(*) from public.club_roles r
                    where r.club_id = c.id and r.template_key in ('owner', 'organizer', 'treasurer', 'committee')) <> 4
                or (select count(*) from public.club_roles r where r.club_id = c.id and r.is_owner) <> 1)
     or exists (select 1 from public.club_roles r
                where r.is_owner and not (r.rights @> array['tournaments', 'rounds', 'members', 'money'])) then
    v_fail := v_fail || ' 2';
  end if;
  -- 3. Flaggene er lik det rollene gir (speilingen).
  if exists (select 1 from public.club_members m, lateral private.member_flags(m.id) f
             where m.is_organizer <> f.is_organizer or m.is_treasurer <> f.is_treasurer) then
    v_fail := v_fail || ' 3';
  end if;
  -- 4. Hver klubb med en arrangør har en eier.
  if exists (select 1 from public.clubs c
             where exists (select 1 from public.club_members m where m.club_id = c.id and m.is_organizer)
               and not exists (select 1 from public.club_member_roles mr join public.club_roles r on r.id = mr.role_id
                               where mr.club_id = c.id and r.is_owner)) then
    v_fail := v_fail || ' 4';
  end if;
  -- 5. private: rettighetsfunksjonene er security definer med tom search_path, og anon
  --    kommer ikke inn i skjemaet.
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'private' and p.proname in ('has_club_right', 'is_club_owner')
               and (not p.prosecdef or not ('search_path=""' = any (p.proconfig))))
     or (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'private' and p.proname in ('has_club_right', 'is_club_owner')) <> 2
     or has_schema_privilege('anon', 'private', 'usage')
     or not has_schema_privilege('authenticated', 'private', 'usage') then
    v_fail := v_fail || ' 5';
  end if;
  -- 6. RPC-ene finnes, og anon kan ikke kalle dem.
  if has_function_privilege('anon', 'public.club_role_save(uuid, uuid, text, text[])', 'execute')
     or has_function_privilege('anon', 'public.club_role_delete(uuid)', 'execute')
     or has_function_privilege('anon', 'public.club_member_set_roles(uuid, uuid[])', 'execute')
     or has_function_privilege('anon', 'public.club_transfer_ownership(uuid, uuid)', 'execute')
     or has_function_privilege('anon', 'public.is_club_organizer(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.club_member_set_roles(uuid, uuid[])', 'execute') then
    v_fail := v_fail || ' 6';
  end if;
  -- 7. Bare de fire policyene med grunn står på is_club_organizer.
  if exists (select 1 from pg_policies where schemaname = 'public'
             and coalesce(qual, '') || coalesce(with_check, '') like '%is_club_organizer%'
             and policyname not in ('activity_select', 'clubs_update', 'entitlements_select', 'rounds_select'))
     or (select count(*) from pg_policies where schemaname = 'public'
         and coalesce(qual, '') || coalesce(with_check, '') like '%has_club_right%') <> 36 then
    v_fail := v_fail || ' 7';
  end if;
  -- 8. Organisasjonsnummeret.
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'clubs' and column_name = 'org_number')
     or not exists (select 1 from pg_constraint where conname = 'clubs_org_number_check') then
    v_fail := v_fail || ' 8';
  end if;
  -- 9. Triggerne for maler og speiling.
  if (select count(*) from pg_trigger where not tgisinternal and tgname in
        ('clubs_role_templates', 'club_members_roles_mirror', 'club_members_roles_inactive',
         'club_member_roles_sync', 'club_roles_sync')) <> 5 then
    v_fail := v_fail || ' 9';
  end if;
  -- 10. Ingen eier uten å være aktiv arrangør med innlogging der det finnes en slik.
  if exists (select 1 from public.club_member_roles mr
               join public.club_roles r on r.id = mr.role_id and r.is_owner
               join public.club_members m on m.id = mr.member_id
              where not (m.status = 'active' and m.user_id is not null)
                and exists (select 1 from public.club_members o
                            where o.club_id = m.club_id and o.is_organizer
                              and o.status = 'active' and o.user_id is not null)) then
    v_fail := v_fail || ' 10';
  end if;

  if v_fail <> '' then
    raise exception '044 kontroll feilet:%', v_fail;
  end if;

  select count(*) into v_no_owner from public.clubs c
   where not exists (select 1 from public.club_member_roles mr join public.club_roles r on r.id = mr.role_id
                     where mr.club_id = c.id and r.is_owner);
  select count(*) into v_treasurer from public.club_members m
   where m.is_treasurer and not m.is_organizer;
  raise notice '044 kontroll: 10 av 10 (klubber uten eier: %, kasserere uten arrangør som får money: %)',
    v_no_owner, v_treasurer;
end $$;

commit;

-- ===========================================================================
-- RULLEBAKKE (bare før appen bruker rollene; flaggene står som de er speilet)
-- ===========================================================================
-- Rekkefølgen betyr noe: policyene og funksjonene i public som kaller private, må
-- tilbake før skjemaet private slettes.
-- begin;
-- 1. Policyene: kjør blokken «7f» over med private.has_club_right(x, '...') byttet
--    tilbake til public.is_club_organizer(x) (36 policyer, uttrykkene ellers like).
-- 2. Funksjonene: gjenopprett fra filene som står over hver av dem («Fra 0NN»):
--    is_competition_admin, is_round_organizer, can_score (032), can_link_round (017),
--    start_round (006), set_round_setup og delete_round (001), confirm_round_par (018),
--    save_course og confirm_course (002), create_competition (026),
--    set_event_committee (005), resolve_bet, settle_bet og mark_bets_closed (012),
--    resolve_report og delete_account_data (019), guard_club_members (024), og
-- create or replace function public.is_club_organizer(p_club_id uuid)
-- returns boolean language sql stable security definer set search_path = '' as $$
--   select exists (select 1 from public.club_members m
--                  where m.club_id = p_club_id and m.user_id = auth.uid()
--                    and m.status = 'active' and m.is_organizer);
-- $$;
-- 3. Rollene:
-- drop function if exists public.club_role_save(uuid, uuid, text, text[]);
-- drop function if exists public.club_role_delete(uuid);
-- drop function if exists public.club_member_set_roles(uuid, uuid[]);
-- drop function if exists public.club_transfer_ownership(uuid, uuid);
-- drop trigger if exists club_members_roles_mirror on public.club_members;
-- drop trigger if exists clubs_role_templates on public.clubs;
-- drop table if exists public.club_member_roles;
-- drop table if exists public.club_roles;
-- drop schema if exists private cascade;
-- alter table public.club_members drop constraint if exists club_members_club_id_id_key;
-- alter table public.clubs drop constraint if exists clubs_org_number_check;
-- alter table public.clubs drop column if exists org_number;
-- commit;
