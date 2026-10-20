-- 062: utløserne leser prosjektadressen og nøklene fra Vault (prod-klargjøringen 20.10.2026).
--
-- Hvorfor:
--   * 052b har test-adressen hardkodet, så fila kan ikke kjøres på prod som den er.
--   * Webhooken dd18_push_queue (010) og cron-jobbene dd18-slope-sync (029),
--     dd18-waitlist-offers (032) og dd18-paaminnelse (010) står bare som kommentar i
--     filene. På test ble de laget for hånd i dashboardet.
--   * Webhooken har x-push-secret i klartekst i triggerdefinisjonen
--     (supabase_functions.http_request), lesbar for alle som kan lese pg_trigger.
--
-- Etter 062 lages alt av SQL, og den samme fila virker på test og prod:
--   * private.project_url() leser Vault-hemmeligheten project_url
--     (f.eks. https://tsekialrxuhrugscosgi.supabase.co).
--   * private.push_send_kick() erstatter webhooken: pg_net-kall per ny rad i push_queue
--     med x-push-secret fra Vault (push_hook_secret). push-send leser bare headeren,
--     ikke innholdet, så kallet er det samme som før.
--   * private.bet_settle_kick() (052b) og alle fire cron-jobbene bruker project_url().
--   * Mangler en hemmelighet, gjør utløseren ingenting (som 052b). Kontrollen nederst
--     sier fra.
--
-- Krever: 010, 029, 032, 052b, og extensions pg_cron og pg_net.
-- Hemmelighetene opprettes én gang per prosjekt, før eller etter denne fila (aldri i git):
--   select vault.create_secret('https://<ref>.supabase.co', 'project_url');
--   select vault.create_secret('<samme verdi som PUSH_HOOK_SECRET>', 'push_hook_secret');
--   select vault.create_secret('<samme verdi som BET_SETTLE_SECRET>', 'bet_settle_secret');
--   select vault.create_secret('<samme verdi som SLOPE_SYNC_SECRET>', 'slope_sync_secret');
--
-- Rullebakke nederst. Idempotent.

begin;

-- --- Prosjektadressen ---------------------------------------------------------
create or replace function private.project_url()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select rtrim(s.decrypted_secret, '/')
    from vault.decrypted_secrets s where s.name = 'project_url';
$$;
revoke all on function private.project_url() from public, anon, authenticated;

-- --- Push: erstatter Database Webhook-en ---------------------------------------
create or replace function private.push_send_kick()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url    text := private.project_url();
  v_secret text;
begin
  select s.decrypted_secret into v_secret
    from vault.decrypted_secrets s where s.name = 'push_hook_secret';
  if v_url is null or v_secret is null then
    return null;  -- Ikke satt opp. Linja står fortsatt i Varsler i appen.
  end if;
  perform net.http_post(
    url := v_url || '/functions/v1/push-send',
    headers := jsonb_build_object('content-type', 'application/json', 'x-push-secret', v_secret),
    body := '{}'::jsonb,
    timeout_milliseconds := 5000);
  return null;
exception when others then
  -- Et feilet kall skal aldri stoppe meldingen eller runden.
  return null;
end;
$$;
revoke all on function private.push_send_kick() from public, anon, authenticated;

-- Én per rad, som webhooken (push-send tar høyst 20 jobber per kall).
drop trigger if exists dd18_push_queue on public.push_queue;
create trigger dd18_push_queue
  after insert on public.push_queue
  for each row execute function private.push_send_kick();

-- --- Veddemål: 052b uten hardkodet adresse ------------------------------------
create or replace function private.bet_settle_kick()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url    text := private.project_url();
  v_secret text;
begin
  select s.decrypted_secret into v_secret
    from vault.decrypted_secrets s where s.name = 'bet_settle_secret';
  if v_url is null or v_secret is null then
    return null;  -- Ikke satt opp: cron tar det når nøkkelen finnes.
  end if;
  perform net.http_post(
    url := v_url || '/functions/v1/bet-settle',
    headers := jsonb_build_object('content-type', 'application/json', 'x-bet-secret', v_secret),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000);
  return null;
exception when others then
  -- Et feilet kall skal aldri stoppe låsingen av runden; cron prøver igjen.
  return null;
end;
$$;
revoke all on function private.bet_settle_kick() from public, anon, authenticated;

-- --- Cron-jobbene -----------------------------------------------------------------
-- cron.schedule med samme navn erstatter jobben.
select cron.schedule('dd18-veddemaal', '*/5 * * * *', $cron$
  select net.http_post(
    url := private.project_url() || '/functions/v1/bet-settle',
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'x-bet-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'bet_settle_secret')),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000)
  where exists (select 1 from public.bet_settle_queue where done_at is null)
    and private.project_url() is not null
$cron$);

select cron.schedule('dd18-slope-sync', '17 3 * * *', $cron$
  select net.http_post(
    url := private.project_url() || '/functions/v1/slope-sync',
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'x-sync-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'slope_sync_secret')),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000)
  where private.project_url() is not null
$cron$);

select cron.schedule('dd18-waitlist-offers', '*/10 * * * *', $cron$
  select public.expire_competition_offers()
$cron$);

select cron.schedule('dd18-paaminnelse', '0 8 * * *', $cron$
  select public.queue_evening_reminders(7)
$cron$);

-- --- Kontroll -----------------------------------------------------------------------
do $$
declare
  v_missing text;
begin
  if not exists (select 1 from pg_trigger where tgname = 'dd18_push_queue'
                   and tgfoid = 'private.push_send_kick()'::regprocedure) then
    raise exception '062: push-triggeren peker ikke på private.push_send_kick';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'bet_settle_queue_kick') then
    raise exception '062: triggeren fra 052b mangler';
  end if;
  if (select count(*) from cron.job where jobname in
        ('dd18-veddemaal', 'dd18-slope-sync', 'dd18-waitlist-offers', 'dd18-paaminnelse')) <> 4 then
    raise exception '062: cron-jobbene mangler';
  end if;
  if exists (select 1 from cron.job where command like '%.supabase.co%') then
    raise exception '062: en cron-jobb har fortsatt en hardkodet adresse';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public', 'private') and p.prosrc like '%.supabase.co%') then
    raise exception '062: en funksjon har fortsatt en hardkodet adresse';
  end if;
  select string_agg(n, ', ') into v_missing
    from unnest(array['project_url', 'push_hook_secret', 'bet_settle_secret', 'slope_sync_secret']) n
   where not exists (select 1 from vault.secrets s where s.name = n);
  if v_missing is not null then
    raise notice '062: disse Vault-hemmelighetene mangler ennå: %', v_missing;
  end if;
  raise notice '062 kontroll: 5 av 5';
end $$;

commit;

-- KONTROLL ETTERPÅ (bare lesing)
-- 1) Ingen adresse og ingen nøkkel i triggere eller cron-jobber. Forventet: 0 rader.
-- select tgname from pg_trigger where pg_get_triggerdef(oid) like '%secret%';
-- select jobname from cron.job where command like '%.supabase.co%';
-- 2) Siste kall fra pg_net etter en ny push-jobb. Forventet: status_code 200.
-- select id, status_code, created from net._http_response order by id desc limit 5;

-- RULLEBAKKE (tilbake til 052b; webhooken må da lages på nytt i dashboardet)
-- begin;
-- drop trigger if exists dd18_push_queue on public.push_queue;
-- drop function if exists private.push_send_kick();
-- select cron.unschedule(j) from unnest(array['dd18-slope-sync', 'dd18-waitlist-offers', 'dd18-paaminnelse']) j
--   where exists (select 1 from cron.job where jobname = j);
-- -- og kjør 052b på nytt
-- drop function if exists private.project_url();
-- commit;
