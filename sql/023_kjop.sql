-- ===========================================================================
-- 023 – KJØP FOR Å KJØRE TURNERING (FASE 17, StoreKit 2) – FORSLAG, IKKE KJØRT
-- ===========================================================================
-- Status: FORSLAG til godkjenning (ROADMAP B5). Ikke kjørt mot Supabase, verken
-- test eller prod. Prøvd lokalt (lokal/023_prove.sql). Krever 001–018
-- (entitlements og competitions fra 017). 022 er fase 15 og røres ikke, men
-- kjøres før 023 (README).
--
-- Besluttet 07.10.2026: bare liga og cup krever kjøp. Morroturneringer (fun),
-- sesongen (jakkeracet) og spill på runden (game) er gratis.
--
-- Hvorfor (docs/visjon-apen-app.md, «Besluttet 07.10.2026» punkt 4): appen er
-- gratis, men å kjøre en turnering koster. Det må være kjøp i appen (StoreKit),
-- fordi Apple krever det for alt som låser opp funksjoner. Kjøpet sjekkes på
-- serveren (Edge Function verify-purchase mot App Store Server API), og bare
-- serveren skriver entitlements.
--
-- Produktene (docs/app-store.md):
--   no.dashdash.turnering.sesong   FORBRUKBAR. Låser opp én turnering (liga
--                                  eller cup) så lenge den varer.
--                                  Ikke-forbrukbar går ikke: et slikt kjøp kan
--                                  bare gjøres én gang per Apple-ID, og da kunne
--                                  ingen kjøre turnering nummer to.
--   no.dashdash.turnering.ar       ABONNEMENT (årlig, valgfritt senere). Alle
--                                  turneringene eieren eller klubben kjører,
--                                  så lenge abonnementet løper.
-- Et forbrukbart kjøp gjenopprettes ikke av App Store. Derfor er serverens
-- entitlements fasiten: «Gjenopprett kjøp» i appen leser dem, og et kjøp som
-- ikke ble koblet til en turnering (appen ble lukket midt i), står som en
-- ledig «kreditt» som kan kobles senere (assign_purchase).
--
-- Hva fila gjør:
--   1. entitlements får competition_id (turneringen kjøpet låser opp),
--      product_kind, transaction_id, app_account_token og revoked_at.
--   2. record_purchase(…): bare service_role (Edge Function). Upsert på
--      original_transaction_id. Et kjøp kan aldri flyttes til en annen
--      profil. Kobler til turneringen når kjøperen styrer den.
--   3. assign_purchase(kjøp, turnering): koble en ledig kreditt til en
--      turnering du styrer.
--   4. competition_is_unlocked(turnering): sant når turneringen ikke krever
--      kjøp, eller et aktivt kjøp eller abonnement låser den opp.
--   5. Nye turneringer av typen league og cup krever kjøp
--      (requires_purchase settes av serveren). Morroturneringer (fun),
--      sesongens konkurranse (jakkeracet) og spill på runden (game) er
--      gratis. Eksisterende rader endres ikke.
--
-- Mønsteret fra 001–021 følges.
-- ===========================================================================

begin;


-- ===========================================================================
-- 1. KOLONNER
-- ===========================================================================
alter table public.entitlements
  add column if not exists competition_id uuid references public.competitions(id) on delete set null,
  add column if not exists product_kind text not null default 'consumable'
    check (product_kind in ('consumable', 'non_consumable', 'subscription')),
  add column if not exists transaction_id text check (transaction_id is null or char_length(transaction_id) <= 64),
  add column if not exists app_account_token uuid,
  add column if not exists revoked_at timestamptz;
comment on column public.entitlements.competition_id is
  'Turneringen et forbrukbart kjøp låser opp. Tom = ledig kreditt (kobles med assign_purchase).';
create index if not exists entitlements_competition_idx on public.entitlements (competition_id)
  where competition_id is not null;
