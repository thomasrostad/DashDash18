-- ===========================================================================
-- 022 – FLERE KONKURRANSER SAMTIDIG (FASE 15) – FORSLAG, IKKE KJØRT
-- ===========================================================================
-- Status: FORSLAG til godkjenning (ROADMAP B5). IKKE KJØRT mot Supabase,
-- verken test eller prod. Prøvd mot en lokal, midlertidig Postgres
-- (sql/lokal/022_prove.sql). Krever 001–017 (competitions,
-- competition_participants, competition_rounds og hjelperne
-- can_read_competition, is_competition_admin, is_competition_participant,
-- can_link_round) og 018 (kodene: round_invite_code, round_invite_normalize).
-- Bruker ikke 019–021, men tåler at de er kjørt. 023 er fase 17.
--
-- Hvorfor (docs/visjon-apen-app.md, fase 15): liga, cup og morroturneringer
-- ved siden av jakkeracet, og «Teller også i …» når en runde settes opp.
-- 017 har konkurransene og koblingen til rundene. Det som mangler, er:
--   1. Åpen påmelding: arrangøren/eieren slår den på, og den som kan se
--      konkurransen, melder seg på selv («Meld meg på»). 017 lar bare
--      arrangøren legge til påmeldte.
--   2. Cup: trekningen og kampene (hvem møter hvem, hvem gikk videre).
--   3. Én transaksjon for det som skriver flere rader: ny konkurranse med
--      deltakere, «Teller også i …» for en runde (legg til og ta bort), og
--      trekningen.
--   4. Invitasjon til en privat konkurranse med kode eller lenke
--      (besluttet 07.10.2026), som løse runder i 018.
--
-- Hva fila gjør:
--   * competitions.signup_open (av som standard). Bare for entry = listed.
--   * competition_matches: én rad per cupkamp (runde, plass i treet, to
--     påmeldte, vinner, walkover, resultattekst, runden kampen ble spilt i,
--     hvem som førte: recorded_by).
--     Første runde skrives av trekningen (bye = kamp uten b, med vinner).
--     Senere runder skrives når et resultat føres; spillerne er vinnerne av de
--     to kampene før. Treet regnes i appen (GolfgutuCore, Cup.bracket) fra
--     disse radene; databasen sjekker at hver rad passer i treet.
--   * competition_invites: én kode per privat konkurranse (10 tegn Crockford
--     base32 = 50 bit, utløper etter 7 dager, samme form og kodefunksjoner
--     som round_invites i 018). Lenken er dashdash://konkurranse/<KODE>.
--     Bare eieren og de påmeldte ser koden; bare eieren lager, fornyer og
--     trekker den tilbake.
--   * RPC-er (hver i én transaksjon):
--       create_competition_with_entrants  ny konkurranse med påmeldte
--       join_competition / leave_competition  meld meg på / av
--       set_round_competitions  «Teller også i …» for en runde
--       draw_cup  trekningen (første runde), på nytt til første resultat
--       record_cup_result  vinneren av en kamp (eller fjerne den)
--       competition_invite  koden til en privat konkurranse (eieren fornyer)
--       revoke_competition_invite  eieren trekker koden tilbake
--       competition_invite_preview  navn, type, eier og antall påmeldte
--       claim_competition_invite  «Bli med»: melder deg på
--   * Ingen regelverdier i SQL. Ligaens poeng, beste N, seeding og regelen
--     for uavgjort ligger i konkurransens regelsett (rules -> competition) og
--     regnes i appen.
--
-- Tilgang:
--   * competition_matches leses av den som kan se konkurransen
--     (can_read_competition, 017). Ingen skriver direkte; bare RPC-ene.
--   * Melde seg på: konkurransen må være synlig, åpen for påmelding, ikke
--     ferdig, og en cup kan ikke være trukket. I en klubbkonkurranse meldes
--     medlemmet på (du må være aktivt medlem), ellers profilen.
--   * «Teller også i»: du må styre konkurransen (is_competition_admin) OG eie
--     runden (can_link_round, som policyen i 017), og minst én av spillerne i
--     runden må være med i konkurransen. Sesongens konkurranse kobles fortsatt
--     bare av triggeren, og spill på runden (kind = game) kobles ikke her.
--   * Trekning: arrangøren / eieren av konkurransen.
--   * Resultat i en cupkamp (besluttet 07.10.2026): de to spillerne i kampen
--     fører selv, og arrangøren / eieren kan rette. Første førte resultat
--     gjelder: en spiller som fører etter at resultatet står, avvises (55000),
--     og bare arrangøren / eieren kan endre eller fjerne det.
--   * Invitasjon: bare private konkurranser (uten klubb). Eieren og de
--     påmeldte henter koden som gjelder; bare eieren lager, fornyer og trekker
--     den tilbake (sikkerhetsrevisjonen 07.10.2026). Den som har koden, ser
--     navn, type, eier og antall
--     påmeldte, og kan melde seg på. Koden gjelder ikke når konkurransen er
--     ferdig, og en trukket cup tar ingen nye.
--
-- Ingen endring i policyene eller funksjonene fra 017 og 018. Én ny unik
-- indeks på competition_participants (id, competition_id), så kampene kan
-- peke på en påmeldt i SAMME konkurranse med en sammensatt fremmednøkkel.
--
-- Mønsteret fra 001–021 følges: én transaksjon, idempotent, `set search_path
-- = ''`, `revoke … from public, anon` ETTER hver create or replace, og
-- indre hjelpere og triggerfunksjoner tas fra authenticated også.
-- ===========================================================================

begin;


-- ===========================================================================
-- 1. ÅPEN PÅMELDING
-- ===========================================================================
alter table public.competitions add column if not exists signup_open boolean not null default false;
comment on column public.competitions.signup_open is
  'Åpen påmelding: den som kan se konkurransen, melder seg på selv (join_competition). Bare entry = listed.';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'competitions_signup_listed'
                   and conrelid = 'public.competitions'::regclass) then
    alter table public.competitions
      add constraint competitions_signup_listed check (not signup_open or entry = 'listed');
  end if;
end $$;

-- En påmeldt i en bestemt konkurranse (mål for kampenes fremmednøkkel).
create unique index if not exists competition_participants_id_competition
  on public.competition_participants (id, competition_id);


