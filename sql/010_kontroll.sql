-- 010 – samlet kontroll. Kjør i SQL Editor etter 010_push.sql.
-- Én rad per sjekk. Alle skal ha ok = true.
with
t as (
  select c.relname, c.relrowsecurity
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r'
    and c.relname in ('push_devices', 'push_preferences', 'push_queue', 'push_tokens')
),
f as (
  select p.proname,
         has_function_privilege('anon', p.oid, 'execute') as anon_kan,
         has_function_privilege('authenticated', p.oid, 'execute') as auth_kan
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('push_player_categories', 'push_club_categories',
                      'register_push_device', 'unregister_push_device', 'push_status',
                      'claim_push_jobs', 'push_job_payload', 'finish_push_job',
                      'queue_evening_reminders', 'push_enqueue_activity',
                      'push_enqueue_thread_message', 'register_push_token')
),
g as (
  select table_name, string_agg(privilege_type, ', ' order by privilege_type) as rettigheter
  from information_schema.role_table_grants
  where table_schema = 'public' and grantee = 'authenticated'
    and table_name in ('push_devices', 'push_preferences', 'push_queue')
  group by 1
)
select 1 as nr, 'Tabellene finnes med RLS' as sjekk,
       (select count(*) = 3 and bool_and(relrowsecurity) from t where relname <> 'push_tokens') as ok
union all
select 2, 'push_tokens er borte', not exists (select 1 from t where relname = 'push_tokens')
union all
select 3, 'anon har ingen tabellrettigheter',
       not exists (select 1 from information_schema.role_table_grants
                   where table_schema = 'public' and grantee in ('anon', 'PUBLIC')
                     and table_name in ('push_devices', 'push_preferences', 'push_queue'))
union all
select 4, 'authenticated: push_devices bare SELECT',
       coalesce((select rettigheter = 'SELECT' from g where table_name = 'push_devices'), false)
union all
select 5, 'authenticated: push_preferences D/I/S/U',
       coalesce((select rettigheter = 'DELETE, INSERT, SELECT, UPDATE' from g where table_name = 'push_preferences'), false)
union all
select 6, 'authenticated: ingen tilgang til push_queue',
       not exists (select 1 from g where table_name = 'push_queue')
union all
select 7, 'anon kan ikke kjøre noen push-funksjon',
       not exists (select 1 from f where anon_kan)
union all
select 8, 'authenticated kan kjøre appens fem funksjoner',
       (select count(*) = 5 and bool_and(auth_kan) from f
        where proname in ('push_player_categories', 'push_club_categories',
                          'register_push_device', 'unregister_push_device', 'push_status'))
union all
select 9, 'authenticated kan ikke kjøre senderens funksjoner',
       not exists (select 1 from f where auth_kan
                   and proname in ('claim_push_jobs', 'push_job_payload', 'finish_push_job',
                                   'queue_evening_reminders', 'push_enqueue_activity',
                                   'push_enqueue_thread_message'))
union all
select 10, 'register_push_token er borte', not exists (select 1 from f where proname = 'register_push_token')
union all
select 11, 'Begge køtriggerne finnes',
       (select count(*) = 2 from pg_trigger
        where tgname in ('push_enqueue_activity', 'push_enqueue_thread_message'))
union all
select 12, 'clubs.push_disabled_categories finnes',
       exists (select 1 from information_schema.columns
               where table_schema = 'public' and table_name = 'clubs'
                 and column_name = 'push_disabled_categories')
order by nr;
