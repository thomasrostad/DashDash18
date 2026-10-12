-- 049: gjenbruk av oppsett (gjennomføringsplanen steg 8). Godkjent og kjørt på test 12.10.2026. Ikke kjørt på test.
--
-- Krever 001–047 (044_roller: private.has_club_right; 034: én spilledag per turnering og dato,
-- flere kvelder per dato i en klubb; 047: rounds.kind, counts, points_table, hide_last_holes).
--
-- Beslutningen (Thomas 11.10.2026, docs/plan-konkurranser-og-sosialt.md): «Samme som sist»,
-- «Sesong fra mal», og egne maler som arrangøren lager og gjenbruker.
--
-- Hva fila gjør:
--   1. «Sesong fra mal»: spilledager i serie.
--        event_series (id, club_id, competition_id, weekday 1–7 (ISO, 1 = mandag), every_weeks 1–8,
--                      first_date, count, start_time, venue, created_by, created_at, updated_at)
--        events.series_id → event_series (sammensatt nøkkel med competition_id, så en kveld bare kan
--                      høre til en serie i sin egen turnering; settes tom når serien slettes, og når
--                      kvelden flyttes til en annen turnering).
--      create_event_series(turnering, første dato, ukedag, antall, hver n-te uke default 1,
--                          starttid default null, sted default null)
--        * bare klubbturneringer (kvelder krever klubb), og bare med rettigheten tournaments;
--        * første kveld er første dato fra og med p_first_date med riktig ukedag, så hver
--          p_every_weeks uke, p_count datoer i alt (høyst 52);
--        * datoer der turneringen alt har en kveld, hoppes over (034: én spilledag per turnering
--          og dato; andre turneringer i klubben kan ha kveld samme dato);
--        * én transaksjon, turneringen låses (for update). Svar: series_id, de nye kvelds-id-ene,
--          datoene og datoene som ble hoppet over. Ble ingen kveld laget, slettes serien igjen.
--      update_event_series(kveld, omfang 'one'|'future', starttid, sted, ny dato default null)
--        * 'one': bare denne kvelden (som en vanlig update), også om den er passert;
--        * 'future': denne og senere kvelder i samme serie. Kvelder som er passert (dato før i dag)
--          eller har en startet runde (active/locked), røres ikke og står i «skipped»;
--        * starttid og sted settes som gitt (null tømmer). Ny dato flytter kvelden; for 'future'
--          flyttes alle med like mange dager. Fristene (045) flyttes like mye. Serien får ny ukedag,
--          tid og sted ved 'future'. En dato som alt er tatt i turneringen, gir 23505 og ingenting endres.
--   2. Egne maler: setup_templates (id, club_id eller owner_id (personlig), kind 'round'|'tournament',
--      name, payload jsonb, created_by, created_at, updated_at).
--        * payload er et objekt på høyst 32 kB (32 768 byte som tekst). Innholdet tolkes av appen:
--            round:      course_id, tee_id, hole_count, first_hole, format, handicap_allowance,
--                        external_handicap, venue, ld/kp, weight, counts, points_table,
--                        hide_last_holes, games [{kind, settings}];
--            tournament: kind, rules (regelsettet), schedule {weekday, every_weeks, count,
--                        start_time, venue}, venue, max_entrants osv.
--          Databasen sjekker bare formen, ikke nøklene (regelsettet har sin egen versjon).
--        * Lesing: klubbens maler for dem med rettigheten rounds eller tournaments (begge typer),
--          personlige maler for eieren. Vanlige medlemmer ser ingen maler (de trenger dem ikke).
--        * Skriving bare via setup_template_save og setup_template_delete: en rundemal krever
--          rounds, en turneringsmal tournaments (klubb), eller at det er din egen (personlig).
--          Unikt navn per klubb (eller eier) og type. Høyst 200 maler per klubb eller person.
--   3. «Samme som sist»: ingen tabell. previous_round_setup(kveld) gir oppsettet fra den siste
--      startede (active/locked), vanlige (kind = normal, ikke playoff) runden på en kveld i samme
--      turnering, til og med denne kveldens dato (samme rekkefølge som QuickStart.previousRound:
--      dato, så rundenummer). Kladder og playoffer telles ikke. counts = false-runder telles med
--      («sist» er sist), og counts sendes med så appen kan velge. Med spillerne (bås, markør, lag,
--      seeding; bare aktive medlemmer), matchene og spillene som forslag. Ingen runde gir null.
--      Hvem: rettigheten rounds i klubben, eller arrangør i turneringens stab (som kan sette opp runder).
--
-- Rettighetene (docs/roller.md): spilledager og serier er tournaments; runder er rounds.
--
-- Mønsteret fra 001–047: én transaksjon, idempotent, search_path = '', revoke etter hver
-- create or replace, kontroll og rullebakke nederst. Rører ikke push-tabellene (046).
--
-- Appen og web-admin må (ikke i denne fila):
--   * Terminlista: «Lag serie» (startdato, ukedag, antall, hver n-te uke, tid, sted) med
--     create_event_series; vise hvilke datoer som ble hoppet over;
--   * redigering av en kveld med series_id: valget «Bare denne» / «Denne og fremtidige», med
--     update_event_series; vise kvelder som ble hoppet over (passert eller startet);
--   * lese events.series_id (og event_series for å vise «Hver torsdag kl. 18»);
--   * «Samme som sist»: hente previous_round_setup(kveld) i stedet for (eller i tillegg til)
--     QuickStart.previousRound, og bruke spillerne/båsene som forslag (ny trekning er et valg);
--   * maler: «Lagre som mal» i runde-oppsettet og i Ny turnering, liste over maler (select på
--     setup_templates), «Bruk mal», gi nytt navn og slette, med setup_template_save/_delete;
--   * Ny turnering fra mal: lage turneringen som før med rules fra malen, så create_event_series
--     med schedule fra malen;
--   * web-admin: det samme.

