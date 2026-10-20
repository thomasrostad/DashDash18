-- 063: e-post ved ny rapport (fase 17, App Store 1.2: rapporter følges opp innen 24 timer).
--
-- Hva:
--   * private.report_alert_kick(): AFTER INSERT-trigger per rad på public.content_reports.
--     Kaller Edge Function-en report-alert med pg_net, header x-report-secret fra Vault
--     (report_alert_secret) og body {"report_id": "<uuid>"}. Samme mønster som
--     push_send_kick i 062: adressen fra private.project_url(), ingen nøkler i SQL.
--   * Mangler adressen eller hemmeligheten, gjør triggeren ingenting. En feil i kallet
--     stopper aldri rapporten (exception when others).
--   * public.report_alert_payload(rapport): et lite jsonb-objekt for e-posten (type, grunn,
--     hvem som rapporterte og hvem innholdet er fra, med navn og aldri e-post, utdrag av
--     innholdet på høyst 300 tegn, klubb eller turnering, tidspunkt). Bare service_role.
--
-- Rapporterer noen det samme på nytt mens den forrige er åpen, oppdaterer report_content
-- raden (on conflict do update). Det er ingen ny INSERT, så da kommer ingen ny e-post.
--
-- Krever: 019, 050 (competition_id, 'comment'), 062 (private.project_url) og pg_net.
-- Hemmeligheten opprettes én gang per prosjekt (aldri i git), samme verdi som
-- REPORT_ALERT_SECRET i Edge Function-en:
--   select vault.create_secret('<lang tilfeldig verdi>', 'report_alert_secret');
--
-- Rullebakke nederst. Idempotent.

begin;

-- --- Innholdet i e-posten -------------------------------------------------------
create or replace function public.report_alert_payload(p_report_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id',               r.id,
    'kind',             r.kind,
    'reason',           r.reason,
    'note',             left(r.note, 300),
    'excerpt',          left(r.snapshot, 300),
    'status',           r.status,
    'created_at',       r.created_at,
    'reporter_name',    coalesce(rp.display_name,
                          (select m.display_name from public.club_members m
                            where m.user_id = r.reporter_id and m.club_id = r.club_id
                            order by m.created_at limit 1)),
    'target_name',      coalesce(tp.display_name,
                          (select m.display_name from public.club_members m
                            where m.user_id = r.target_profile_id and m.club_id = r.club_id
                            order by m.created_at limit 1)),
    'club_name',        c.name,
    'competition_name', k.name)
  from public.content_reports r
  left join public.profiles rp on rp.id = r.reporter_id
  left join public.profiles tp on tp.id = r.target_profile_id
  left join public.clubs c on c.id = r.club_id
  left join public.competitions k on k.id = r.competition_id
  where r.id = p_report_id;
$$;
revoke all on function public.report_alert_payload(uuid) from public, anon, authenticated;
grant execute on function public.report_alert_payload(uuid) to service_role;

-- --- Utløseren ------------------------------------------------------------------
create or replace function private.report_alert_kick()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url    text;
  v_secret text;
begin
  v_url := private.project_url();
  select s.decrypted_secret into v_secret
    from vault.decrypted_secrets s where s.name = 'report_alert_secret';
  if v_url is null or v_secret is null then
    return null;  -- Ikke satt opp. Rapporten står fortsatt i lista til arrangøren.
  end if;
  perform net.http_post(
    url := v_url || '/functions/v1/report-alert',
    headers := jsonb_build_object('content-type', 'application/json', 'x-report-secret', v_secret),
    body := jsonb_build_object('report_id', new.id),
    timeout_milliseconds := 10000);
  return null;
exception when others then
  -- Et feilet kall skal aldri stoppe rapporten.
  return null;
end;
$$;
revoke all on function private.report_alert_kick() from public, anon, authenticated;

drop trigger if exists dd18_report_alert on public.content_reports;
create trigger dd18_report_alert
  after insert on public.content_reports
  for each row execute function private.report_alert_kick();

-- --- Kontroll -------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'dd18_report_alert'
                   and tgrelid = 'public.content_reports'::regclass
                   and tgfoid = 'private.report_alert_kick()'::regprocedure) then
    raise exception '063: triggeren dd18_report_alert peker ikke på private.report_alert_kick';
  end if;
  if has_function_privilege('anon', 'public.report_alert_payload(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.report_alert_payload(uuid)', 'execute') then
    raise exception '063: report_alert_payload kan kjøres av anon eller authenticated';
  end if;
  if not has_function_privilege('service_role', 'public.report_alert_payload(uuid)', 'execute') then
    raise exception '063: service_role kan ikke kjøre report_alert_payload';
  end if;
  if has_function_privilege('anon', 'private.report_alert_kick()', 'execute')
     or has_function_privilege('authenticated', 'private.report_alert_kick()', 'execute') then
    raise exception '063: report_alert_kick kan kjøres av anon eller authenticated';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public', 'private')
                and p.proname in ('report_alert_kick', 'report_alert_payload')
                and p.prosrc like '%.supabase.co%') then
    raise exception '063: en funksjon har en hardkodet adresse';
  end if;
  if not exists (select 1 from vault.secrets s where s.name = 'report_alert_secret') then
    raise notice '063: Vault-hemmeligheten report_alert_secret mangler ennå (ingen e-post før den finnes)';
  end if;
  raise notice '063 kontroll: 5 av 5';
end $$;

commit;

-- KONTROLL ETTERPÅ (bare lesing)
-- 1) Ingen nøkkel i triggerdefinisjonen. Forventet: 0 rader.
-- select tgname from pg_trigger where pg_get_triggerdef(oid) like '%secret%';
-- 2) Etter en prøverapport: siste kall fra pg_net. Forventet: status_code 200.
-- select id, status_code, content, created from net._http_response order by id desc limit 5;
-- 3) Innholdet for siste rapport (som postgres i SQL Editor):
-- select public.report_alert_payload(id) from public.content_reports order by created_at desc limit 1;

-- RULLEBAKKE
-- begin;
-- drop trigger if exists dd18_report_alert on public.content_reports;
-- drop function if exists private.report_alert_kick();
-- drop function if exists public.report_alert_payload(uuid);
-- commit;
-- Vault-hemmeligheten kan stå. Vil du fjerne den:
-- delete from vault.secrets where name = 'report_alert_secret';