-- ===========================================================================
-- 2. CUPKAMPENE
-- ===========================================================================
create table if not exists public.competition_matches (
  id              uuid primary key default gen_random_uuid(),
  competition_id  uuid not null references public.competitions(id) on delete cascade,
  -- 1 = første runde. Finalen er runde log2(plasser i treet).
  round_no        smallint not null check (round_no between 1 and 10),
  -- Plassen i runden, ovenfra (0 …). Vinneren går til slot / 2 i neste runde.
  slot            smallint not null check (slot between 0 and 511),
  player_a        uuid,
  -- Tom i første runde: bye (a går videre uten kamp).
  player_b        uuid,
  winner          uuid,
  -- Motstanderen stilte ikke eller trakk seg.
  walkover        boolean not null default false,
  -- Fritekst fra appen, f.eks. «3&2» eller «countback».
  result          text check (char_length(result) <= 40),
  -- Runden kampen ble spilt i (må telle i konkurransen).
  round_id        uuid references public.rounds(id) on delete set null,
  -- Hvem som førte resultatet (spilleren selv, arrangøren eller eieren), og
  -- når. Byer i trekningen: den som trakk.
  recorded_by     uuid references public.profiles(id) on delete set null,
  recorded_at     timestamptz,
  created_at      timestamptz not null default now(),
  constraint competition_matches_slot_key unique (competition_id, round_no, slot),
  -- De påmeldte er i samme konkurranse. Ingen cascade: en påmeldt som er
  -- trukket, meldes av (status), ikke slettes. Hele konkurransen kan slettes.
  constraint competition_matches_a_fk foreign key (player_a, competition_id)
    references public.competition_participants (id, competition_id),
  constraint competition_matches_b_fk foreign key (player_b, competition_id)
    references public.competition_participants (id, competition_id),
  constraint competition_matches_two check (player_a is null or player_b is null or player_a <> player_b),
  constraint competition_matches_winner check (winner is null or winner = player_a or winner = player_b),
  constraint competition_matches_bye check (player_b is not null or round_no = 1)
);
comment on table public.competition_matches is
  'Cupkampene (fase 15). Første runde fra trekningen (draw_cup), senere runder fra record_cup_result. '
  'Treet regnes i appen. Bare RPC-ene skriver. recorded_by = hvem som førte.';
create index if not exists competition_matches_round_idx on public.competition_matches (round_id) where round_id is not null;


-- ===========================================================================
-- 3. HJELPERE
-- ===========================================================================