begin;


-- ===========================================================================
-- 1. SERIER AV SPILLEDAGER
-- ===========================================================================
create table if not exists public.event_series (
  id              uuid primary key default gen_random_uuid(),
  club_id         uuid not null,
  competition_id  uuid not null,
  weekday         smallint not null check (weekday between 1 and 7),
  every_weeks     smallint not null default 1 check (every_weeks between 1 and 8),
  first_date      date not null,
  count           smallint not null check (count between 1 and 52),
  start_time      time,
  venue           text check (venue is null or char_length(venue) between 1 and 80),
  created_by      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint event_series_competition_fk foreign key (competition_id, club_id)
    references public.competitions (id, club_id) on delete cascade,
  constraint event_series_id_competition_key unique (id, competition_id)
);
comment on table public.event_series is
  'Serie av spilledager i en klubbturnering («Sesong fra mal»). weekday er ISO (1 = mandag). '
  'Skrives bare av create_event_series og update_event_series.';
create index if not exists event_series_competition_idx on public.event_series (competition_id);
create index if not exists event_series_club_idx on public.event_series (club_id);

alter table public.events add column if not exists series_id uuid;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'events_series_fk') then
    alter table public.events add constraint events_series_fk
      foreign key (series_id, competition_id) references public.event_series (id, competition_id)
      on delete set null (series_id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'events_series_needs_competition') then
    alter table public.events add constraint events_series_needs_competition
      check (series_id is null or competition_id is not null);
  end if;
end $$;
comment on column public.events.series_id is
  'Serien kvelden ble laget i (create_event_series). null = enkeltkveld.';
create index if not exists events_series_idx on public.events (series_id, event_date) where series_id is not null;

alter table public.event_series enable row level security;
revoke all on table public.event_series from public, anon, authenticated;
grant select on table public.event_series to authenticated;
grant all on table public.event_series to service_role;

drop policy if exists event_series_select on public.event_series;
create policy event_series_select on public.event_series
  for select to authenticated
  using (public.is_club_member(club_id) or public.is_competition_admin(competition_id));

drop trigger if exists event_series_set_updated_at on public.event_series;
create trigger event_series_set_updated_at before update on public.event_series
  for each row execute function public.set_updated_at();

-- En kveld som flyttes til en annen turnering (eller ut av turneringen), slipper serien.
-- Navnet gjør at den går etter events_sync_competition (som kan endre competition_id).
create or replace function private.events_unlink_series()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.series_id is not null and new.competition_id is distinct from old.competition_id then
    new.series_id := null;
  end if;
  return new;
end;
$$;
revoke all on function private.events_unlink_series() from public, anon, authenticated;

drop trigger if exists events_unlink_series on public.events;
create trigger events_unlink_series before update on public.events
  for each row execute function private.events_unlink_series();

