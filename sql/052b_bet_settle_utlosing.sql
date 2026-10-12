-- 052b: utløser for oppgjør av veddemål på serveren (gjennomføringsplanen steg 11).
-- Godkjent av Thomas 12.10.2026 («kjør 052 og sett opp oppgjøret»).
--
-- Edge Function bet-settle (supabase/functions/bet-settle) gjør opp åpne veddemål med
-- vilkår når en runde låses. Den kalles to veier:
--   1. Straks: en trigger på bet_settle_queue (ny rad) sender et kall med pg_net.
--   2. Sikkerhetsnett: pg_cron hvert femte minutt (feilede jobber, runder som låses på
--      nytt og derfor oppdaterer køraden i stedet for å lage en ny).
-- Nøkkelen (x-bet-secret) ligger i Vault som bet_settle_secret og som secret
-- BET_SETTLE_SECRET på funksjonen. Den står aldri i git. Opprettes slik (én gang):
--   select vault.create_secret('<samme verdi som BET_SETTLE_SECRET>', 'bet_settle_secret');
-- Kallet er asynkront (pg_net); låsingen av runden venter ikke på det.
--
-- Rullebakke nederst. Idempotent.

begin;

create or replace function private.bet_settle_kick()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_secret text;
begin
  select s.decrypted_secret into v_secret
    from vault.decrypted_secrets s where s.name = 'bet_settle_secret';
  if v_secret is null then
    return null;  -- Ikke satt opp: cron tar det når nøkkelen finnes.
  end if;
  perform net.http_post(
    url := 'https://tsekialrxuhrugscosgi.supabase.co/functions/v1/bet-settle',
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

drop trigger if exists bet_settle_queue_kick on public.bet_settle_queue;
create trigger bet_settle_queue_kick
  after insert on public.bet_settle_queue
  for each statement execute function private.bet_settle_kick();

select cron.unschedule('dd18-veddemaal') where exists (select 1 from cron.job where jobname = 'dd18-veddemaal');
select cron.schedule('dd18-veddemaal', '*/5 * * * *', $cron$
  select net.http_post(
    url := 'https://tsekialrxuhrugscosgi.supabase.co/functions/v1/bet-settle',
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'x-bet-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'bet_settle_secret')),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000)
  where exists (select 1 from public.bet_settle_queue where done_at is null)
$cron$);

-- Kontroll
do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'bet_settle_queue_kick') then
    raise exception '052b: triggeren mangler';
  end if;
  if not exists (select 1 from cron.job where jobname = 'dd18-veddemaal') then
    raise exception '052b: cron-jobben mangler';
  end if;
  raise notice '052b kontroll: 2 av 2';
end $$;

commit;

-- RULLEBAKKE
-- begin;
-- select cron.unschedule('dd18-veddemaal');
-- drop trigger if exists bet_settle_queue_kick on public.bet_settle_queue;
-- drop function if exists private.bet_settle_kick();
-- commit;
