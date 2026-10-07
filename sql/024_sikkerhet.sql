-- ===========================================================================
-- 024 – SIKKERHET FØR ÅPEN APP – FORSLAG, IKKE KJØRT
-- ===========================================================================
-- Status: FORSLAG til godkjenning (ROADMAP B5). IKKE KJØRT mot Supabase,
-- verken test eller prod. Prøvd lokalt (lokal/024_prove.sql og de eldre
-- rolleprøvene). Krever 001–021 (019 inkludert). Uavhengig av 022 og 023.
--
-- Hvorfor: sikkerhetsrevisjonen i docs/sikkerhet-database.md. Når hvem som
-- helst kan registrere seg, er en fremmed en innlogget bruker med egen klubb
-- (create_club gjør deg til arrangør). Denne fila retter funnene som kan
-- rettes trygt i databasen:
--
--   H1  En arrangør kunne koble en hvilken som helst innlogging (user_id) til
--       et navn i sin egen klubb. Offeret ble da «medlem» uten å vite det: den
--       fremmede fikk se profilen, kunne legge offeret til i runder og
--       konkurranser (can_see_profile) og sende push til telefonen. Nå kan
--       user_id bare settes til deg selv (join_club) eller tømmes.
--   H2  Et ledig navn med rolle (arrangør/kasserer, f.eks. kommissæren fra
--       importen, eller et navn der arrangøren har koblet fra innloggingen)
--       kunne tas med invitasjonskoden, og den som tok det, ble arrangør med
--       én gang. Nå mister navnet rollene når det tas, så lenge klubben har
--       en annen aktiv arrangør med innlogging. (Har klubben ingen, beholdes
--       rollene, ellers blir klubben låst ute. Se rapporten om importen.)
--   M1  Klubbens invitasjonskode var 10 hex-tegn (40 bit) uten utløp eller
--       hastighetsgrense. Nye klubber får 12 tegn fra et alfabet på 32 tegn
--       (60 bit) uten 0/O og 1/I. Eksisterende koder endres ikke (det ville
--       ugyldiggjort delte lenker); rotér dem når appen har knappen.
--   M2  Ingen kvoter: én konto kunne lage ubegrenset med klubber, løse runder,
--       konkurranser og baner i det felles biblioteket (som ALLE ser), og
--       sende ubegrenset med meldinger og hendelser (push til hele klubben).
--       Nå: rause grenser per innlogging (se avsnitt 3). Bare innloggede
--       telles; SQL Editor, importen og service_role (auth.uid() tom) slipper.
--   L1  rls_auto_enable() (Supabase sin event trigger-funksjon) kunne kalles
--       av anon via /rest/v1/rpc. Den gjør ingenting utenfor en event trigger,
--       men advisoren melder den. Tas fra public, anon og authenticated.
--   L2  Standardrettighetene i public ga anon (og PUBLIC) alt på nye tabeller
--       og funksjoner («anon-fella» i README). Nå får ikke anon noe av seg
--       selv, og nye funksjoner er ikke åpne for PUBLIC. Hver migrering
--       grant-er fortsatt eksplisitt til authenticated, som før.
--
-- Ingen policy endres. Ingen kolonne endres. join_club og club_preview er
-- urørt (vakta gjør jobben, også for direkte UPDATE).
--
-- Mønsteret fra 001–021 følges: én transaksjon, idempotent, `set search_path
-- = ''`, `revoke … from public, anon` ETTER hver create or replace, og
-- triggerfunksjoner tas fra authenticated også.
-- ===========================================================================

begin;


-- ===========================================================================
-- 1. VAKTA PÅ club_members (H1 og H2)
-- ===========================================================================
-- Som i 001, med tre tillegg (merket NYTT):
--   * INSERT: user_id er tom eller deg selv, også for arrangøren.
--   * UPDATE: user_id kan bare settes til deg selv (fra tom) eller tømmes.
--   * Tar du et ledig navn med roller, mister det rollene når klubben har en
--     annen aktiv arrangør med innlogging.
create or replace function public.guard_club_members()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid        uuid := auth.uid();
  v_organizer  boolean;