-- Sted: trimmet, tomt = null, høyst 80 tegn.
create or replace function private.series_venue(p_venue text)
returns text
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v text := nullif(btrim(coalesce(p_venue, '')), '');
begin
  if v is not null and char_length(v) > 80 then
    raise exception 'Stedet kan ha høyst 80 tegn' using errcode = '22023';
  end if;
  return v;
end;
$$;
revoke all on function private.series_venue(text) from public, anon, authenticated;

-- Har kvelden en runde som er startet (pågår eller låst)? Playoffer teller også.
create or replace function private.event_has_started_round(p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.rounds r
                  where r.event_id = p_event_id and r.status in ('active', 'locked'));
$$;
revoke all on function private.event_has_started_round(uuid) from public, anon, authenticated;


create or replace function public.create_event_series(
  p_competition_id uuid,
  p_first_date     date,
  p_weekday        smallint,
  p_count          smallint,
  p_every_weeks    smallint default 1,
  p_start_time     time default null,
  p_venue          text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_comp     public.competitions%rowtype;
  v_venue    text;
  v_first    date;
  v_date     date;
  v_series   uuid;
  v_id       uuid;
  v_ids      uuid[] := '{}';
  v_dates    date[] := '{}';
  v_skipped  date[] := '{}';
  i          int;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select c.* into v_comp from public.competitions c where c.id = p_competition_id for update;
  if v_comp.id is null or not public.can_read_competition(v_comp.id) then
    raise exception 'Fant ikke turneringen' using errcode = 'P0002';
  end if;
  if v_comp.club_id is null then
    raise exception 'Spilledager i serie finnes bare i klubbturneringer' using errcode = '22023';
  end if;
  if not private.has_club_right(v_comp.club_id, 'tournaments') then
    raise exception 'Bare den som styrer turneringer, kan lage spilledager' using errcode = '42501';
  end if;
  if v_comp.status = 'finished' then
    raise exception 'Turneringen er avsluttet' using errcode = '55000';
  end if;
  if p_first_date is null then
    raise exception 'Velg første dato' using errcode = '22023';
  end if;
  if p_weekday is null or p_weekday not between 1 and 7 then
    raise exception 'Ukedagen må være 1–7 (mandag–søndag)' using errcode = '22023';
  end if;
  if p_count is null or p_count not between 1 and 52 then
    raise exception 'Antall kvelder må være 1–52' using errcode = '22023';
  end if;
  if p_every_weeks is null or p_every_weeks not between 1 and 8 then
    raise exception 'Hver 1.–8. uke' using errcode = '22023';
  end if;
  v_venue := private.series_venue(p_venue);

  v_first := p_first_date + ((p_weekday - extract(isodow from p_first_date)::int + 7) % 7);

  insert into public.event_series (club_id, competition_id, weekday, every_weeks, first_date, count,
                                   start_time, venue, created_by)
  values (v_comp.club_id, v_comp.id, p_weekday, p_every_weeks, v_first, p_count,
          p_start_time, v_venue, auth.uid())
  returning id into v_series;

  for i in 0 .. p_count - 1 loop
    v_date := v_first + i * 7 * p_every_weeks;
    v_id := null;
    insert into public.events (club_id, competition_id, event_date, start_time, venue, series_id)
    values (v_comp.club_id, v_comp.id, v_date, p_start_time, v_venue, v_series)
    on conflict (competition_id, event_date) where competition_id is not null do nothing
    returning id into v_id;
    if v_id is null then
      v_skipped := v_skipped || v_date;
    else
      v_ids := v_ids || v_id;
      v_dates := v_dates || v_date;
    end if;
  end loop;

  if cardinality(v_ids) = 0 then
    delete from public.event_series where id = v_series;
    v_series := null;
  end if;

  return jsonb_build_object(
    'series_id', v_series,
    'event_ids', to_jsonb(v_ids),
    'dates', to_jsonb(v_dates),
    'skipped', to_jsonb(v_skipped));
end;
$$;
revoke all on function public.create_event_series(uuid, date, smallint, smallint, smallint, time, text) from public, anon;
grant execute on function public.create_event_series(uuid, date, smallint, smallint, smallint, time, text) to authenticated;


create or replace function public.update_event_series(
  p_event_id   uuid,
  p_scope      text,
  p_start_time time,
  p_venue      text,
  p_new_date   date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event    public.events%rowtype;
  v_venue    text;
  v_shift    int := 0;
  v_updated  uuid[] := '{}';
  v_skipped  uuid[] := '{}';
  v_row      record;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select e.* into v_event from public.events e where e.id = p_event_id;
  if v_event.id is null
     or not (public.is_club_member(v_event.club_id)
             or (v_event.competition_id is not null and public.can_read_competition(v_event.competition_id))) then
    raise exception 'Fant ikke kvelden' using errcode = 'P0002';
  end if;
  if not private.has_club_right(v_event.club_id, 'tournaments') then
    raise exception 'Bare den som styrer turneringer, kan endre spilledager' using errcode = '42501';
  end if;
  if p_scope is null or p_scope not in ('one', 'future') then
    raise exception 'Omfanget må være one eller future' using errcode = '22023';
  end if;
  v_venue := private.series_venue(p_venue);
  -- Lås turneringen (eller klubben) så to endringer ikke krysser hverandre.
  if v_event.competition_id is not null then
    perform 1 from public.competitions c where c.id = v_event.competition_id for update;
  end if;
  select e.* into v_event from public.events e where e.id = p_event_id for update;
  if p_new_date is not null then
    v_shift := p_new_date - v_event.event_date;
  end if;

  if p_scope = 'one' then
    begin
      update public.events e
         set start_time = p_start_time,
             venue = v_venue,
             event_date = e.event_date + v_shift,
             signup_deadline = e.signup_deadline + make_interval(days => v_shift),
             withdraw_deadline = e.withdraw_deadline + make_interval(days => v_shift)
       where e.id = v_event.id;
    exception when unique_violation then
      raise exception 'Turneringen har alt en kveld %', to_char(p_new_date, 'DD.MM.YYYY')
        using errcode = '23505';
    end;
    return jsonb_build_object('updated', to_jsonb(array[v_event.id]), 'skipped', '[]'::jsonb,
                              'shifted_days', v_shift);
  end if;

  -- 'future'
  if v_event.series_id is null then
    raise exception 'Kvelden er ikke en del av en serie' using errcode = '22023';
  end if;
  if p_new_date is not null and p_new_date < current_date then
    raise exception 'Den nye datoen er passert' using errcode = '22023';
  end if;
  -- Kvelder som flyttes, tas i en rekkefølge som ikke kolliderer med hverandre underveis
  -- (fram i tid: den siste først).
  for v_row in
    select e.id, e.event_date,
           (e.event_date < current_date or private.event_has_started_round(e.id)) as frozen
      from public.events e
     where e.series_id = v_event.series_id and e.event_date >= v_event.event_date
     order by case when v_shift > 0 then e.event_date end desc,
              case when v_shift <= 0 then e.event_date end asc
       for update
  loop
    if v_row.frozen then
      v_skipped := v_skipped || v_row.id;
      continue;
    end if;
    begin
      update public.events e
         set start_time = p_start_time,
             venue = v_venue,
             event_date = e.event_date + v_shift,
             signup_deadline = e.signup_deadline + make_interval(days => v_shift),
             withdraw_deadline = e.withdraw_deadline + make_interval(days => v_shift)
       where e.id = v_row.id;
    exception when unique_violation then
      raise exception 'Turneringen har alt en kveld %', to_char(v_row.event_date + v_shift, 'DD.MM.YYYY')
        using errcode = '23505';
    end;
    v_updated := v_updated || v_row.id;
  end loop;

  update public.event_series s
     set start_time = p_start_time,
         venue = v_venue,
         weekday = case when v_shift = 0 then s.weekday
                        else extract(isodow from v_event.event_date + v_shift)::smallint end
   where s.id = v_event.series_id;

  return jsonb_build_object('updated', to_jsonb(v_updated), 'skipped', to_jsonb(v_skipped),
                            'shifted_days', v_shift);
end;
$$;
revoke all on function public.update_event_series(uuid, text, time, text, date) from public, anon;
grant execute on function public.update_event_series(uuid, text, time, text, date) to authenticated;


-- ===========================================================================
-- 2. EGNE MALER
-- ===========================================================================
create table if not exists public.setup_templates (
  id          uuid primary key default gen_random_uuid(),
  club_id     uuid references public.clubs(id) on delete cascade,
  owner_id    uuid references auth.users(id) on delete cascade,
  kind        text not null check (kind in ('round', 'tournament')),
  name        text not null check (char_length(btrim(name)) between 1 and 60),
  payload     jsonb not null default '{}'::jsonb,
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint setup_templates_one_home check ((club_id is null) <> (owner_id is null)),
  constraint setup_templates_payload_shape check (jsonb_typeof(payload) = 'object'
                                                  and octet_length(payload::text) <= 32768)
);
comment on table public.setup_templates is
  'Egne maler: oppsett for en runde (kind = round) eller en turnering (kind = tournament). '
  'Klubbens (club_id) eller personlig (owner_id). payload tolkes av appen, høyst 32 kB. '
  'Skrives bare av setup_template_save og setup_template_delete.';
create unique index if not exists setup_templates_club_name
  on public.setup_templates (club_id, kind, lower(btrim(name))) where club_id is not null;
create unique index if not exists setup_templates_owner_name
  on public.setup_templates (owner_id, kind, lower(btrim(name))) where owner_id is not null;

alter table public.setup_templates enable row level security;
revoke all on table public.setup_templates from public, anon, authenticated;
grant select on table public.setup_templates to authenticated;
grant all on table public.setup_templates to service_role;

drop policy if exists setup_templates_select on public.setup_templates;
create policy setup_templates_select on public.setup_templates
  for select to authenticated
  using (   (club_id is not null and (private.has_club_right(club_id, 'rounds')
                                      or private.has_club_right(club_id, 'tournaments')))
         or (owner_id is not null and owner_id = (select auth.uid())));

drop trigger if exists setup_templates_set_updated_at on public.setup_templates;
create trigger setup_templates_set_updated_at before update on public.setup_templates
  for each row execute function public.set_updated_at();

-- Kan innloggingen skrive en mal av typen i klubben (eller personlig når klubben er null)?
create or replace function private.template_can_write(p_club_id uuid, p_owner_id uuid, p_kind text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
           when p_club_id is not null then
             private.has_club_right(p_club_id, case when p_kind = 'round' then 'rounds' else 'tournaments' end)
           else coalesce(p_owner_id = (select auth.uid()), false)
         end;
$$;
revoke all on function private.template_can_write(uuid, uuid, text) from public, anon, authenticated;

create or replace function public.setup_template_save(
  p_id      uuid,
  p_club_id uuid,
  p_kind    text,
  p_name    text,
  p_payload jsonb)
returns public.setup_templates
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old  public.setup_templates%rowtype;
  v_row  public.setup_templates%rowtype;
  v_name text := btrim(coalesce(p_name, ''));
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if p_kind is null or p_kind not in ('round', 'tournament') then
    raise exception 'Malen må være round eller tournament' using errcode = '22023';
  end if;
  if char_length(v_name) not between 1 and 60 then
    raise exception 'Navnet må ha 1–60 tegn' using errcode = '22023';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Malen må være et objekt' using errcode = '22023';
  end if;
  if octet_length(p_payload::text) > 32768 then
    raise exception 'Malen er for stor (høyst 32 kB)' using errcode = '22023';
  end if;
  if p_club_id is not null and not public.is_club_member(p_club_id) then
    raise exception 'Fant ikke klubben' using errcode = 'P0002';
  end if;

  if p_id is null then
    if not private.template_can_write(p_club_id, auth.uid(), p_kind) then
      raise exception 'Du har ikke rettighet til å lagre denne malen' using errcode = '42501';
    end if;
    if (select count(*) from public.setup_templates t
         where (p_club_id is not null and t.club_id = p_club_id)
            or (p_club_id is null and t.owner_id = auth.uid())) >= 200 then
      raise exception 'Høyst 200 maler' using errcode = '54000';
    end if;
    begin
      insert into public.setup_templates (club_id, owner_id, kind, name, payload, created_by)
      values (p_club_id, case when p_club_id is null then auth.uid() end, p_kind, v_name, p_payload, auth.uid())
      returning * into v_row;
    exception when unique_violation then
      raise exception 'Det finnes alt en mal med navnet «%»', v_name using errcode = '23505';
    end;
    return v_row;
  end if;

  select t.* into v_old from public.setup_templates t where t.id = p_id for update;
  if v_old.id is null
     or not ((v_old.club_id is not null and (private.has_club_right(v_old.club_id, 'rounds')
                                             or private.has_club_right(v_old.club_id, 'tournaments')))
             or coalesce(v_old.owner_id = auth.uid(), false)) then
    raise exception 'Fant ikke malen' using errcode = 'P0002';
  end if;
  if v_old.club_id is distinct from p_club_id or v_old.kind <> p_kind then
    raise exception 'Klubb og type kan ikke endres på en mal' using errcode = '22023';
  end if;
  if not private.template_can_write(v_old.club_id, v_old.owner_id, v_old.kind) then
    raise exception 'Du har ikke rettighet til å endre denne malen' using errcode = '42501';
  end if;
  begin
    update public.setup_templates t
       set name = v_name, payload = p_payload
     where t.id = v_old.id
    returning * into v_row;
  exception when unique_violation then
    raise exception 'Det finnes alt en mal med navnet «%»', v_name using errcode = '23505';
  end;
  return v_row;
end;
$$;
revoke all on function public.setup_template_save(uuid, uuid, text, text, jsonb) from public, anon;
grant execute on function public.setup_template_save(uuid, uuid, text, text, jsonb) to authenticated;

create or replace function public.setup_template_delete(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old public.setup_templates%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select t.* into v_old from public.setup_templates t where t.id = p_id for update;
  if v_old.id is null
     or not ((v_old.club_id is not null and (private.has_club_right(v_old.club_id, 'rounds')
                                             or private.has_club_right(v_old.club_id, 'tournaments')))
             or coalesce(v_old.owner_id = auth.uid(), false)) then
    raise exception 'Fant ikke malen' using errcode = 'P0002';
  end if;
  if not private.template_can_write(v_old.club_id, v_old.owner_id, v_old.kind) then
    raise exception 'Du har ikke rettighet til å slette denne malen' using errcode = '42501';
  end if;
  delete from public.setup_templates t where t.id = v_old.id;
  return true;
end;
$$;
revoke all on function public.setup_template_delete(uuid) from public, anon;
grant execute on function public.setup_template_delete(uuid) to authenticated;


-- ===========================================================================
-- 3. «SAMME SOM SIST»
-- ===========================================================================
create or replace function public.previous_round_setup(p_event_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_event public.events%rowtype;
  v_r     public.rounds%rowtype;
  v_date  date;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select e.* into v_event from public.events e where e.id = p_event_id;
  if v_event.id is null
     or not (public.is_club_member(v_event.club_id)
             or (v_event.competition_id is not null and public.can_read_competition(v_event.competition_id))) then
    raise exception 'Fant ikke kvelden' using errcode = 'P0002';
  end if;
  if not (private.has_club_right(v_event.club_id, 'rounds')
          or (v_event.competition_id is not null
              and exists (select 1 from public.competition_staff s
                           where s.competition_id = v_event.competition_id
                             and s.profile_id = auth.uid() and s.role = 'organizer'))) then
    raise exception 'Bare den som setter opp runder, kan hente forrige oppsett' using errcode = '42501';
  end if;

  select r.* into v_r
    from public.rounds r
    join public.events e on e.id = r.event_id
   where e.club_id = v_event.club_id
     and e.competition_id is not distinct from v_event.competition_id
     and e.event_date <= v_event.event_date
     and r.kind = 'normal'
     and r.status in ('active', 'locked')
   order by e.event_date desc, r.round_no desc, coalesce(r.started_at, r.created_at) desc, r.id
   limit 1;
  if v_r.id is null then
    return null;
  end if;
  select e.event_date into v_date from public.events e where e.id = v_r.event_id;

  return jsonb_build_object(
    'round_id', v_r.id,
    'event_id', v_r.event_id,
    'event_date', v_date,
    'round_no', v_r.round_no,
    'name', v_r.name,
    'status', v_r.status,
    'course_id', v_r.course_id,
    'tee_id', v_r.tee_id,
    'hole_count', v_r.hole_count,
    'first_hole', v_r.first_hole,
    'format', v_r.format,
    'handicap_allowance', v_r.handicap_allowance,
    'external_handicap', v_r.external_handicap,
    'venue', v_r.venue,
    'ld_enabled', v_r.ld_enabled,
    'ld_hole_index', v_r.ld_hole_index,
    'kp_enabled', v_r.kp_enabled,
    'kp_hole_index', v_r.kp_hole_index,
    'weight', v_r.weight,
    'counts', v_r.counts,
    'points_table', v_r.points_table,
    'hide_last_holes', v_r.hide_last_holes,
    'wave_no', v_r.wave_no,
    'players', coalesce((
      select jsonb_agg(jsonb_build_object('member_id', rp.member_id, 'bay_no', rp.bay_no,
                                          'is_marker', rp.is_marker, 'team_no', rp.team_no,
                                          'seed_group', rp.seed_group)
                       order by rp.bay_no nulls last, rp.is_marker desc, m.display_name)
        from public.round_players rp
        join public.club_members m on m.id = rp.member_id
       where rp.round_id = v_r.id and m.status = 'active'), '[]'::jsonb),
    'matches', coalesce((
      select jsonb_agg(jsonb_build_object('match_no', rm.match_no, 'player_a', rm.player_a,
                                          'player_b', rm.player_b, 'player_c', rm.player_c,
                                          'team_a', rm.team_a, 'team_b', rm.team_b)
                       order by rm.match_no)
        from public.round_matches rm where rm.round_id = v_r.id), '[]'::jsonb),
    'games', coalesce((
      select jsonb_agg(jsonb_build_object('kind', g.kind, 'settings', g.settings) order by g.created_at, g.id)
        from public.round_games g where g.round_id = v_r.id), '[]'::jsonb));
end;
$$;
revoke all on function public.previous_round_setup(uuid) from public, anon;
grant execute on function public.previous_round_setup(uuid) to authenticated;


-- ===========================================================================
-- KONTROLL (10 sjekker; feiler hele transaksjonen ved avvik)
-- ===========================================================================
do $$
declare
  v_fail text := '';
begin
  -- 1. Tabellene og kolonnen finnes.
  if to_regclass('public.event_series') is null or to_regclass('public.setup_templates') is null
     or not exists (select 1 from information_schema.columns
                     where table_schema = 'public' and table_name = 'events' and column_name = 'series_id') then
    v_fail := v_fail || ' 1';
  end if;
  -- 2. Reglene på kveldene: nøkkelen til serien i samme turnering, og serie krever turnering.
  if (select count(*) from pg_constraint where conrelid = 'public.events'::regclass
        and conname in ('events_series_fk', 'events_series_needs_competition')) <> 2
     or (select count(*) from pg_constraint where conrelid = 'public.event_series'::regclass
        and conname in ('event_series_competition_fk', 'event_series_id_competition_key')) <> 2 then
    v_fail := v_fail || ' 2';
  end if;
  -- 3. Malene: klubb eller eier, objekt på høyst 32 kB, unike navn.
  if (select count(*) from pg_constraint where conrelid = 'public.setup_templates'::regclass
        and conname in ('setup_templates_one_home', 'setup_templates_payload_shape')) <> 2
     or (select pg_get_constraintdef(oid) from pg_constraint
          where conname = 'setup_templates_payload_shape') not like '%32768%'
     or (select count(*) from pg_index i join pg_class c on c.oid = i.indexrelid
          where c.relname in ('setup_templates_club_name', 'setup_templates_owner_name') and i.indisunique) <> 2 then
    v_fail := v_fail || ' 3';
  end if;
  -- 4. RLS på, bare lesepolicyer, authenticated har bare select, anon ingenting.
  if not (select relrowsecurity from pg_class where oid = 'public.event_series'::regclass)
     or not (select relrowsecurity from pg_class where oid = 'public.setup_templates'::regclass)
     or exists (select 1 from pg_policies where schemaname = 'public'
                 and tablename in ('event_series', 'setup_templates') and cmd <> 'SELECT')
     or (select count(*) from pg_policies where schemaname = 'public'
          and tablename in ('event_series', 'setup_templates')) <> 2
     or has_table_privilege('authenticated', 'public.event_series', 'insert, update, delete')
     or has_table_privilege('authenticated', 'public.setup_templates', 'insert, update, delete')
     or has_table_privilege('anon', 'public.event_series', 'select')
     or has_table_privilege('anon', 'public.setup_templates', 'select') then
    v_fail := v_fail || ' 4';
  end if;
  -- 5. RPC-ene: authenticated kan, anon kan ikke. Hjelperne kan ingen kalle.
  if has_function_privilege('anon', 'public.create_event_series(uuid, date, smallint, smallint, smallint, time, text)', 'execute')
     or has_function_privilege('anon', 'public.update_event_series(uuid, text, time, text, date)', 'execute')
     or has_function_privilege('anon', 'public.setup_template_save(uuid, uuid, text, text, jsonb)', 'execute')
     or has_function_privilege('anon', 'public.setup_template_delete(uuid)', 'execute')
     or has_function_privilege('anon', 'public.previous_round_setup(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.create_event_series(uuid, date, smallint, smallint, smallint, time, text)', 'execute')
     or not has_function_privilege('authenticated', 'public.update_event_series(uuid, text, time, text, date)', 'execute')
     or not has_function_privilege('authenticated', 'public.setup_template_save(uuid, uuid, text, text, jsonb)', 'execute')
     or not has_function_privilege('authenticated', 'public.setup_template_delete(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.previous_round_setup(uuid)', 'execute')
     or has_function_privilege('authenticated', 'private.events_unlink_series()', 'execute')
     or has_function_privilege('authenticated', 'private.series_venue(text)', 'execute')
     or has_function_privilege('authenticated', 'private.event_has_started_round(uuid)', 'execute')
     or has_function_privilege('authenticated', 'private.template_can_write(uuid, uuid, text)', 'execute') then
    v_fail := v_fail || ' 5';
  end if;
  -- 6. Alle funksjonene her er security definer med tom search_path.
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where (n.nspname, p.proname) in (('public', 'create_event_series'), ('public', 'update_event_series'),
                                               ('public', 'setup_template_save'), ('public', 'setup_template_delete'),
                                               ('public', 'previous_round_setup'), ('private', 'events_unlink_series'),
                                               ('private', 'series_venue'), ('private', 'event_has_started_round'),
                                               ('private', 'template_can_write'))
               and (not p.prosecdef or not ('search_path=""' = any (p.proconfig))))
     or (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where (n.nspname, p.proname) in (('public', 'create_event_series'), ('public', 'update_event_series'),
                                            ('public', 'setup_template_save'), ('public', 'setup_template_delete'),
                                            ('public', 'previous_round_setup'))) <> 5 then
    v_fail := v_fail || ' 6';
  end if;
  -- 7. Triggerne.
  if (select count(*) from pg_trigger where not tgisinternal
        and ((tgname = 'events_unlink_series' and tgrelid = 'public.events'::regclass)
          or (tgname = 'event_series_set_updated_at' and tgrelid = 'public.event_series'::regclass)
          or (tgname = 'setup_templates_set_updated_at' and tgrelid = 'public.setup_templates'::regclass))) <> 3 then
    v_fail := v_fail || ' 7';
  end if;
  -- 8. 034 står: én spilledag per turnering og dato, ingen grense per klubb og dato.
  if to_regclass('public.events_one_per_date_per_competition') is null
     or to_regclass('public.events_one_per_date') is not null then
    v_fail := v_fail || ' 8';
  end if;
  -- 9. Hver kveld i en serie hører til seriens turnering og klubb.
  if exists (select 1 from public.events e join public.event_series s on s.id = e.series_id
              where e.competition_id <> s.competition_id or e.club_id <> s.club_id) then
    v_fail := v_fail || ' 9';
  end if;
  -- 10. Hver mal har nøyaktig ett hjem og et gyldig innhold.
  if exists (select 1 from public.setup_templates t
              where (t.club_id is null) = (t.owner_id is null)
                 or jsonb_typeof(t.payload) <> 'object' or octet_length(t.payload::text) > 32768) then
    v_fail := v_fail || ' 10';
  end if;

  if v_fail <> '' then
    raise exception '049 kontroll feilet:%', v_fail;
  end if;
  raise notice '049 kontroll: 10 av 10 (serier: %, kvelder i serie: %, maler: %)',
    (select count(*) from public.event_series),
    (select count(*) from public.events where series_id is not null),
    (select count(*) from public.setup_templates);
end $$;

commit;

-- ===========================================================================
-- RULLEBAKKE (sletter seriene og malene; kveldene blir stående som enkeltkvelder)
-- ===========================================================================
-- begin;
-- drop function if exists public.previous_round_setup(uuid);
-- drop function if exists public.setup_template_delete(uuid);
-- drop function if exists public.setup_template_save(uuid, uuid, text, text, jsonb);
-- drop function if exists private.template_can_write(uuid, uuid, text);
-- drop table if exists public.setup_templates;
-- drop function if exists public.update_event_series(uuid, text, time, text, date);
-- drop function if exists public.create_event_series(uuid, date, smallint, smallint, smallint, time, text);
-- drop function if exists private.event_has_started_round(uuid);
-- drop function if exists private.series_venue(text);
-- drop trigger if exists events_unlink_series on public.events;
-- drop function if exists private.events_unlink_series();
-- drop index if exists public.events_series_idx;
-- alter table public.events
--   drop constraint if exists events_series_needs_competition,
--   drop constraint if exists events_series_fk;
-- alter table public.events drop column if exists series_id;
-- drop table if exists public.event_series;
-- commit;