-- Ett aktivt forbrukbart kjøp per turnering.
create unique index if not exists entitlements_one_per_competition
  on public.entitlements (competition_id)
  where competition_id is not null and status = 'active' and product_kind = 'consumable';


-- ===========================================================================
-- 2. HJELPERE
-- ===========================================================================
-- Styrer profilen turneringen? (Eieren, eller arrangør i klubben.) Brukes av
-- serveren, som ikke har auth.uid().
create or replace function public.profile_admins_competition(p_profile_id uuid, p_competition_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.competitions c
    where c.id = p_competition_id
      and (   (c.club_id is null and c.owner_id = p_profile_id)
           or exists (select 1 from public.club_members m
                      where m.club_id = c.club_id and m.user_id = p_profile_id
                        and m.status = 'active' and m.is_organizer)));
$$;
revoke all on function public.profile_admins_competition(uuid, uuid) from public, anon, authenticated;
grant execute on function public.profile_admins_competition(uuid, uuid) to service_role;

-- Er turneringen låst opp? Ingen krav om kjøp, eller et aktivt kjøp (koblet
-- til turneringen eller pekt på av competitions.entitlement_id), eller et
-- løpende abonnement for eieren eller klubben.
create or replace function public.competition_unlocked_by_purchase(p_competition_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.competitions c
    where c.id = p_competition_id
      and (   not c.requires_purchase
           or exists (select 1 from public.entitlements e
                      where e.status = 'active'
                        and (e.competition_id = c.id or e.id = c.entitlement_id))
           or exists (select 1 from public.entitlements e
                      where e.status = 'active' and e.product_kind = 'subscription'
                        and (e.expires_at is null or e.expires_at > now())
                        and (   (c.club_id is null and e.profile_id = c.owner_id and e.club_id is null)
                             or (c.club_id is not null and e.club_id = c.club_id)))));
$$;
revoke all on function public.competition_unlocked_by_purchase(uuid) from public, anon, authenticated;
grant execute on function public.competition_unlocked_by_purchase(uuid) to service_role;