begin
  if v_uid is null then
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

  v_organizer := public.is_club_organizer(new.club_id);

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
    if old.user_id is null and new.user_id = v_uid
       and (new.is_organizer or new.is_treasurer)
       and exists (select 1 from public.club_members m
                   where m.club_id = new.club_id and m.id <> new.id
                     and m.is_organizer and m.status = 'active' and m.user_id is not null) then
      new.is_organizer := false;
      new.is_treasurer := false;
    end if;
  end if;

  -- Siste arrangør kan ikke fjerne seg selv (eller bli fjernet), ellers er
  -- klubben låst ute. Nødutgang: SQL Editor.
  if old.is_organizer and old.status = 'active' and old.user_id is not null
     and (not new.is_organizer or new.status <> 'active' or new.user_id is null)
     and not exists (select 1 from public.club_members m
                     where m.club_id = old.club_id and m.id <> old.id
                       and m.is_organizer and m.status = 'active'
                       and m.user_id is not null) then
    raise exception 'Klubben må ha minst én arrangør' using errcode = '42501';
  end if;

  return new;
end;
$$;
revoke all on function public.guard_club_members() from public, anon, authenticated;

drop trigger if exists club_members_guard on public.club_members;
create trigger club_members_guard
  before insert or update on public.club_members
  for each row execute function public.guard_club_members();


-- ===========================================================================
-- 2. LENGRE INVITASJONSKODE FOR NYE KLUBBER (M1)
-- ===========================================================================
-- 12 tegn fra 23456789ABCDEFGHJKLMNPQRSTUVWXYZ (32 tegn = 5 bit per tegn,
-- 60 bit). Ingen 0/O eller 1/I å forveksle. Passer clubs_join_code_check
-- (^[A-Z0-9]{6,16}$). Byte % 32 er jevnt fordelt (256 = 8 · 32).
create or replace function public.club_join_code()
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_alphabet constant text := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  v_bytes    bytea := uuid_send(gen_random_uuid()) || uuid_send(gen_random_uuid());
  v_code     text := '';
  v_i        integer;
begin
  -- Hopp over versjons- og variantbytene i hvert uuid (6, 8, 22, 24).
  foreach v_i in array array[0, 1, 2, 3, 4, 5, 9, 10, 11, 12, 13, 14] loop
    v_code := v_code || substr(v_alphabet, (get_byte(v_bytes, v_i) % 32) + 1, 1);
  end loop;
  return v_code;
end;
$$;
revoke all on function public.club_join_code() from public, anon, authenticated;

alter table public.clubs alter column join_code set default public.club_join_code();


-- ===========================================================================
-- 3. KVOTER PER INNLOGGING (M2)
-- ===========================================================================
-- Rause grenser som ingen vanlig bruk når. Feilkode 54000
-- (program_limit_exceeded) med en norsk melding. Bare når auth.uid() er satt.
--   clubs                 10 nye klubber per døgn (der du er arrangør)
--   courses (bibliotek)   30 nye felles baner per døgn
--   rounds (løse)         50 nye løse runder per døgn
--   competitions (egne)   30 nye konkurranser uten klubb per døgn
--   round_participants    48 deltakere per runde (som claim_round_invite)
--   thread_messages       60 meldinger per medlem per 10 minutter
--   activity             200 hendelser per medlem per 10 minutter
-- Triggeren heter zz_quota, så den går etter de andre BEFORE-triggerne
-- (navnene sorteres) og ser verdiene de har satt.
create or replace function public.quota_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := auth.uid();
  v_n      integer;
  v_limit  integer;
  v_what   text;
