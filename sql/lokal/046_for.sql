\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Første halvdel av prøven for 046_varsler.sql: «verden før». Kjøres på kopien med
-- 001–043, 034, 044, 045 og 047, FØR 046. Lagres (ingen rollback), så bruk en kopi.
--
--   * lokal46.for_payload: push_job_payload for hver jobb i køen, slik den var før 046.
--   * lokal46.push_job_payload_for(jobb): den gamle funksjonen, kopiert, så
--     lokal/046_prove.sql kan kjøre den på nye jobber i samme verden og sammenligne.
--   * lokal46.for_queue: hvilke linjer som lå i køen før.
-- ===========================================================================

create schema if not exists lokal46;

drop table if exists lokal46.for_payload;
create table lokal46.for_payload as
  select q.id as job_id, public.push_job_payload(q.id) as payload from public.push_queue q;

drop table if exists lokal46.for_queue;
create table lokal46.for_queue as
  select q.id as job_id, q.club_id, q.activity_id, q.thread_message_id from public.push_queue q;

do $$
declare
  v_def text := pg_get_functiondef('public.push_job_payload(bigint)'::regprocedure);
begin
  v_def := replace(v_def, 'FUNCTION public.push_job_payload(', 'FUNCTION lokal46.push_job_payload_for(');
  execute v_def;
end $$;

select 'for: ' || count(*) || ' jobber lagret, ' || count(*) filter (where payload is not null) || ' med svar'
  from lokal46.for_payload;