-- For appen: bare turneringer du kan se.
create or replace function public.competition_is_unlocked(p_competition_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if not public.can_read_competition(p_competition_id) then
    raise exception 'Fant ikke turneringen' using errcode = 'P0002';
  end if;
  return public.competition_unlocked_by_purchase(p_competition_id);
end;
$$;
revoke all on function public.competition_is_unlocked(uuid) from public, anon;
grant execute on function public.competition_is_unlocked(uuid) to authenticated;


-- ===========================================================================
-- 3. KJØP FRA SERVEREN (Edge Function verify-purchase)
-- ===========================================================================
-- p: {profile_id, product_id, product_kind, original_transaction_id,
--     transaction_id, environment, status, purchased_at, expires_at,
--     revoked_at, app_account_token, club_id, competition_id}
-- Upsert på original_transaction_id. Samme kjøp fra en annen profil = 42501
-- (en kvittering kan ikke «lånes»). Returnerer raden som jsonb.
create or replace function public.record_purchase(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile      uuid := nullif(p ->> 'profile_id', '')::uuid;
  v_original     text := nullif(p ->> 'original_transaction_id', '');
  v_kind         text := coalesce(nullif(p ->> 'product_kind', ''), 'consumable');
  v_status       text := coalesce(nullif(p ->> 'status', ''), 'active');
  v_competition  uuid := nullif(p ->> 'competition_id', '')::uuid;
  v_club         uuid := nullif(p ->> 'club_id', '')::uuid;
  v_existing     public.entitlements;
  v_row          public.entitlements;
begin
  if v_profile is null or v_original is null or nullif(p ->> 'product_id', '') is null then
    raise exception 'Mangler profil, produkt eller transaksjon' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles pr where pr.id = v_profile) then
    raise exception 'Fant ikke profilen' using errcode = 'P0002';
  end if;

  select * into v_existing from public.entitlements e where e.original_transaction_id = v_original for update;
  if found and v_existing.profile_id is distinct from v_profile then
    raise exception 'Kjøpet tilhører en annen konto' using errcode = '42501';
  end if;

  -- Kobles bare til en turnering kjøperen styrer, og som ikke alt er låst opp
  -- av et annet kjøp. Ellers står kjøpet som ledig kreditt.
  if v_competition is not null
     and (v_kind <> 'consumable' or v_status <> 'active'
          or not public.profile_admins_competition(v_profile, v_competition)
          or exists (select 1 from public.entitlements e
                     where e.competition_id = v_competition and e.status = 'active'
                       and e.product_kind = 'consumable' and e.original_transaction_id <> v_original)) then
    v_competition := null;
  end if;
  -- Et abonnement for en klubb krever at kjøperen er arrangør der.
  if v_club is not null and not exists (select 1 from public.club_members m
                                        where m.club_id = v_club and m.user_id = v_profile
                                          and m.status = 'active' and m.is_organizer) then
    v_club := null;
  end if;

  insert into public.entitlements as e (profile_id, club_id, product_id, product_kind, original_transaction_id,
                                        transaction_id, environment, status, purchased_at, expires_at,
                                        revoked_at, app_account_token, competition_id)
  values (v_profile, v_club, p ->> 'product_id', v_kind, v_original,
          nullif(p ->> 'transaction_id', ''), coalesce(nullif(p ->> 'environment', ''), 'production'), v_status,
          nullif(p ->> 'purchased_at', '')::timestamptz, nullif(p ->> 'expires_at', '')::timestamptz,
          nullif(p ->> 'revoked_at', '')::timestamptz, nullif(p ->> 'app_account_token', '')::uuid, v_competition)
  on conflict (original_transaction_id) do update
    set transaction_id = excluded.transaction_id,
        status         = excluded.status,
        expires_at     = excluded.expires_at,
        revoked_at     = excluded.revoked_at,
        -- En ny kobling vinner, men en eksisterende kobling slettes ikke av et
        -- nytt kall uten turnering (gjenoppretting).
        competition_id = coalesce(excluded.competition_id, e.competition_id),
        club_id        = coalesce(excluded.club_id, e.club_id)
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;
revoke all on function public.record_purchase(jsonb) from public, anon, authenticated;
grant execute on function public.record_purchase(jsonb) to service_role;


-- ===========================================================================
-- 4. KOBLE EN LEDIG KREDITT TIL EN TURNERING (appen)
-- ===========================================================================
create or replace function public.assign_purchase(p_entitlement_id uuid, p_competition_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := auth.uid();
  v_row  public.entitlements;
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select * into v_row from public.entitlements e where e.id = p_entitlement_id for update;
  if not found or v_row.profile_id is distinct from v_uid then
    raise exception 'Fant ikke kjøpet' using errcode = 'P0002';
  end if;
  if v_row.status <> 'active' or v_row.product_kind <> 'consumable' or v_row.competition_id is not null then
    raise exception 'Kjøpet er brukt eller ikke aktivt' using errcode = '55000';
  end if;
  if not public.is_competition_admin(p_competition_id) then
    raise exception 'Bare den som styrer turneringen, kan låse den opp' using errcode = '42501';
  end if;
  if public.competition_unlocked_by_purchase(p_competition_id) then
    raise exception 'Turneringen er allerede låst opp' using errcode = '23505';
  end if;
  update public.entitlements set competition_id = p_competition_id where id = p_entitlement_id;
  return true;
end;
$$;
revoke all on function public.assign_purchase(uuid, uuid) from public, anon;
grant execute on function public.assign_purchase(uuid, uuid) to authenticated;


-- ===========================================================================
-- 5. NYE TURNERINGER KREVER KJØP (league og cup; fun er gratis)
-- ===========================================================================
-- Kjører etter competitions_guard (navnene sorteres), så vakta fra 017 har
-- allerede nektet appen å sette requires_purchase selv.
create or replace function public.competitions_require_purchase()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.season_id is null and not new.is_main and new.kind in ('league', 'cup') then
    new.requires_purchase := true;
  end if;
  return new;
end;
$$;
revoke all on function public.competitions_require_purchase() from public, anon, authenticated;

drop trigger if exists competitions_require_purchase on public.competitions;
create trigger competitions_require_purchase
  before insert on public.competitions
  for each row execute function public.competitions_require_purchase();

commit;


-- ===========================================================================
-- KONTROLL (kjør i SQL Editor etter fila, som én kjøring). Alle ok = true.
-- ===========================================================================
-- with f as (select p.proname,
--                   has_function_privilege('anon', p.oid, 'execute') as anon_kan,
--                   has_function_privilege('authenticated', p.oid, 'execute') as auth_kan,
--                   has_function_privilege('service_role', p.oid, 'execute') as server_kan
--            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--            where n.nspname = 'public'
--              and p.proname in ('profile_admins_competition', 'competition_unlocked_by_purchase',
--                                'competition_is_unlocked', 'record_purchase', 'assign_purchase',
--                                'competitions_require_purchase'))
-- select 1 as nr, 'entitlements har de nye kolonnene' as sjekk,
--        (select count(*) = 5 from information_schema.columns
--          where table_schema = 'public' and table_name = 'entitlements'
--            and column_name in ('competition_id', 'product_kind', 'transaction_id', 'app_account_token', 'revoked_at')) as ok
-- union all
-- select 2, 'appen kan fortsatt bare lese entitlements',
--        has_table_privilege('authenticated', 'public.entitlements', 'select')
--        and not has_table_privilege('authenticated', 'public.entitlements', 'insert')
--        and not has_table_privilege('authenticated', 'public.entitlements', 'update')
-- union all
-- select 3, 'anon kan ikke kjøre noen av funksjonene', not exists (select 1 from f where anon_kan)
-- union all
-- select 4, 'record_purchase er bare for serveren',
--        (select not auth_kan and server_kan from f where proname = 'record_purchase')
-- union all
-- select 5, 'appen kan sjekke og koble, ikke mer',
--        (select bool_and(auth_kan = (proname in ('competition_is_unlocked', 'assign_purchase'))) from f)
-- union all
-- select 6, 'trigger for kjøpskrav finnes',
--        exists (select 1 from pg_trigger where not tgisinternal and tgname = 'competitions_require_purchase')
-- union all
-- select 7, 'ingen turnering har to aktive forbrukbare kjøp',
--        not exists (select competition_id from public.entitlements
--                    where competition_id is not null and status = 'active' and product_kind = 'consumable'
--                    group by competition_id having count(*) > 1)
-- union all
-- select 8, 'bare liga og cup krever kjøp (morro, sesong og spill er gratis)',
--        pg_get_functiondef('public.competitions_require_purchase()'::regprocedure) like '%(''league'', ''cup'')%'
--        and pg_get_functiondef('public.competitions_require_purchase()'::regprocedure) not like '%''fun''%'
-- order by nr;


-- ===========================================================================
-- RULLEBAKKE (bare test). Kjøp som er registrert, står igjen i entitlements
-- (uten de nye kolonnene). Slå av PurchaseFeature i appen først.
-- ===========================================================================
-- begin;
-- drop trigger if exists competitions_require_purchase on public.competitions;
-- drop function if exists public.competitions_require_purchase();
-- drop function if exists public.assign_purchase(uuid, uuid);
-- drop function if exists public.record_purchase(jsonb);
-- drop function if exists public.competition_is_unlocked(uuid);
-- drop function if exists public.competition_unlocked_by_purchase(uuid);
-- drop function if exists public.profile_admins_competition(uuid, uuid);
-- drop index if exists public.entitlements_one_per_competition;
-- drop index if exists public.entitlements_competition_idx;
-- alter table public.entitlements drop column if exists competition_id, drop column if exists product_kind,
--   drop column if exists transaction_id, drop column if exists app_account_token, drop column if exists revoked_at;
-- commit;