begin
  if v_uid is null then
    return new;
  end if;

  if tg_table_name = 'clubs' then
    v_limit := 10; v_what := 'nye klubber i døgnet';
    select count(*) into v_n from public.club_members m
     where m.user_id = v_uid and m.is_organizer and m.created_at > now() - interval '1 day';
  elsif tg_table_name = 'courses' then
    if new.club_id is not null then return new; end if;
    v_limit := 30; v_what := 'nye baner i det felles biblioteket i døgnet';
    select count(*) into v_n from public.courses c
     where c.club_id is null and c.created_by_profile = v_uid and c.created_at > now() - interval '1 day';
  elsif tg_table_name = 'rounds' then
    if new.club_id is not null then return new; end if;
    v_limit := 50; v_what := 'nye runder i døgnet';
    select count(*) into v_n from public.rounds r
     where r.club_id is null and r.owner_id = v_uid and r.created_at > now() - interval '1 day';
  elsif tg_table_name = 'competitions' then
    if new.club_id is not null then return new; end if;
    v_limit := 30; v_what := 'nye konkurranser i døgnet';
    select count(*) into v_n from public.competitions c
     where c.club_id is null and c.owner_id = v_uid and c.created_at > now() - interval '1 day';
  elsif tg_table_name = 'round_participants' then
    v_limit := 48; v_what := 'deltakere i én runde';
    select count(*) into v_n from public.round_participants p where p.round_id = new.round_id;
  elsif tg_table_name = 'thread_messages' then
    v_limit := 60; v_what := 'meldinger på ti minutter';
    select count(*) into v_n from public.thread_messages t
     where t.member_id = new.member_id and t.created_at > now() - interval '10 minutes';
  elsif tg_table_name = 'activity' then
    if new.actor_member_id is null then return new; end if;
    v_limit := 200; v_what := 'hendelser på ti minutter';
    select count(*) into v_n from public.activity a
     where a.club_id = new.club_id and a.actor_member_id = new.actor_member_id
       and a.created_at > now() - interval '10 minutes';
  else
    return new;
  end if;

  if v_n >= v_limit then
    raise exception 'Grensen er nådd: høyst % %. Prøv igjen senere.', v_limit, v_what
      using errcode = '54000';
  end if;
  return new;
end;
$$;
revoke all on function public.quota_guard() from public, anon, authenticated;

do $$
declare
  t text;
begin
  foreach t in array array['clubs', 'courses', 'rounds', 'competitions', 'round_participants',
                           'thread_messages', 'activity'] loop
    execute format('drop trigger if exists zz_quota on public.%I', t);
    execute format('create trigger zz_quota before insert on public.%I '
                   'for each row execute function public.quota_guard()', t);
  end loop;
end $$;

-- Tellingene bruker disse oppslagene.
create index if not exists courses_library_creator_idx
  on public.courses (created_by_profile, created_at) where club_id is null;
create index if not exists competitions_owner_created_idx
  on public.competitions (owner_id, created_at) where club_id is null;
create index if not exists activity_actor_time_idx
  on public.activity (actor_member_id, created_at) where actor_member_id is not null;
create index if not exists thread_messages_member_time_idx
  on public.thread_messages (member_id, created_at);


-- ===========================================================================
-- 4. SUPABASE SIN rls_auto_enable() (L1)
-- ===========================================================================
-- Finnes bare i Supabase (event trigger som slår på RLS for nye tabeller).
-- Event triggeren trenger ikke EXECUTE for å kjøre.
do $$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    revoke all on function public.rls_auto_enable() from public, anon, authenticated;
  end if;
end $$;


-- ===========================================================================
-- 5. STANDARDRETTIGHETER FOR NYE OBJEKTER (L2)
-- ===========================================================================
-- Gjelder objekter postgres lager etter dette. Eksisterende objekter røres
-- ikke. Det globale PUBLIC-EXECUTE kan bare tas bort uten «in schema».
alter default privileges for role postgres in schema public revoke all on tables from anon;
alter default privileges for role postgres in schema public revoke all on sequences from anon;
alter default privileges for role postgres in schema public revoke all on functions from anon;
alter default privileges for role postgres revoke execute on functions from public;

commit;


