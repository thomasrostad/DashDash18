-- 065: feilrapporter (064) slettes etter 90 dager, som personvernerklæringen sier.
--
-- Cron-jobben dd18-feilrapporter sletter rader i public.app_diagnostics eldre enn 90 dager,
-- hver natt kl. 03:45 UTC. Krever 064 og pg_cron. Bare additivt.
--
-- Rullebakke nederst. Idempotent (cron.schedule med samme navn erstatter jobben).

begin;

select cron.schedule('dd18-feilrapporter', '45 3 * * *', $cron$
  delete from public.app_diagnostics where created_at < now() - interval '90 days'
$cron$);

do $$
begin
  if not exists (select 1 from cron.job where jobname = 'dd18-feilrapporter') then
    raise exception '065: cron-jobben mangler';
  end if;
  raise notice '065 kontroll: 1 av 1';
end $$;

commit;

-- RULLEBAKKE
-- select cron.unschedule('dd18-feilrapporter');
