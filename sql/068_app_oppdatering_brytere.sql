-- 068: anbefalt bygg og nødbrytere i app_config (1.0.2, docs/utgivelser.md). Kjørt på test 21.10.2026.
--
-- app_config (031) har min_ios_build: bygg under den får «Oppdater Atten» og kommer ikke videre.
-- Det virker fra 1.0. Fra 1.0.2 leser appen også:
--   * recommended_ios_build {"build": N}: bygg under N får «Ny versjon av Atten» én gang per N,
--     med «Oppdater» og «Senere». 0 = ingen beskjed.
--   * ios_flags {"navn": false}: slår av en funksjon uten nytt bygg. Bare av, aldri på (App
--     Review 2.3.1). Navnene: tavla_share (Del tavla), tv_code (TV-kode), find_tournaments
--     (Finn turneringer), bill_split (Del regningen), social (reaksjoner og kommentarer),
--     live_activity (Live Activity). {} = alt som i bygget.
-- Appen leser alle tre etter innlogging og når den blir aktiv. Feiler lesingen, beholder den
-- bryterne fra sist og sperrer ingenting.
--
-- Bare data, ingen skjemaendring. Begge radene lages uten virkning. Kjøres fila på nytt, røres
-- ikke verdier som er satt.
--
-- Bruk (SQL Editor eller CLI, test først):
--   update public.app_config set value = '{"build": 201}' where key = 'recommended_ios_build';
--   update public.app_config set value = '{"build": 201}' where key = 'min_ios_build';
--   update public.app_config set value = '{"social": false}' where key = 'ios_flags';
--   update public.app_config set value = '{}' where key = 'ios_flags';   -- alt på igjen
-- Byggnummeret er CFBundleVersion (Xcode Cloud), ikke versjonen (1.0.1).
--
-- Krever 031. Rullebakke nederst.

begin;

insert into public.app_config (key, value)
values ('recommended_ios_build', '{"build": 0}'::jsonb),
       ('ios_flags', '{}'::jsonb)
on conflict (key) do nothing;

comment on table public.app_config is
  'Brytere appen leser etter innlogging. min_ios_build = laveste bygg som får bruke databasen '
  '(appen ber om oppdatering under det). recommended_ios_build = bygg under det får en beskjed '
  'om ny versjon (068). ios_flags = funksjoner som er slått av fra serveren (068). '
  'Skrives bare i SQL Editor / service_role.';

do $$
declare
  v_ok int := 0;
begin
  if exists (select 1 from public.app_config
             where key = 'recommended_ios_build' and jsonb_typeof(value->'build') = 'number') then
    v_ok := v_ok + 1;
  end if;
  if exists (select 1 from public.app_config
             where key = 'ios_flags' and jsonb_typeof(value) = 'object') then
    v_ok := v_ok + 1;
  end if;
  if v_ok <> 2 then
    raise exception '068: kontroll % av 2', v_ok;
  end if;
  raise notice '068 kontroll: 2 av 2';
end $$;

commit;

-- RULLEBAKKE
-- delete from public.app_config where key in ('recommended_ios_build', 'ios_flags');