-- ===========================================================================
-- KONTROLL (kjør i SQL Editor etter fila, som én kjøring). Én rad per sjekk,
-- alle skal ha ok = true.
-- ===========================================================================
-- with f as (select p.proname,
--                   has_function_privilege('anon', p.oid, 'execute') as anon_kan,
--                   has_function_privilege('authenticated', p.oid, 'execute') as auth_kan
--            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--            where n.nspname = 'public'
--              and p.proname in ('guard_club_members', 'club_join_code', 'quota_guard', 'rls_auto_enable'))
-- select 1 as nr, 'anon og authenticated kan ikke kjøre de nye/endrede funksjonene' as sjekk,
--        not exists (select 1 from f where anon_kan or auth_kan) as ok
-- union all
-- select 2, 'vakta på club_members har H1-sjekken',
--        pg_get_functiondef('public.guard_club_members()'::regprocedure) like '%Bare personen selv kan koble%'
--        and exists (select 1 from pg_trigger where not tgisinternal and tgname = 'club_members_guard'
--                      and tgrelid = 'public.club_members'::regclass)
-- union all
-- select 3, 'nye klubber får 60-bits kode',
--        (select pg_get_expr(d.adbin, d.adrelid) from pg_attrdef d
--          join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
--          where d.adrelid = 'public.clubs'::regclass and a.attname = 'join_code') = 'club_join_code()'
--        and char_length(public.club_join_code()) = 12
-- union all
-- select 4, 'kvotetriggeren står på sju tabeller',
--        (select count(*) = 7 from pg_trigger where not tgisinternal and tgname = 'zz_quota')
-- union all
-- select 5, 'ingen funksjon i public kan kjøres av anon',
--        not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--                    where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute'))
-- union all
-- select 6, 'nye tabeller og funksjoner i public gir ikke anon noe',
--        not exists (select 1 from pg_default_acl d
--                    where pg_get_userbyid(d.defaclrole) = 'postgres'
--                      and d.defaclnamespace = 'public'::regnamespace
--                      and d.defaclacl::text like '%anon=%')
-- union all
-- select 7, 'ingen ledige navn med roller står igjen (rydd ellers med arrangøren)',
--        not exists (select 1 from public.club_members where user_id is null and (is_organizer or is_treasurer))
-- union all
-- select 8, 'policyene er urørt (club_members har fire)',
--        (select count(*) = 4 from pg_policies where schemaname = 'public' and tablename = 'club_members')
-- order by nr;


-- ===========================================================================
-- RULLEBAKKE (bare test). Setter alt tilbake til 001–021. Ingen data endres
-- (navn som har mistet roller ved H2, får dem ikke tilbake av seg selv).
-- Vakta fra 001 må limes inn igjen: kjør create or replace-blokken for
-- guard_club_members fra 001_skjema_v1.sql (linje 694–777) etter dette.
-- ===========================================================================
-- begin;
-- do $$ declare t text; begin
--   foreach t in array array['clubs', 'courses', 'rounds', 'competitions', 'round_participants',
--                            'thread_messages', 'activity'] loop
--     execute format('drop trigger if exists zz_quota on public.%I', t);
--   end loop; end $$;
-- drop function if exists public.quota_guard();
-- drop index if exists public.courses_library_creator_idx;
-- drop index if exists public.competitions_owner_created_idx;
-- drop index if exists public.activity_actor_time_idx;
-- drop index if exists public.thread_messages_member_time_idx;
-- alter table public.clubs alter column join_code
--   set default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
-- drop function if exists public.club_join_code();
-- alter default privileges for role postgres in schema public grant all on tables to anon;
-- alter default privileges for role postgres in schema public grant all on sequences to anon;
-- alter default privileges for role postgres in schema public grant all on functions to anon;
-- alter default privileges for role postgres grant execute on functions to public;
-- do $$ begin
--   if to_regprocedure('public.rls_auto_enable()') is not null then
--     grant execute on function public.rls_auto_enable() to public, anon, authenticated;
--   end if; end $$;
-- commit;
-- -- Så: guard_club_members fra 001 (se over).