-- Hvor mange av spillerne i runden er med i konkurransen? open: alle. club:
-- medlemmer i klubben (også når de spiller en løs runde med profilen sin).
-- listed: de aktive påmeldte, som medlem eller profil. Indre hjelper for
-- set_round_competitions; authenticated kan ikke kalle den.
create or replace function public.competition_round_entrants(p_competition_id uuid, p_round_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  with c as (
    select id, club_id, entry from public.competitions where id = p_competition_id
  ),
  players as (
    select rp.member_id,
           rp.club_id,
           coalesce(m.user_id, pa.profile_id) as profile_id
    from public.round_players rp
    left join public.club_members m on m.id = rp.member_id and rp.club_id is not null
    left join public.round_participants pa on pa.id = rp.member_id and pa.round_id = rp.round_id and rp.club_id is null
    where rp.round_id = p_round_id
  )
  select count(*)::integer
  from players p, c
  where case c.entry
    when 'open' then true
    when 'club' then
         p.club_id = c.club_id
      or exists (select 1 from public.club_members m2
                 where m2.club_id = c.club_id and m2.status = 'active' and m2.user_id = p.profile_id)
    else exists (
      select 1 from public.competition_participants cp
      left join public.club_members m3 on m3.id = cp.member_id
      where cp.competition_id = c.id and cp.status = 'active'
        and (   (cp.member_id is not null and cp.member_id = p.member_id and p.club_id is not null)
             or (cp.profile_id is not null and cp.profile_id = p.profile_id)
             or (m3.user_id is not null and m3.user_id = p.profile_id)))
  end;
$$;
revoke all on function public.competition_round_entrants(uuid, uuid) from public, anon, authenticated;


-- ===========================================================================
-- 4. RLS OG RETTIGHETER
-- ===========================================================================
alter table public.competition_matches enable row level security;

do $$
declare
  p record;
begin
  for p in select policyname from pg_policies where schemaname = 'public' and tablename = 'competition_matches' loop
    execute format('drop policy if exists %I on public.competition_matches', p.policyname);
  end loop;
end $$;

create policy competition_matches_select on public.competition_matches
  for select to authenticated using (public.can_read_competition(competition_id));

revoke all on table public.competition_matches from public, anon, authenticated;
grant select on table public.competition_matches to authenticated;


-- ===========================================================================
-- 5. RPC-ER (én transaksjon hver)
-- ===========================================================================

-- --- create_competition_with_entrants -----------------------------------------
-- Ny liga, cup eller morroturnering med påmeldte i ett kall. Bygger på
-- create_competition (017: arrangør i klubben, eller du blir eier og første
-- påmeldte). Påmeldte: medlemmer i klubben (p_member_ids) og profiler du kan
-- se (p_profile_ids, sjekket av vakta fra 017). En cup trenger påmeldte
-- (entry = listed). Gir konkurransens id.
create or replace function public.create_competition_with_entrants(
  p_kind         text,
  p_name         text,
  p_club_id      uuid    default null,
  p_entry        text    default 'listed',
  p_rules        jsonb   default null,
  p_starts_on    date    default null,
  p_ends_on      date    default null,
  p_signup_open  boolean default false,
  p_member_ids   uuid[]  default '{}',
  p_profile_ids  uuid[]  default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if p_kind is null or p_kind not in ('league', 'cup', 'fun') then
    raise exception 'Velg liga, cup eller morroturnering' using errcode = '22023';
  end if;
  if p_entry is null or p_entry not in ('club', 'listed', 'open') then
    raise exception 'Ukjent påmelding' using errcode = '22023';
  end if;
  if p_kind = 'cup' and p_entry <> 'listed' then
    raise exception 'En cup trenger påmeldte' using errcode = '22023';
  end if;
  if coalesce(p_signup_open, false) and p_entry <> 'listed' then
    raise exception 'Åpen påmelding gjelder bare konkurranser med påmeldte' using errcode = '22023';
  end if;
  if cardinality(coalesce(p_member_ids, '{}')) + cardinality(coalesce(p_profile_ids, '{}')) > 200 then
    raise exception 'Høyst 200 påmeldte om gangen' using errcode = '22023';
  end if;
  if p_club_id is null and cardinality(coalesce(p_member_ids, '{}')) > 0 then
    raise exception 'Medlemmer kan bare meldes på en klubbkonkurranse' using errcode = '22023';
  end if;
  if p_club_id is not null and exists (
       select 1 from unnest(coalesce(p_member_ids, '{}')) x
       where not exists (select 1 from public.club_members m
                         where m.id = x and m.club_id = p_club_id and m.status = 'active')) then
    raise exception 'Bare aktive medlemmer i klubben kan meldes på' using errcode = '22023';
  end if;

  -- Sjekkene for klubb og eier, navn, regelsett og periode står i 017.
  v_id := public.create_competition(p_kind, p_name, p_club_id, p_entry, p_rules, p_starts_on, p_ends_on);

  if coalesce(p_signup_open, false) then
    update public.competitions set signup_open = true where id = v_id;
  end if;

  insert into public.competition_participants (competition_id, member_id)
  select v_id, x from (select distinct unnest(coalesce(p_member_ids, '{}')) x) m
  on conflict do nothing;
  -- Vakta (017) nekter profiler du ikke kan se (42501).
  insert into public.competition_participants (competition_id, profile_id)
  select v_id, x from (select distinct unnest(coalesce(p_profile_ids, '{}')) x) p
  on conflict do nothing;

  return v_id;
end;
$$;
revoke all on function public.create_competition_with_entrants(text, text, uuid, text, jsonb, date, date, boolean, uuid[], uuid[])
  from public, anon;
grant execute on function public.create_competition_with_entrants(text, text, uuid, text, jsonb, date, date, boolean, uuid[], uuid[])
  to authenticated;


-- --- join_competition: «Meld meg på» -----------------------------------------
-- Konkurransen må være synlig, åpen for påmelding og ikke ferdig, og en cup kan
-- ikke være trukket. Klubbkonkurranse: medlemmet ditt (aktivt). Ellers:
-- profilen. Har du meldt deg av, meldes du på igjen. Idempotent. Gir raden.
create or replace function public.join_competition(p_competition_id uuid)
returns public.competition_participants
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_c       public.competitions;
  v_member  uuid;
  v_me      public.profiles;
  v_row     public.competition_participants;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select * into v_c from public.competitions where id = p_competition_id;
  if v_c.id is null or not public.can_read_competition(v_c.id) then
    raise exception 'Fant ikke konkurransen' using errcode = 'P0002';
  end if;
  if not v_c.signup_open then
    raise exception 'Påmeldingen er ikke åpen' using errcode = '55000';
  end if;
  if v_c.status = 'finished' then
    raise exception 'Konkurransen er ferdig' using errcode = '55000';
  end if;
  if v_c.kind = 'cup' and exists (select 1 from public.competition_matches where competition_id = v_c.id) then
    raise exception 'Cupen er trukket. Spør arrangøren.' using errcode = '55000';
  end if;

  if v_c.club_id is not null then
    select m.id into v_member from public.club_members m
    where m.club_id = v_c.club_id and m.user_id = auth.uid() and m.status = 'active'
    order by m.id limit 1;
    if v_member is null then
      raise exception 'Du må være medlem i klubben' using errcode = '42501';
    end if;
    select * into v_row from public.competition_participants
    where competition_id = v_c.id and member_id = v_member;
    if v_row.id is null then
      insert into public.competition_participants (competition_id, member_id)
      values (v_c.id, v_member) returning * into v_row;
    end if;
  else
    v_me := public.ensure_profile();
    select * into v_row from public.competition_participants
    where competition_id = v_c.id and profile_id = v_me.id;
    if v_row.id is null then
      insert into public.competition_participants (competition_id, profile_id)
      values (v_c.id, v_me.id) returning * into v_row;
    end if;
  end if;

  if v_row.status <> 'active' then
    update public.competition_participants set status = 'active' where id = v_row.id returning * into v_row;
  end if;
  return v_row;
end;
$$;
revoke all on function public.join_competition(uuid) from public, anon;
grant execute on function public.join_competition(uuid) to authenticated;


-- --- leave_competition: «Meld meg av» ----------------------------------------
-- Påmeldingen settes til withdrawn (raden står, så cupkampene og historikken
-- står). Er du i en cupkamp som ikke er avgjort, fører arrangøren walkover.
-- Gir true når du var påmeldt.
create or replace function public.leave_competition(p_competition_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_n integer;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  update public.competition_participants p
     set status = 'withdrawn'
   where p.competition_id = p_competition_id and p.status = 'active'
     and (p.profile_id = auth.uid() or public.owns_member(p.member_id));
  get diagnostics v_n = row_count;
  return v_n > 0;
end;
$$;
revoke all on function public.leave_competition(uuid) from public, anon;
grant execute on function public.leave_competition(uuid) to authenticated;


-- --- set_round_competitions: «Teller også i …» --------------------------------
-- Rundens ekstra konkurranser blir lista p_competition_ids, blant dem DU
-- styrer: de som mangler, legges til (source = manual), og dine manuelle som
-- ikke står i lista, tas bort. Andres koblinger og sesongens kobling røres
-- ikke. Krever at du eier runden (can_link_round) og styrer hver konkurranse,
-- at den er en liga, cup eller morroturnering som ikke er ferdig, og at minst
-- én av spillerne i runden er med i den. Gir {added, removed}.
create or replace function public.set_round_competitions(p_round_id uuid, p_competition_ids uuid[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ids      uuid[] := coalesce(p_competition_ids, '{}');
  v_added    integer;
  v_removed  integer;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if not exists (select 1 from public.rounds r where r.id = p_round_id) or not public.can_read_round(p_round_id) then
    raise exception 'Fant ikke runden' using errcode = 'P0002';
  end if;
  if not public.can_link_round(p_round_id) then
    raise exception 'Bare arrangøren eller eieren av runden kan legge den i en konkurranse' using errcode = '42501';
  end if;
  if cardinality(v_ids) > 20 then
    raise exception 'Høyst 20 konkurranser per runde' using errcode = '22023';
  end if;
  if exists (select 1 from unnest(v_ids) x where not public.is_competition_admin(x)) then
    raise exception 'Du kan bare legge runden i konkurranser du styrer' using errcode = '42501';
  end if;
  if exists (select 1 from unnest(v_ids) x join public.competitions c on c.id = x
             where c.kind not in ('league', 'cup', 'fun') or c.status = 'finished') then
    raise exception 'Runden kan bare telle i en liga, cup eller morroturnering som ikke er ferdig'
      using errcode = '22023';
  end if;
  if exists (select 1 from unnest(v_ids) x
             where public.competition_round_entrants(x, p_round_id) = 0) then
    raise exception 'Ingen av spillerne i runden er med i konkurransen' using errcode = '22023';
  end if;

  delete from public.competition_rounds cr
   where cr.round_id = p_round_id and cr.source = 'manual'
     and public.is_competition_admin(cr.competition_id)
     and not (cr.competition_id = any (v_ids));
  get diagnostics v_removed = row_count;

  insert into public.competition_rounds (competition_id, round_id, source, added_by)
  select distinct x, p_round_id, 'manual', auth.uid() from unnest(v_ids) x
  on conflict (competition_id, round_id) do nothing;
  get diagnostics v_added = row_count;

  return jsonb_build_object('added', v_added, 'removed', v_removed);
end;
$$;
revoke all on function public.set_round_competitions(uuid, uuid[]) from public, anon;
grant execute on function public.set_round_competitions(uuid, uuid[]) to authenticated;


-- --- draw_cup: trekningen -------------------------------------------------------
-- Første runde fra appen (seedet og trukket i GolfgutuCore, Cup.draw):
-- [{"slot": 0, "a": <påmeldt>, "b": <påmeldt eller null>}, …]. Sjekker at alle
-- aktive påmeldte er med nøyaktig én gang, at treet har riktig størrelse
-- (minste toerpotens), og at en bye bare finnes når det trengs. Kan trekkes på
-- nytt til første resultat er ført. Gir antall kamper i første runde.
create or replace function public.draw_cup(p_competition_id uuid, p_pairings jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_c       public.competitions;
  v_slots   integer;
  v_slot    integer[];
  v_a       uuid[];
  v_b       uuid[];
  v_players uuid[];
  v_active  integer;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select * into v_c from public.competitions where id = p_competition_id;
  if v_c.id is null or not public.can_read_competition(v_c.id) then
    raise exception 'Fant ikke konkurransen' using errcode = 'P0002';
  end if;
  if not public.is_competition_admin(v_c.id) then
    raise exception 'Bare arrangøren eller eieren trekker cupen' using errcode = '42501';
  end if;
  if v_c.kind <> 'cup' then
    raise exception 'Bare en cup trekkes' using errcode = '22023';
  end if;
  if v_c.status = 'finished' then
    raise exception 'Cupen er ferdig' using errcode = '55000';
  end if;
  if exists (select 1 from public.competition_matches m
             where m.competition_id = v_c.id and m.winner is not null and m.player_b is not null) then
    raise exception 'Cupen er i gang. Trekningen kan ikke gjøres om.' using errcode = '55000';
  end if;
  if p_pairings is null or jsonb_typeof(p_pairings) <> 'array' then
    raise exception 'Trekningen må være en liste' using errcode = '22023';
  end if;

  v_slots := jsonb_array_length(p_pairings);
  if v_slots < 1 or v_slots > 64 or (v_slots & (v_slots - 1)) <> 0 then
    raise exception 'Første runde må ha 1, 2, 4, 8 … kamper' using errcode = '22023';
  end if;

  begin
    select array_agg((e ->> 'slot')::integer order by i), array_agg((e ->> 'a')::uuid order by i),
           array_agg(nullif(e ->> 'b', '')::uuid order by i)
      into v_slot, v_a, v_b
    from jsonb_array_elements(p_pairings) with ordinality as t(e, i);
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'Ugyldig kamp i trekningen' using errcode = '22023';
  end;

  if (select count(distinct x) from unnest(v_slot) x where x between 0 and v_slots - 1) <> v_slots
     or array_position(v_a, null) is not null then
    raise exception 'Hver plass 0 … % må ha én kamp med en spiller a', v_slots - 1 using errcode = '22023';
  end if;

  v_players := v_a || array(select x from unnest(v_b) x where x is not null);
  select count(*) into v_active from public.competition_participants p
  where p.competition_id = v_c.id and p.status = 'active';

  if (select count(distinct x) from unnest(v_players) x) <> cardinality(v_players) then
    raise exception 'En spiller står to ganger i trekningen' using errcode = '22023';
  end if;
  if cardinality(v_players) <> v_active
     or exists (select 1 from unnest(v_players) x
                where not exists (select 1 from public.competition_participants p
                                  where p.id = x and p.competition_id = v_c.id and p.status = 'active')) then
    raise exception 'Trekningen må ha med alle aktive påmeldte, og bare dem' using errcode = '22023';
  end if;
  if v_active < 2 then
    raise exception 'En cup trenger minst to påmeldte' using errcode = '22023';
  end if;
  -- Minste tre: flere enn halvparten av plassene er fylt (to plasser for to).
  if v_slots > 1 and v_active <= v_slots then
    raise exception 'Treet er for stort for % påmeldte', v_active using errcode = '22023';
  end if;

  delete from public.competition_matches where competition_id = v_c.id;
  insert into public.competition_matches (competition_id, round_no, slot, player_a, player_b, winner,
                                          recorded_by, recorded_at)
  select v_c.id, 1, v_slot[i], v_a[i], v_b[i],
         case when v_b[i] is null then v_a[i] end,
         case when v_b[i] is null then auth.uid() end,
         case when v_b[i] is null then now() end
  from generate_subscripts(v_slot, 1) i;
  return v_slots;
end;
$$;
revoke all on function public.draw_cup(uuid, jsonb) from public, anon;
grant execute on function public.draw_cup(uuid, jsonb) to authenticated;


-- --- record_cup_result: vinneren av en kamp ---------------------------------------
-- Vinneren av kamp p_slot i runde p_round_no (1 = første). Spillerne er de
-- trukne (runde 1) eller vinnerne av kamp 2s og 2s + 1 i runden før.
-- Hvem (besluttet 07.10.2026):
--   * De to spillerne i kampen (aktiv påmelding, som profil eller medlem)
--     fører selv. Første førte resultat gjelder: står det et resultat, avvises
--     en ny registrering fra en spiller (55000), også når to fører samtidig.
--     En spiller kan ikke fjerne et resultat.
--   * Arrangøren / eieren fører, retter og fjerner (p_winner null). Et
--     resultat kan endres så lenge kampen etter ikke er avgjort (den finnes da
--     ikke ennå).
-- recorded_by / recorded_at er hvem som førte sist, og når.
-- p_round_id (valgfri) må telle i konkurransen. Gir kampens rad.
create or replace function public.record_cup_result(
  p_competition_id  uuid,
  p_round_no        integer,
  p_slot            integer,
  p_winner          uuid,
  p_walkover        boolean default false,
  p_result          text    default null,
  p_round_id        uuid    default null
)
returns public.competition_matches
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_c       public.competitions;
  v_admin   boolean;
  v_first   integer;
  v_rounds  integer := 0;
  v_a       uuid;
  v_b       uuid;
  v_next    public.competition_matches;
  v_row     public.competition_matches;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select * into v_c from public.competitions where id = p_competition_id;
  if v_c.id is null or not public.can_read_competition(v_c.id) then
    raise exception 'Fant ikke konkurransen' using errcode = 'P0002';
  end if;
  v_admin := public.is_competition_admin(v_c.id);
  if not v_admin and not public.is_competition_participant(v_c.id) then
    raise exception 'Bare spillerne i kampen, arrangøren eller eieren fører resultater' using errcode = '42501';
  end if;
  if v_c.kind <> 'cup' then
    raise exception 'Bare en cup har kamper' using errcode = '22023';
  end if;
  if v_c.status = 'finished' then
    raise exception 'Cupen er ferdig' using errcode = '55000';
  end if;
  if p_result is not null and char_length(p_result) > 40 then
    raise exception 'Resultatet kan ha høyst 40 tegn' using errcode = '22023';
  end if;

  select count(*) into v_first from public.competition_matches where competition_id = v_c.id and round_no = 1;
  if v_first = 0 then
    raise exception 'Cupen er ikke trukket' using errcode = '55000';
  end if;
  while (1 << v_rounds) < v_first * 2 loop
    v_rounds := v_rounds + 1;
  end loop;
  if p_round_no is null or p_slot is null or p_round_no < 1 or p_round_no > v_rounds
     or p_slot < 0 or p_slot >= (v_first * 2) >> p_round_no then
    raise exception 'Kampen finnes ikke i treet' using errcode = '22023';
  end if;

  -- Spillerne i kampen.
  if p_round_no = 1 then
    select player_a, player_b into v_a, v_b from public.competition_matches
    where competition_id = v_c.id and round_no = 1 and slot = p_slot;
    if v_b is null then
      raise exception 'En bye trenger ikke resultat' using errcode = '22023';
    end if;
  else
    select winner into v_a from public.competition_matches
    where competition_id = v_c.id and round_no = p_round_no - 1 and slot = p_slot * 2;
    select winner into v_b from public.competition_matches
    where competition_id = v_c.id and round_no = p_round_no - 1 and slot = p_slot * 2 + 1;
    if v_a is null or v_b is null then
      raise exception 'Kampene før er ikke avgjort' using errcode = '55000';
    end if;
  end if;

  -- En spiller fører bare sin egen kamp, bare én gang, og fjerner ingenting.
  if not v_admin then
    if not exists (select 1 from public.competition_participants p
                   where p.id in (v_a, v_b) and p.competition_id = v_c.id and p.status = 'active'
                     and (p.profile_id = auth.uid() or public.owns_member(p.member_id))) then
      raise exception 'Bare de to i kampen, arrangøren eller eieren fører resultatet' using errcode = '42501';
    end if;
    if p_winner is null then
      raise exception 'Bare arrangøren eller eieren kan fjerne et resultat' using errcode = '42501';
    end if;
    if exists (select 1 from public.competition_matches m
               where m.competition_id = v_c.id and m.round_no = p_round_no and m.slot = p_slot
                 and m.winner is not null) then
      raise exception 'Resultatet er alt ført. Bare arrangøren eller eieren kan endre det.' using errcode = '55000';
    end if;
  end if;

  if p_winner is not null and p_winner is distinct from v_a and p_winner is distinct from v_b then
    raise exception 'Vinneren må være en av de to i kampen' using errcode = '22023';
  end if;
  if p_round_id is not null and not exists (
       select 1 from public.competition_rounds cr where cr.competition_id = v_c.id and cr.round_id = p_round_id) then
    raise exception 'Runden teller ikke i cupen' using errcode = '22023';
  end if;

  -- Kampen etter kan ikke være avgjort.
  if p_round_no < v_rounds then
    select * into v_next from public.competition_matches
    where competition_id = v_c.id and round_no = p_round_no + 1 and slot = p_slot / 2;
    if v_next.winner is not null then
      raise exception 'Kampen etter er avgjort. Fjern det resultatet først.' using errcode = '55000';
    end if;
  end if;

  if p_round_no = 1 then
    update public.competition_matches
       set winner = p_winner,
           walkover = p_winner is not null and coalesce(p_walkover, false),
           result = case when p_winner is not null then nullif(btrim(p_result), '') end,
           round_id = case when p_winner is not null then p_round_id end,
           recorded_by = case when p_winner is not null then auth.uid() end,
           recorded_at = case when p_winner is not null then now() end
     where competition_id = v_c.id and round_no = 1 and slot = p_slot
       -- En spiller skriver bare når kampen ikke er avgjort (første gjelder).
       and (v_admin or winner is null)
    returning * into v_row;
  elsif p_winner is null then
    delete from public.competition_matches
     where competition_id = v_c.id and round_no = p_round_no and slot = p_slot
    returning * into v_row;
  elsif v_admin then
    insert into public.competition_matches (competition_id, round_no, slot, player_a, player_b, winner,
                                            walkover, result, round_id, recorded_by, recorded_at)
    values (v_c.id, p_round_no, p_slot, v_a, v_b, p_winner, coalesce(p_walkover, false),
            nullif(btrim(p_result), ''), p_round_id, auth.uid(), now())
    on conflict (competition_id, round_no, slot) do update
      set player_a = excluded.player_a, player_b = excluded.player_b, winner = excluded.winner,
          walkover = excluded.walkover, result = excluded.result, round_id = excluded.round_id,
          recorded_by = excluded.recorded_by, recorded_at = excluded.recorded_at
    returning * into v_row;
  else
    insert into public.competition_matches (competition_id, round_no, slot, player_a, player_b, winner,
                                            walkover, result, round_id, recorded_by, recorded_at)
    values (v_c.id, p_round_no, p_slot, v_a, v_b, p_winner, coalesce(p_walkover, false),
            nullif(btrim(p_result), ''), p_round_id, auth.uid(), now())
    on conflict (competition_id, round_no, slot) do nothing
    returning * into v_row;
  end if;

  -- To spillere førte samtidig: den andre fikk ingen rad.
  if not v_admin and v_row.id is null then
    raise exception 'Resultatet er alt ført. Bare arrangøren eller eieren kan endre det.' using errcode = '55000';
  end if;

  -- Kamper etter første runde skrives bare med en vinner, så kampen etter
  -- finnes ikke uten at den er avgjort (stoppet over). Treet regnes på nytt
  -- i appen med den nye vinneren.
  return v_row;
end;
$$;
revoke all on function public.record_cup_result(uuid, integer, integer, uuid, boolean, text, uuid) from public, anon;
grant execute on function public.record_cup_result(uuid, integer, integer, uuid, boolean, text, uuid) to authenticated;


-- ===========================================================================
-- 6. INVITASJON TIL EN PRIVAT KONKURRANSE (kode og lenke, som 018)
-- ===========================================================================
-- Besluttet 07.10.2026: private konkurranser (uten klubb) deles med kode eller
-- lenke, dashdash://konkurranse/<KODE>. Samme form og sikkerhet som
-- round_invites (018): 10 tegn Crockford base32 (50 bit) fra
-- round_invite_code(), utløper etter 7 dager, og bare eieren og de påmeldte
-- ser koden. Den som har koden, ser navn, type, eier og antall påmeldte, og
-- kan melde seg på. Klubbens konkurranser deles i klubben (åpen påmelding).
create table if not exists public.competition_invites (
  competition_id  uuid primary key references public.competitions(id) on delete cascade,
  -- Crockford base32 uten I, L, O og U: 10 tegn = 50 bit.
  code            text not null unique check (code ~ '^[0-9A-HJKMNP-TV-Z]{10}$'),
  created_by      uuid references public.profiles(id) on delete set null,
  created_at      timestamptz not null default now(),
  expires_at      timestamptz not null
);
comment on table public.competition_invites is
  'Invitasjonskoden til en privat konkurranse (dashdash://konkurranse/<kode>). Skrives bare av RPC-ene.';

alter table public.competition_invites enable row level security;
drop policy if exists competition_invites_select on public.competition_invites;
-- Eieren og de påmeldte ser koden, så de kan dele den videre.
create policy competition_invites_select on public.competition_invites
  for select to authenticated
  using (public.is_competition_admin(competition_id) or public.is_competition_participant(competition_id));
revoke all on table public.competition_invites from public, anon, authenticated;
grant select on table public.competition_invites to authenticated;


-- --- competition_invite: koden til konkurransen ---------------------------------
-- Bare private liga-, cup- og morroturneringer som ikke er ferdige, og ikke en
-- trukket cup. Returnerer {competition_id, code, expires_at}.
--   * De påmeldte får koden som gjelder, så de kan dele den videre. Finnes
--     ingen gyldig kode, svarer den 55000 (be eieren lage en ny).
--   * Bare eieren lager, fornyer (p_renew = true: ny kode, den gamle slutter
--     å virke) eller trekker tilbake koden (revoke_competition_invite).
--     Sikkerhetsrevisjonen 07.10.2026: en påmeldt skal ikke kunne fornye en
--     kode eieren har trukket tilbake.
-- (Første utkast hadde bare p_competition_id; den gamle signaturen fjernes.)
drop function if exists public.competition_invite(uuid);
create or replace function public.competition_invite(p_competition_id uuid, p_renew boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_c      public.competitions;
  v_admin  boolean;
  v_row    public.competition_invites%rowtype;
  v_try    integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  select * into v_c from public.competitions c where c.id = p_competition_id for update;
  if v_c.id is null or not public.can_read_competition(v_c.id) then
    raise exception 'Fant ikke konkurransen' using errcode = 'P0002';
  end if;
  if v_c.club_id is not null then
    raise exception 'Klubbens konkurranser deles i klubben, ikke med kode' using errcode = '22023';
  end if;
  v_admin := public.is_competition_admin(v_c.id);
  if not (v_admin or public.is_competition_participant(v_c.id)) then
    raise exception 'Fant ikke konkurransen' using errcode = 'P0002';
  end if;
  if coalesce(p_renew, false) and not v_admin then
    raise exception 'Bare eieren kan lage en ny kode' using errcode = '42501';
  end if;
  if v_c.kind not in ('league', 'cup', 'fun') then
    raise exception 'Bare en liga, cup eller morroturnering kan deles med kode' using errcode = '22023';
  end if;
  if v_c.status = 'finished' then
    raise exception 'Konkurransen er ferdig' using errcode = '55000';
  end if;
  if v_c.kind = 'cup' and exists (select 1 from public.competition_matches where competition_id = v_c.id) then
    raise exception 'Cupen er trukket. Ingen nye kan bli med.' using errcode = '55000';
  end if;

  select * into v_row from public.competition_invites i where i.competition_id = v_c.id;
  if found and v_row.expires_at > now() and not coalesce(p_renew, false) then
    return jsonb_build_object('competition_id', v_row.competition_id, 'code', v_row.code, 'expires_at', v_row.expires_at);
  end if;
  if not v_admin then
    raise exception 'Ingen gyldig kode. Be eieren lage en ny.' using errcode = '55000';
  end if;

  perform public.ensure_profile();
  loop
    v_try := v_try + 1;
    begin
      insert into public.competition_invites as i (competition_id, code, created_by, expires_at)
      values (v_c.id, public.round_invite_code(), auth.uid(), now() + interval '7 days')
      on conflict (competition_id) do update
        set code = excluded.code, created_by = excluded.created_by,
            created_at = now(), expires_at = excluded.expires_at
      returning * into v_row;
      exit;
    exception when unique_violation then
      -- To konkurranser fikk samme kode (1 av 2^50): prøv en ny.
      if v_try >= 5 then
        raise;
      end if;
    end;
  end loop;

  return jsonb_build_object('competition_id', v_row.competition_id, 'code', v_row.code, 'expires_at', v_row.expires_at);
end;
$$;
revoke all on function public.competition_invite(uuid, boolean) from public, anon;
grant execute on function public.competition_invite(uuid, boolean) to authenticated;


-- --- revoke_competition_invite: trekk tilbake koden ------------------------------
-- Bare eieren. Koden slettes og slutter å virke med én gang (lenker og QR som
-- er delt). De som alt er påmeldt, er fortsatt med. Gir true når det fantes en
-- kode.
create or replace function public.revoke_competition_invite(p_competition_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_n integer;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if not exists (select 1 from public.competitions c where c.id = p_competition_id)
     or not public.can_read_competition(p_competition_id) then
    raise exception 'Fant ikke konkurransen' using errcode = 'P0002';
  end if;
  if not public.is_competition_admin(p_competition_id) then
    raise exception 'Bare eieren kan trekke tilbake koden' using errcode = '42501';
  end if;
  delete from public.competition_invites i where i.competition_id = p_competition_id;
  get diagnostics v_n = row_count;
  return v_n > 0;
end;
$$;
revoke all on function public.revoke_competition_invite(uuid) from public, anon;
grant execute on function public.revoke_competition_invite(uuid) to authenticated;


-- --- competition_invite_preview: hva du blir med i -------------------------------
-- Alle innloggede som har koden. Gir bare navn, type, eier og antall aktive
-- påmeldte, og om du er påmeldt selv. Ikke hvem de andre er, regelsettet eller
-- rundene. P0002 = ukjent eller utgått kode, 55000 = konkurransen er ferdig.
create or replace function public.competition_invite_preview(p_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_c     public.competitions;
  v_code  text := public.round_invite_normalize(p_code);
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  select c.* into v_c
  from public.competition_invites i
  join public.competitions c on c.id = i.competition_id
  where i.code = v_code and i.expires_at > now() and c.club_id is null;
  if not found then
    raise exception 'Fant ingen konkurranse med den koden. Den kan ha gått ut.' using errcode = 'P0002';
  end if;
  if v_c.status = 'finished' then
    raise exception 'Konkurransen er ferdig' using errcode = '55000';
  end if;

  return jsonb_build_object(
    'competition_id', v_c.id,
    'name',           v_c.name,
    'kind',           v_c.kind,
    'owner_name',     (select p.display_name from public.profiles p where p.id = v_c.owner_id),
    'entrants',       (select count(*) from public.competition_participants cp
                       where cp.competition_id = v_c.id and cp.status = 'active'),
    'entered',        exists (select 1 from public.competition_participants cp
                              where cp.competition_id = v_c.id and cp.status = 'active'
                                and cp.profile_id = auth.uid())
  );
end;
$$;
revoke all on function public.competition_invite_preview(text) from public, anon;
grant execute on function public.competition_invite_preview(text) to authenticated;


-- --- claim_competition_invite: «Bli med» ------------------------------------------
-- Melder profilen din på i én transaksjon. Er du påmeldt: ingenting skjer.
-- Har du meldt deg av: på igjen. En ferdig konkurranse og en trukket cup tar
-- ingen nye (55000). Returnerer {competition_id, participant_id,
-- joined: already | new | rejoined}.
create or replace function public.claim_competition_invite(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me    public.profiles;
  v_c     public.competitions;
  v_code  text := public.round_invite_normalize(p_code);
  v_row   public.competition_participants;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  select c.* into v_c
  from public.competition_invites i
  join public.competitions c on c.id = i.competition_id
  where i.code = v_code and i.expires_at > now() and c.club_id is null;
  if not found then
    raise exception 'Fant ingen konkurranse med den koden. Den kan ha gått ut.' using errcode = 'P0002';
  end if;
  -- Lås konkurransen, så trekningen og påmeldingen ikke krysser hverandre.
  select * into v_c from public.competitions c where c.id = v_c.id for update;

  v_me := public.ensure_profile();
  select * into v_row from public.competition_participants cp
  where cp.competition_id = v_c.id and cp.profile_id = v_me.id;
  if v_row.id is not null and v_row.status = 'active' then
    return jsonb_build_object('competition_id', v_c.id, 'participant_id', v_row.id, 'joined', 'already');
  end if;

  if v_c.status = 'finished' then
    raise exception 'Konkurransen er ferdig' using errcode = '55000';
  end if;
  if v_c.kind = 'cup' and exists (select 1 from public.competition_matches where competition_id = v_c.id) then
    raise exception 'Cupen er trukket. Spør eieren.' using errcode = '55000';
  end if;

  if v_row.id is not null then
    update public.competition_participants set status = 'active' where id = v_row.id returning * into v_row;
    return jsonb_build_object('competition_id', v_c.id, 'participant_id', v_row.id, 'joined', 'rejoined');
  end if;

  insert into public.competition_participants (competition_id, profile_id)
  values (v_c.id, v_me.id) returning * into v_row;
  return jsonb_build_object('competition_id', v_c.id, 'participant_id', v_row.id, 'joined', 'new');
end;
$$;
revoke all on function public.claim_competition_invite(text) from public, anon;
grant execute on function public.claim_competition_invite(text) to authenticated;


-- ===========================================================================
-- 7. REALTIME (cupkampene; invitasjonskodene sendes ikke rundt)
-- ===========================================================================
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'Publikasjonen supabase_realtime finnes ikke – hopper over realtime';
    return;
  end if;
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'competition_matches') then
    alter publication supabase_realtime add table public.competition_matches;
  end if;
end $$;

commit;


-- ===========================================================================
-- KONTROLL (kjør i SQL Editor etter fila, som én kjøring). Én rad per sjekk,
-- alle skal ha ok = true.
-- ===========================================================================
-- with f as (
--   select p.proname,
--          has_function_privilege('anon', p.oid, 'execute') as anon_kan,
--          has_function_privilege('authenticated', p.oid, 'execute') as auth_kan
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public'
--     and p.proname in ('competition_round_entrants', 'create_competition_with_entrants', 'join_competition',
--                       'leave_competition', 'set_round_competitions', 'draw_cup', 'record_cup_result',
--                       'competition_invite', 'competition_invite_preview', 'claim_competition_invite',
--                       'revoke_competition_invite')
-- )
-- select 1 as nr, 'competitions.signup_open finnes (av som standard)' as sjekk,
--        exists (select 1 from information_schema.columns
--                where table_schema = 'public' and table_name = 'competitions' and column_name = 'signup_open'
--                  and column_default = 'false' and is_nullable = 'NO') as ok
-- union all
-- select 2, 'Ingen åpen påmelding uten påmeldte (entry = listed)',
--        not exists (select 1 from public.competitions where signup_open and entry <> 'listed')
-- union all
-- select 3, 'competition_matches finnes med RLS og én policy (lese)',
--        (select c.relrowsecurity from pg_class c where c.oid = 'public.competition_matches'::regclass)
--        and (select count(*) = 1 from pg_policies where schemaname = 'public' and tablename = 'competition_matches'
--               and cmd = 'SELECT' and qual like '%can_read_competition%')
-- union all
-- select 4, 'authenticated: bare SELECT på competition_matches, anon ingenting',
--        (select string_agg(privilege_type, ',' order by privilege_type) = 'SELECT'
--         from information_schema.role_table_grants
--         where table_schema = 'public' and table_name = 'competition_matches' and grantee = 'authenticated')
--        and not exists (select 1 from information_schema.role_table_grants
--                        where table_schema = 'public' and table_name = 'competition_matches'
--                          and grantee in ('anon', 'PUBLIC'))
-- union all
-- select 5, 'Alle elleve funksjonene finnes (competition_invite bare med (uuid, boolean))', (select count(*) = 11 from f)
-- union all
-- select 6, 'anon kan ikke kjøre noen av dem', not exists (select 1 from f where anon_kan)
-- union all
-- select 7, 'authenticated kan kjøre de ti RPC-ene, ikke den indre hjelperen',
--        (select bool_and(auth_kan = (proname <> 'competition_round_entrants')) from f)
-- union all
-- select 8, 'Kampene peker på påmeldte i samme konkurranse',
--        not exists (select 1 from public.competition_matches m
--                    left join public.competition_participants a on a.id = m.player_a
--                    left join public.competition_participants b on b.id = m.player_b
--                    where (m.player_a is not null and a.competition_id <> m.competition_id)
--                       or (m.player_b is not null and b.competition_id <> m.competition_id))
-- union all
-- select 9, 'Vinneren er alltid en av de to', not exists (select 1 from public.competition_matches
--        where winner is not null and winner is distinct from player_a and winner is distinct from player_b)
-- union all
-- select 10, 'Bare cuper har kamper', not exists (select 1 from public.competition_matches m
--        join public.competitions c on c.id = m.competition_id where c.kind <> 'cup')
-- union all
-- select 11, 'Realtime for competition_matches, ikke for competition_invites',
--        exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime'
--                  and schemaname = 'public' and tablename = 'competition_matches')
--        and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime'
--                          and schemaname = 'public' and tablename = 'competition_invites')
-- union all
-- select 12, 'Policyene på competitions/participants/rounds fra 017 er urørt (4 + 4 + 3)',
--        (select count(*) = 11 from pg_policies where schemaname = 'public'
--           and tablename in ('competitions', 'competition_participants', 'competition_rounds'))
-- union all
-- select 13, 'competition_matches logger hvem som førte (recorded_by, recorded_at)',
--        (select count(*) = 2 from information_schema.columns where table_schema = 'public'
--           and table_name = 'competition_matches' and column_name in ('recorded_by', 'recorded_at'))
-- union all
-- select 14, 'competition_invites: RLS, én policy (lese), authenticated bare SELECT, anon ingenting',
--        (select c.relrowsecurity from pg_class c where c.oid = 'public.competition_invites'::regclass)
--        and (select count(*) = 1 from pg_policies where schemaname = 'public' and tablename = 'competition_invites'
--               and cmd = 'SELECT')
--        and (select string_agg(privilege_type, ',' order by privilege_type) = 'SELECT'
--             from information_schema.role_table_grants
--             where table_schema = 'public' and table_name = 'competition_invites' and grantee = 'authenticated')
--        and not exists (select 1 from information_schema.role_table_grants
--                        where table_schema = 'public' and table_name = 'competition_invites'
--                          and grantee in ('anon', 'PUBLIC'))
-- union all
-- select 15, 'Koder bare for private konkurranser, med riktig form',
--        not exists (select 1 from public.competition_invites i join public.competitions c on c.id = i.competition_id
--                    where c.club_id is not null or i.code !~ '^[0-9A-HJKMNP-TV-Z]{10}$')
-- order by nr;
--
-- Rolleprøven sql/lokal/022_prove.sql er KUN for lokal Postgres.


-- ===========================================================================
-- RULLEBAKKE (bare test). Fjerner invitasjonene, cupkampene og åpen
-- påmelding. Slå av CompetitionsFeature i appen først (den er av fra start).
-- ===========================================================================
-- begin;
-- drop function if exists public.claim_competition_invite(text);
-- drop function if exists public.competition_invite_preview(text);
-- drop function if exists public.revoke_competition_invite(uuid);
-- drop function if exists public.competition_invite(uuid, boolean);
-- drop table if exists public.competition_invites;
-- drop function if exists public.record_cup_result(uuid, integer, integer, uuid, boolean, text, uuid);
-- drop function if exists public.draw_cup(uuid, jsonb);
-- drop function if exists public.set_round_competitions(uuid, uuid[]);
-- drop function if exists public.leave_competition(uuid);
-- drop function if exists public.join_competition(uuid);
-- drop function if exists public.create_competition_with_entrants(text, text, uuid, text, jsonb, date, date, boolean, uuid[], uuid[]);
-- drop function if exists public.competition_round_entrants(uuid, uuid);
-- drop table if exists public.competition_matches;
-- drop index if exists public.competition_participants_id_competition;
-- alter table public.competitions drop constraint if exists competitions_signup_listed;
-- alter table public.competitions drop column if exists signup_open;
-- commit;
