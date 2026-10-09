-- ===========================================================================
-- 033 – TURNERINGEN SOM KJERNE, TRINN 3 (FASE 23) – FORSLAG, IKKE KJØRT
-- ===========================================================================
-- Status: FORSLAG til godkjenning (ROADMAP B5). IKKE KJØRT mot Supabase,
-- verken test eller prod. Prøvd lokalt (sql/lokal/033_for.sql og
-- sql/lokal/033_prove.sql, fila kjørt to ganger på rad, rullebakken prøvd på
-- en kopi). Krever 001–032. 036–038 kan være kjørt før eller etter.
--
-- Hvorfor (docs/fase-22-turnering-som-kjerne.md, kap. 5 og 10, trinn 3):
-- turneringen skal være kilden, ikke sesongen. En liga, cup eller
-- morroturnering i en klubb skal kunne ha EGNE spilledager (events med
-- competition_id = turneringen, uten sesong), og rundene på dem skal telle i
-- den turneringen. Golfgutu (sesongen, jakkeracet) skal gi nøyaktig de samme
-- dataene som før.
--
-- Hva fila gjør:
--   1. Speilingen går begge veier, og turneringen kan være kilden:
--        * competitions_sync_to_season (NY, etter update av name, status,
--          rules på en sesongturnering) skriver navn, status og regler
--          tilbake til seasons. Dermed kan den nye appen endre jakkeracet via
--          competitions, og dagens app (som leser seasons) ser endringen.
--        * Sperre mot ring: tilbakeskrivingen gjør ingenting når endringen
--          på turneringen selv kom fra en trigger (pg_trigger_depth() > 1),
--          altså fra competitions_sync_season. Og competitions_sync_season
--          oppdaterer bare når noe faktisk er ulikt, så ekkoet fra
--          tilbakeskrivingen stopper der.
--        * guard_competitions (fra 026) lar arrangøren endre navn, status og
--          regler på en sesongturnering. Hvem som er med (entry), type,
--          sesong, eier, hovedturnering og kjøp er fortsatt låst.
--        * competitions_update-policyen er uendret (klubbens arrangør), så
--          det er de samme som i dag kan endre sesongen (seasons_update).
--   2. Hovedturneringen (is_main):
--        * en ny sesong blir hovedturnering bare når klubben ikke har en
--          aktiv hovedturnering fra før (competitions_sync_season);
--        * en sesongturnering som blir aktiv, blir hovedturnering når
--          klubben ikke har en annen aktiv (competition_claim_main). Det
--          gjør at dagens flyt «ny sesong (planlagt) → activate_season» ender
--          likt som før: den nye sesongen blir jakkeracet når den forrige
--          avsluttes.
--        * ingen turnering mister is_main automatisk, og ingen eksisterende
--          rad endres.
--   3. Koblingen runde → turnering går via events.competition_id for ALLE
--      turneringer, ikke bare sesonger (competition_rounds_sync_round og
--      competition_rounds_sync_event). For kvelder i en sesong er
--      events.competition_id sesongens turnering (031 holder dem i takt), så
--      svaret er det samme. For en spilledag i en liga blir rundene koblet til
--      ligaen med source = 'season' («koblet via spilledagen», ingen ny
--      verdi, dagens app dekoder source strengt).
--   4. Utfylling: runder på spilledager med competition_id som mangler
--      koblingen, får den (on conflict do nothing). På test og i Golfgutu er
--      det ingen (kontroll 6 og paritetskontrollen).
--
-- Hvorfor dagens app ikke merker noe:
--   * Dagens app skriver seasons (ny sesong, nytt navn, nye regler, avslutt)
--     og kaller activate_season. Speilingen sesong → turnering er som før;
--     tilbakeskrivingen fyrer, men skriver ingenting (verdiene er like).
--   * activate_season er uendret (se «Åpne spørsmål» 1).
--   * Ingen policy, ingen hjelpefunksjon og ingen unik regel endres. De
--     gamle reglene (rounds_one_active_per_club, seasons_one_active_per_club,
--     events_one_per_date) står til 034.
--   * Ingen ny verdi i kolonner appen dekoder strengt (status, kind, entry,
--     source).
--   * Golfgutu-dataene endres ikke (paritetskontrollen og bildet per
--     innlogging er likt før og etter, lokal/033_prove.sql del A).
--
-- Hva fila IKKE gjør (trinn 4–5):
--   * fjerner ingen gamle unike regler. En spilledag i en liga kan derfor
--     ikke ligge på samme dato som en annen kveld i klubben
--     (events_one_per_date), og bare én runde kan gå i klubben om gangen
--     (rounds_one_active_per_club). Det løses i 034;
--   * lar ikke den nye appen LAGE en sesong via competitions (nye sesonger
--     lages fortsatt i seasons, nye ligaer med create_competition);
--   * setter ikke app_config.min_ios_build.
--
-- Åpne spørsmål (valgt det forsiktige, til godkjenning):
--   1. activate_season endres ikke i 033. Designet sier at den skal avslutte
--      bare forrige hovedturnering. Så lenge seasons_one_active_per_club står
--      (til 034), MÅ den avslutte alle andre aktive sesonger, ellers gir den
--      23505. I 033 er «den andre aktive sesongen» og «forrige aktive
--      hovedturnering» alltid den samme raden (bare sesonger kan være
--      hovedturnering, og høyst én sesong er aktiv), så endringen flyttes til
--      034, der indeksen fjernes. Spørsmål til da: skal aktivering av en serie
--      som IKKE er hovedturnering la jakkeracet stå (forslag: ja)?
--   2. En ny planlagt sesong mens jakkeracet er aktivt får is_main = false
--      fram til den aktiveres (i dag får den true). Dagens app viser da ikke
--      «Hovedturnering» på den planlagte serien og sorterer den etter de
--      aktive (TournamentPicker), men Hjem behandler alle sesonger som
--      hovedturnering (HomeFeed.isMain). Når den aktiveres, blir den
--      hovedturnering som før. Er det greit?
--   3. Tilbakeskrivingen er security definer. Den som kan endre turneringen
--      (competitions_update: klubbens arrangør) kan dermed endre sesongen. Det
--      er de samme som i dag (seasons_update). Arrangører i staben (032) kan
--      ikke endre competitions-raden direkte, så de får ikke mer.
--   4. Runder på en ligas spilledag kobles til ligaen også om ligaen ikke er
--      kjøpt (requires_purchase, 023). Kjøpssperren er i appen i dag, ikke i
--      databasen, og en spilledag kan uansett bare lages av arrangøren.
--   5. Dagens app (uten fase 23) viser en ligas spilledager som «kveld uten
--      sesong» i terminlista, og rundene der som klubbens runder. Det skjer
--      først når den nye appen lager slike spilledager.
--
-- Mønsteret fra 001–032 følges: én transaksjon, idempotent, `set search_path
-- = ''`, `revoke … from public, anon` ETTER hver create or replace, interne
-- funksjoner og triggerfunksjoner tas fra authenticated også, kontroll og
-- rullebakke nederst.
-- ===========================================================================

begin;


-- ===========================================================================
-- 1. HOVEDTURNERINGEN: bare når klubben ikke har en aktiv
-- ===========================================================================
-- En aktiv sesongturnering blir hovedturnering når klubben ikke har en annen
-- aktiv hovedturnering. Gjør ingenting ellers (idempotent). Oppdateringen
-- fyrer competitions-triggerne på dybde > 1, så vakta slipper den gjennom.
create or replace function public.competition_claim_main(p_competition_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.competitions c
     set is_main = true
   where c.id = p_competition_id
     and c.kind = 'season'
     and c.club_id is not null
     and c.status = 'active'
     and not c.is_main
     and not exists (select 1 from public.competitions o
                      where o.club_id = c.club_id and o.is_main and o.status = 'active'
                        and o.id <> c.id);
$$;
revoke all on function public.competition_claim_main(uuid) from public, anon, authenticated;


-- ===========================================================================
-- 2. SESONG → TURNERING (017), med is_main-regelen og uten ekko
-- ===========================================================================
-- Som i 017: den som lager eller endrer en sesong (dagens app,
-- activate_season, importen), får turneringen oppdatert i samme transaksjon.
-- 033:
--   * ny sesong er hovedturnering bare når klubben ikke har en aktiv;
--   * oppdaterer bare når navn, status eller regler faktisk er ulike, så
--     ekkoet fra tilbakeskrivingen (seksjon 3) stopper her;
--   * en sesong som blir aktiv, tar over som hovedturnering når klubben ikke
--     har en annen aktiv.
create or replace function public.competitions_sync_season()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.competitions (kind, name, club_id, season_id, status, entry, rules, is_main)
  values ('season', new.name, new.club_id, new.id, new.status, 'club', new.rules,
          not exists (select 1 from public.competitions o
                       where o.club_id = new.club_id and o.is_main and o.status = 'active'
                         and o.season_id is distinct from new.id))
  on conflict (season_id) do update
    set name   = excluded.name,
        status = excluded.status,
        rules  = excluded.rules
    where (public.competitions.name, public.competitions.status, public.competitions.rules)
          is distinct from (excluded.name, excluded.status, excluded.rules);

  if new.status = 'active' then
    perform public.competition_claim_main(c.id)
       from public.competitions c where c.season_id = new.id;
  end if;
  return null;
end;
$$;
revoke all on function public.competitions_sync_season() from public, anon, authenticated;

-- Triggeren fra 017 er uendret (after insert or update of name, status, rules
-- on seasons); den peker på funksjonen over.


-- ===========================================================================
-- 3. TURNERING → SESONG (ny): turneringen kan være kilden
-- ===========================================================================
-- Navn, status og regler på en sesongturnering skrives tilbake til seasons,
-- så dagens app (Tavla, arrangørsiden, veddemål) ser det den nye appen endrer.
-- Sperre mot ring: kom endringen på turneringen fra en annen trigger
-- (pg_trigger_depth() > 1), er det speilingen fra seasons, og da er seasons
-- allerede kilden. Oppdaterer bare når noe er ulikt.
create or replace function public.competitions_sync_to_season()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if pg_trigger_depth() > 1 or new.season_id is null then
    return null;
  end if;
  update public.seasons s
     set name   = new.name,
         status = new.status,
         rules  = new.rules
   where s.id = new.season_id
     and (s.name, s.status, s.rules) is distinct from (new.name, new.status, new.rules);
  if new.status = 'active' then
    perform public.competition_claim_main(new.id);
  end if;
  return null;
end;
$$;
revoke all on function public.competitions_sync_to_season() from public, anon, authenticated;

drop trigger if exists competitions_sync_to_season on public.competitions;
create trigger competitions_sync_to_season
  after update of name, status, rules on public.competitions
  for each row
  when (new.season_id is not null)
  execute function public.competitions_sync_to_season();


-- ===========================================================================
-- 4. VAKTA: navn, status og regler på sesongturneringen kan endres
-- ===========================================================================
-- Som 026, med én endring: blokken «Endre turneringen i stedet» gjelder nå
-- bare entry (hvem som er med). Sesongturneringen er alltid klubbens tropp
-- (entry = club), som Tavla bygger på.
create or replace function public.guard_competitions()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or pg_trigger_depth() > 1 then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.owner_id := case when new.club_id is null then auth.uid() end;
    if new.kind = 'season' or new.season_id is not null or new.is_main then
      raise exception 'En serie med kvelder lages under «Ny turnering»' using errcode = '22023';
    end if;
    if new.requires_purchase or new.entitlement_id is not null then
      raise exception 'Kjøp settes bare av serveren' using errcode = '42501';
    end if;
    return new;
  end if;

  if new.kind is distinct from old.kind or new.club_id is distinct from old.club_id
     or (new.owner_id is distinct from old.owner_id
         and not (new.owner_id is null
                  and not exists (select 1 from public.profiles p where p.id = old.owner_id)))
     or new.season_id is distinct from old.season_id
     or new.is_main is distinct from old.is_main then
    raise exception 'Type, eier og hovedturnering kan ikke endres her' using errcode = '42501';
  end if;
  if new.requires_purchase is distinct from old.requires_purchase
     or new.entitlement_id is distinct from old.entitlement_id then
    raise exception 'Kjøp settes bare av serveren' using errcode = '42501';
  end if;
  -- 033: navn, status og regler kan endres her (skrives tilbake til
  -- sesongen). Hvem som er med, kan ikke.
  if old.season_id is not null and new.entry is distinct from old.entry then
    raise exception 'Endre turneringen i stedet' using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_competitions() from public, anon, authenticated;


-- ===========================================================================
-- 5. RUNDE → TURNERING VIA SPILLEDAGEN, FOR ALLE TURNERINGER
-- ===========================================================================
-- En runde på en spilledag teller i turneringen spilledagen hører til
-- (events.competition_id). For en kveld i en sesong er det sesongens
-- turnering, som før. source = 'season' betyr «koblet via spilledagen».
create or replace function public.competition_rounds_sync_round()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if new.event_id is not distinct from old.event_id then
      return null;
    end if;
    delete from public.competition_rounds cr
     where cr.round_id = new.id and cr.source = 'season';
  end if;

  insert into public.competition_rounds (competition_id, round_id, source)
  select e.competition_id, new.id, 'season'
    from public.events e
   where e.id = new.event_id and e.competition_id is not null
  on conflict (competition_id, round_id) do nothing;
  return null;
end;
$$;
revoke all on function public.competition_rounds_sync_round() from public, anon, authenticated;

-- En spilledag som flyttes til en annen turnering (eller sesong, som flytter
-- competition_id via events_sync_competition), tar rundene med seg.
create or replace function public.competition_rounds_sync_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.competition_id is not distinct from old.competition_id then
    return null;
  end if;
  delete from public.competition_rounds cr
   using public.rounds r
   where r.event_id = new.id and cr.round_id = r.id and cr.source = 'season';
  if new.competition_id is not null then
    insert into public.competition_rounds (competition_id, round_id, source)
    select new.competition_id, r.id, 'season'
      from public.rounds r
     where r.event_id = new.id
    on conflict (competition_id, round_id) do nothing;
  end if;
  return null;
end;
$$;
revoke all on function public.competition_rounds_sync_event() from public, anon, authenticated;

-- Triggerne er som i 017/031 (rounds: after insert or update of event_id;
-- events: after update of season_id, competition_id). De settes på nytt her,
-- så fila står på egne bein.
drop trigger if exists competition_rounds_sync_round on public.rounds;
create trigger competition_rounds_sync_round
  after insert or update of event_id on public.rounds
  for each row execute function public.competition_rounds_sync_round();

drop trigger if exists competition_rounds_sync_event on public.events;
create trigger competition_rounds_sync_event
  after update of season_id, competition_id on public.events
  for each row execute function public.competition_rounds_sync_event();


-- ===========================================================================
-- 6. UTFYLLING: runder på spilledager som mangler koblingen
-- ===========================================================================
-- For kvelder i en sesong finnes koblingen alt (017). Dette gjelder bare
-- spilledager i andre turneringer, om noen er lagt inn etter 031.
insert into public.competition_rounds (competition_id, round_id, source)
select e.competition_id, r.id, 'season'
  from public.rounds r
  join public.events e on e.id = r.event_id
 where e.competition_id is not null
on conflict (competition_id, round_id) do nothing;

commit;


-- ===========================================================================
-- KONTROLL (kjør i SQL Editor etter fila, som én kjøring). Én rad per sjekk,
-- alle skal ha ok = true.
-- ===========================================================================
-- with f as (
--   select p.proname,
--          has_function_privilege('anon', p.oid, 'execute') as anon_kan,
--          has_function_privilege('authenticated', p.oid, 'execute') as auth_kan,
--          p.proconfig, p.prosrc
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public'
--     and p.proname in ('competition_claim_main', 'competitions_sync_season', 'competitions_sync_to_season',
--                       'guard_competitions', 'competition_rounds_sync_round', 'competition_rounds_sync_event')
-- )
-- select 1 as nr, 'Alle seks funksjonene finnes og har tom search_path' as sjekk,
--        (select count(*) = 6 and bool_and('search_path=""' = any(proconfig)) from f) as ok
-- union all
-- select 2, 'Ingen av dem kan kalles av anon eller innloggede (bare triggere og interne)',
--        (select bool_and(not anon_kan and not auth_kan) from f)
-- union all
-- select 3, 'De gamle reglene står: én aktiv runde og sesong per klubb, én kveld per dato, én hovedturnering',
--        (select count(*) = 4 from pg_indexes where schemaname = 'public'
--          and indexname in ('rounds_one_active_per_club', 'seasons_one_active_per_club',
--                            'competitions_one_main_active', 'rounds_one_active_per_event_wave'))
--        and exists (select 1 from pg_constraint where conname = 'events_one_per_date'
--                     and conrelid = 'public.events'::regclass)
-- union all
-- select 4, 'Triggerne finnes: begge veier sesong ↔ turnering, rundene følger spilledagen',
--        (select count(*) = 4 from pg_trigger where not tgisinternal and tgname in
--          ('competitions_sync_season', 'competitions_sync_to_season',
--           'competition_rounds_sync_round', 'competition_rounds_sync_event'))
-- union all
-- select 5, 'Sperren mot ring er på plass (pg_trigger_depth i tilbakeskrivingen)',
--        (select prosrc ~ 'pg_trigger_depth\(\) > 1' from f where proname = 'competitions_sync_to_season')
-- union all
-- select 6, 'Hver runde på en spilledag er koblet (season) til spilledagens turnering, og ingen annen season-kobling finnes',
--        not exists (select 1 from public.rounds r join public.events e on e.id = r.event_id
--                     where e.competition_id is not null
--                       and not exists (select 1 from public.competition_rounds cr
--                                        where cr.round_id = r.id and cr.competition_id = e.competition_id
--                                          and cr.source = 'season'))
--        and not exists (select 1 from public.competition_rounds cr
--                         left join public.rounds r on r.id = cr.round_id
--                         left join public.events e on e.id = r.event_id
--                        where cr.source = 'season' and cr.competition_id is distinct from e.competition_id)
-- union all
-- select 7, 'Speilingen holder: hver sesong har turneringen sin med samme navn, status og regler',
--        not exists (select 1 from public.seasons s
--                     left join public.competitions c on c.season_id = s.id
--                    where c.id is null or c.kind <> 'season' or c.entry <> 'club'
--                       or (c.name, c.status, c.rules) is distinct from (s.name, s.status, s.rules))
-- union all
-- select 8, 'Hovedturnering: høyst én aktiv per klubb, og en aktiv sesong er hovedturneringen',
--        not exists (select club_id from public.competitions where is_main and status = 'active'
--                     group by club_id having count(*) > 1)
--        and not exists (select 1 from public.seasons s join public.competitions c on c.season_id = s.id
--                         where s.status = 'active' and not c.is_main)
-- union all
-- select 9, 'Paritet (Tavla): rundene via sesongens kvelder = rundene via turneringens spilledager = koblingene',
--        not exists (
--          (select e.season_id, r.id from public.rounds r join public.events e on e.id = r.event_id
--            where e.season_id is not null
--           except
--           select c.season_id, r.id from public.rounds r join public.events e on e.id = r.event_id
--             join public.competitions c on c.id = e.competition_id where c.season_id is not null)
--          union all
--          (select c.season_id, r.id from public.rounds r join public.events e on e.id = r.event_id
--             join public.competitions c on c.id = e.competition_id where c.season_id is not null
--           except
--           select c.season_id, cr.round_id from public.competition_rounds cr
--             join public.competitions c on c.id = cr.competition_id
--            where cr.source = 'season' and c.season_id is not null))
-- order by nr;
--
-- Paritetskontrollen fra docs/fase-22-turnering-som-kjerne.md (10.2) kjøres
-- i tillegg før og etter, og svarene skal være like.


-- ===========================================================================
-- RULLEBAKKE (bare test; koblinger fra ligaers spilledager går tapt)
-- ===========================================================================
-- Funksjonene får de gamle kroppene tilbake: kjør blokkene «create or
-- replace function public.competitions_sync_season / competition_rounds_sync_round
-- / competition_rounds_sync_event» fra 017_fundament.sql og «guard_competitions»
-- fra 026_turnering_tekster.sql på nytt (med revoke-linjene under dem). Så:
--
-- begin;
-- drop trigger if exists competitions_sync_to_season on public.competitions;
-- drop function if exists public.competitions_sync_to_season();
-- -- (competitions_sync_season fra 017 kaller ikke denne lenger)
-- drop function if exists public.competition_claim_main(uuid);
-- -- Som før 033: «season»-koblinger finnes bare for sesongturneringer, og
-- -- hver sesong er hovedturnering (høyst én aktiv, så ingen 23505).
-- delete from public.competition_rounds cr
--  using public.competitions c
--  where c.id = cr.competition_id and cr.source = 'season' and c.season_id is null;
-- update public.competitions set is_main = true where kind = 'season' and not is_main;
-- commit;
