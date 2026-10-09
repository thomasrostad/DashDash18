-- ===========================================================================
-- 032 – TURNERINGEN SOM KJERNE, TRINN 2 (FASE 23) – FORSLAG, IKKE KJØRT
-- ===========================================================================
-- Status: FORSLAG til godkjenning (ROADMAP B5). IKKE KJØRT mot Supabase,
-- verken test eller prod. Prøvd lokalt (sql/lokal/032_for.sql og
-- sql/lokal/032_prove.sql, 032 to ganger på rad). Krever 001–031.
--
-- Hvorfor (docs/fase-22-turnering-som-kjerne.md, kap. 7 og 10, og
-- «Besluttet 09.10.2026»): staben i en turnering skal få rettighetene sine,
-- påmeldingen skal ha tak, vindu og venteliste med tilbud, åpne turneringer
-- skal kunne finnes av alle innloggede, og startlista skal kunne lagres i én
-- transaksjon.
--
-- Beslutningene fila bygger på (Thomas 08.–09.10.2026):
--   * åpen påmelding for ikke-medlemmer velges per turnering (signup_audience);
--   * åpne turneringer: alle innloggede ser turneringen, bare deltakerne ser
--     runder og hull;
--   * et tilbud om ledig plass gjelder i 24 timer, så går det videre;
--   * funksjonærer (scorer) fører bare for gruppene de er satt på, arrangøren
--     (organizer) for alle;
--   * Golfgutu skal ikke merke noe.
--
-- Hva fila gjør:
--   1. app_config: waitlist_offer_hours = 24 (fristen for et tilbud kan
--      endres uten ny migrering).
--   2. round_start_groups.scorer_id: funksjonæren som fører for gruppa.
--   3. Mengdebaserte hjelpere (lasttesten, kap. 9): my_member_ids,
--      my_entered_competition_ids, my_staff_competition_ids,
--      my_competition_event_ids. Brukes i policyene som `= any ((select …))`,
--      så de regnes én gang per spørring, ikke per rad.
--   4. Hjelperne fra 017 får nye grener (samme signatur, samme svar for alle
--      som ikke er i en stab eller påmeldt i en turnering med spilledager):
--        is_competition_participant  – samme svar, skrevet som mengde;
--        is_competition_admin        – + staben med rollen organizer;
--        can_read_competition        – + staben (begge roller);
--        is_round_organizer          – + organizer i turneringen som eier
--                                      spilledagen (events.competition_id);
--        can_read_round              – + staben, og påmeldte i turneringen
--                                      som eier spilledagen (ikke kladder);
--        can_score                   – + organizer for alle, og scorer for
--                                      spillerne i gruppene hen er satt på.
--      Den åpne grenen (listed + anyone) legges IKKE i can_read_competition,
--      fordi den hjelperen også åpner rundene (round_in_readable_competition).
--      Åpne turneringer leses i stedet med RPC-en public_competitions.
--   5. Tre nye policyer ved siden av de gamle (ingen gammel policy endres):
--      competitions_select_staff, events_select_competition og
--      rounds_select_competition. De gamle har uttrykket inline og kaller
--      ikke hjelperne over.
--   6. RPC-er (security definer, én transaksjon, `for update` på turneringen
--      der to kan ta siste plass):
--        competition_signup          – meld meg på (tak, vindu, venteliste);
--        competition_withdraw        – meld meg av (eller ut av ventelista);
--        competition_offer_respond   – ta imot eller avslå tilbudet;
--        competition_signup_status   – min status for flere turneringer i
--                                      ett kall (mengde);
--        competition_waitlist_entries – ventelista med navn (arrangøren);
--        set_competition_signup      – arrangørens innstillinger;
--        public_competitions         – åpne turneringer (listed + anyone)
--                                      for alle innloggede: navn, tid, sted,
--                                      plasser. Ikke runder, ikke tropp;
--        save_start_list             – startlista for en runde (pulje,
--                                      grupper med tid, starthull, bås og
--                                      funksjonær);
--        expire_competition_offers   – bare service_role/cron: utløpte tilbud
--                                      går videre, ledige plasser tilbys.
--   7. guard_competition_staff (031) får et tak: høyst 50 i staben.
--
-- Hvorfor dagens app ikke merker noe:
--   * Ingen policy fra 001–031 endres eller fjernes. De tre nye policyene gir
--     bare rader til den som er i en stab eller påmeldt i en turnering med
--     spilledager; i dag er staben tom, og ingen klubbturnering har
--     påmeldte med spilledager (kontroll og per-innlogging-bilde i prøven).
--   * Hjelperne gir samme svar for hver innlogging og hver Golfgutu-runde og
--     -turnering (lokal/032_prove.sql del A: samme bilde og Tavla som før 032
--     for fem innlogginger, metoden fra 017/9 og 031).
--   * join_competition og leave_competition (022) står urørt. Dagens app
--     bruker dem; den nye appen bruker de nye RPC-ene bak flagg.
--   * Ingen ny verdi i kolonner appen dekoder strengt (status, kind, entry,
--     source). Ingen ny aktivitetstype (push for tilbud kommer i trinn 4).
--   * De gamle unike reglene står (kontroll 3).
--
-- Hva fila IKKE gjør (trinn 3–5):
--   * snur ikke speilingen sesong → turnering, og kobler ikke runder til
--     andre turneringer enn sesongen via events.competition_id;
--   * fjerner ingen gamle unike regler (034, tidligst når hele gjengen har et
--     fase 23-bygg, min_ios_build);
--   * lar ikke ikke-medlemmer spille klubbrunder (round_players.member_id er
--     fortsatt troppen);
--   * ingen push eller aktivitet for venteliste-tilbud (trinn 4);
--   * tabellen for ikke-deltakere i åpne turneringer krever rådata fra
--     serveren (tavla_data, fase 24).
--
-- Kjøring av utløpte tilbud: alle RPC-ene rydder selv før de regner ledige
-- plasser, så ingen kan ta en plass som er lovet bort. For at tilbudet skal gå
-- videre selv når ingen gjør noe, foreslås pg_cron hvert 10. minutt (IKKE satt
-- opp her, se «Etter migreringen» nederst).
--
-- Mønsteret fra 001–031 følges: én transaksjon, idempotent, `set search_path
-- = ''`, `revoke … from public, anon` ETTER hver create or replace, interne
-- funksjoner tas fra authenticated også, kontroll og rullebakke nederst.
-- ===========================================================================

begin;


-- ===========================================================================
-- 1. APP_CONFIG: fristen for et tilbud fra ventelista
-- ===========================================================================
insert into public.app_config (key, value)
values ('waitlist_offer_hours', '{"hours": 24}'::jsonb)
on conflict (key) do nothing;

-- Timer et tilbud gjelder: app_config, mellom 1 og 168, ellers 24.
create or replace function public.waitlist_offer_hours()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select least(greatest((c.value ->> 'hours')::integer, 1), 168)
       from public.app_config c
      where c.key = 'waitlist_offer_hours'
        and jsonb_typeof(c.value -> 'hours') = 'number'),
    24);
$$;
revoke all on function public.waitlist_offer_hours() from public, anon;
grant execute on function public.waitlist_offer_hours() to authenticated;


-- ===========================================================================
-- 2. ROUND_START_GROUPS.SCORER_ID: funksjonæren for gruppa
-- ===========================================================================
alter table public.round_start_groups
  add column if not exists scorer_id uuid references public.profiles(id) on delete set null;
comment on column public.round_start_groups.scorer_id is
  'Funksjonæren (competition_staff) som fører for gruppa. Tom = markøren og spillerne som før. '
  'Settes med save_start_list, som krever at personen er i staben til turneringen.';
create index if not exists round_start_groups_scorer_idx
  on public.round_start_groups (scorer_id) where scorer_id is not null;


-- ===========================================================================
-- 3. MENGDEBASERTE HJELPERE
-- ===========================================================================
-- Medlemskapene mine (aktive), slått opp én gang.
create or replace function public.my_member_ids()
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(m.id), '{}')
    from public.club_members m
   where m.user_id = auth.uid() and m.status = 'active';
$$;
revoke all on function public.my_member_ids() from public, anon;
grant execute on function public.my_member_ids() to authenticated;

-- Turneringene jeg er påmeldt i (aktiv), som profil eller som medlem.
create or replace function public.my_entered_competition_ids()
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(distinct p.competition_id), '{}')
    from public.competition_participants p
   where p.status = 'active'
     and (p.profile_id = auth.uid() or p.member_id = any (public.my_member_ids()));
$$;
revoke all on function public.my_entered_competition_ids() from public, anon;
grant execute on function public.my_entered_competition_ids() to authenticated;

-- Turneringene jeg er i staben til (valgfritt: med denne rollen).
create or replace function public.my_staff_competition_ids(p_role text default null)
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(s.competition_id), '{}')
    from public.competition_staff s
   where s.profile_id = auth.uid() and (p_role is null or s.role = p_role);
$$;
revoke all on function public.my_staff_competition_ids(text) from public, anon;
grant execute on function public.my_staff_competition_ids(text) to authenticated;

-- Spilledagene i turneringer der jeg er i staben eller påmeldt.
-- p_organizer_only: bare der jeg er arrangør (for kladder).
create or replace function public.my_competition_event_ids(p_organizer_only boolean default false)
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(e.id), '{}')
    from public.events e
   where e.competition_id is not null
     and (   e.competition_id = any (public.my_staff_competition_ids(case when p_organizer_only then 'organizer' end))
          or (not p_organizer_only and e.competition_id = any (public.my_entered_competition_ids())));
$$;
revoke all on function public.my_competition_event_ids(boolean) from public, anon;
grant execute on function public.my_competition_event_ids(boolean) to authenticated;

-- Er jeg i staben til turneringen som eier rundens spilledag?
create or replace function public.is_round_staff(p_round_id uuid, p_role text default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.rounds r
      join public.events e on e.id = r.event_id
      join public.competition_staff s on s.competition_id = e.competition_id
     where r.id = p_round_id
       and s.profile_id = auth.uid()
       and (p_role is null or s.role = p_role));
$$;
revoke all on function public.is_round_staff(uuid, text) from public, anon;
grant execute on function public.is_round_staff(uuid, text) to authenticated;

-- Er jeg funksjonær for gruppa (bås/flight) i runden? Krever at jeg fortsatt
-- er i staben, så en som tas ut av staben mister retten med en gang.
create or replace function public.is_group_scorer(p_round_id uuid, p_group_no smallint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_group_no is not null
     and exists (select 1 from public.round_start_groups g
                  where g.round_id = p_round_id and g.group_no = p_group_no and g.scorer_id = auth.uid())
     and public.is_round_staff(p_round_id);
$$;
revoke all on function public.is_group_scorer(uuid, smallint) from public, anon;
grant execute on function public.is_group_scorer(uuid, smallint) to authenticated;


-- ===========================================================================
-- 4. HJELPERNE FRA 017 FÅR NYE GRENER (samme signatur og rettigheter)
-- ===========================================================================
-- Deltar jeg i konkurransen? Samme svar som 017, men medlemskapene slås opp
-- én gang (lasttesten: 18,7 → 4,0 ms for turneringslista).
create or replace function public.is_competition_participant(p_competition_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.competition_participants p
    where p.competition_id = p_competition_id
      and p.status = 'active'
      and (p.profile_id = auth.uid() or p.member_id = any (public.my_member_ids()))
  );
$$;
revoke all on function public.is_competition_participant(uuid) from public, anon;
grant execute on function public.is_competition_participant(uuid) to authenticated;

-- Styrer jeg konkurransen? Klubbens: arrangør. Profilens: eieren.
-- 032: + staben med rollen organizer.
create or replace function public.is_competition_admin(p_competition_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.competitions c
    where c.id = p_competition_id
      and (   (c.club_id is not null and public.is_club_organizer(c.club_id))
           or (c.club_id is null and c.owner_id = auth.uid())
           or exists (select 1 from public.competition_staff s
                       where s.competition_id = c.id and s.profile_id = auth.uid()
                         and s.role = 'organizer'))
  );
$$;
revoke all on function public.is_competition_admin(uuid) from public, anon;
grant execute on function public.is_competition_admin(uuid) to authenticated;

-- Kan jeg se konkurransen? Klubbens: medlemmer. Profilens: eieren. Alle: de
-- som deltar. 032: + staben. (Ikke listed + anyone: se kommentaren øverst.)
create or replace function public.can_read_competition(p_competition_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.competitions c
    where c.id = p_competition_id
      and (   (c.club_id is not null and public.is_club_member(c.club_id))
           or (c.club_id is null and c.owner_id = auth.uid())
           or public.is_competition_participant(c.id)
           or exists (select 1 from public.competition_staff s
                       where s.competition_id = c.id and s.profile_id = auth.uid()))
  );
$$;
revoke all on function public.can_read_competition(uuid) from public, anon;
grant execute on function public.can_read_competition(uuid) to authenticated;

-- Styrer jeg runden? Klubb: arrangøren. Løs: eieren.
-- 032: + arrangør i staben til turneringen som eier spilledagen.
create or replace function public.is_round_organizer(p_round_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.rounds r
    where r.id = p_round_id
      and (   public.is_club_organizer(r.club_id)
           or (r.club_id is null and r.owner_id = auth.uid())
           or (r.event_id is not null and public.is_round_staff(r.id, 'organizer')))
  );
$$;
revoke all on function public.is_round_organizer(uuid) from public, anon;
grant execute on function public.is_round_organizer(uuid) to authenticated;

-- Kan jeg se runden? Som 017, pluss (032) for runder på en spilledag i en
-- turnering: arrangøren i staben (også kladd), og funksjonærer og påmeldte
-- (ikke kladd). Påmeldte uten medlemskap ser da rundene i turneringen sin
-- (beslutning 3), andre ikke-medlemmer gjør det ikke.
create or replace function public.can_read_round(p_round_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.rounds r
    where r.id = p_round_id
      and (   (r.status <> 'draft' and public.is_club_member(r.club_id))
           or public.is_club_organizer(r.club_id)
           or (r.club_id is null
               and (r.owner_id = auth.uid() or public.is_round_participant(r.id)))
           or (r.status <> 'draft' and public.round_in_readable_competition(r.id))
           or (r.event_id is not null
               and exists (select 1 from public.events e
                            where e.id = r.event_id and e.competition_id is not null
                              and (   exists (select 1 from public.competition_staff s
                                               where s.competition_id = e.competition_id
                                                 and s.profile_id = auth.uid()
                                                 and (s.role = 'organizer' or r.status <> 'draft'))
                                   or (r.status <> 'draft'
                                       and public.is_competition_participant(e.competition_id))))))
  );
$$;
revoke all on function public.can_read_round(uuid) from public, anon;
grant execute on function public.can_read_round(uuid) to authenticated;

-- kanFore, som i 017. 032: arrangøren i staben fører for alle (som klubbens
-- arrangør), og en funksjonær fører for spillerne i gruppene hen er satt på
-- (round_start_groups.scorer_id) mens runden pågår.
create or replace function public.can_score(p_round_id uuid, p_member_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_found   boolean;
  v_club    uuid;
  v_status  text;
  v_owner   uuid;
  v_bay     smallint;
  v_marker  uuid;
begin
  if auth.uid() is null then
    return false;
  end if;

  select true, r.club_id, r.status, r.owner_id into v_found, v_club, v_status, v_owner
  from public.rounds r where r.id = p_round_id;
  if v_found is null then
    return false;
  end if;

  if v_club is not null then
    if public.is_club_organizer(v_club) then
      return true;
    end if;
  elsif v_owner = auth.uid() then
    return true;
  end if;

  -- 032: arrangøren i staben har arrangørens rett.
  if public.is_round_staff(p_round_id, 'organizer') then
    return true;
  end if;

  if v_status <> 'active' then
    return false;
  end if;

  select rp.bay_no into v_bay
  from public.round_players rp
  where rp.round_id = p_round_id and rp.member_id = p_member_id;

  if v_bay is not null then
    select rp.member_id into v_marker
    from public.round_players rp
    where rp.round_id = p_round_id and rp.bay_no = v_bay and rp.is_marker;
  end if;

  if v_marker is not null then
    return public.owns_round_player(p_round_id, v_marker)
        or public.is_group_scorer(p_round_id, v_bay);
  end if;

  return public.owns_round_player(p_round_id, p_member_id)
      or public.is_group_scorer(p_round_id, v_bay);
end;
$$;
revoke all on function public.can_score(uuid, uuid) from public, anon;
grant execute on function public.can_score(uuid, uuid) to authenticated;


-- ===========================================================================
-- 5. NYE POLICYER VED SIDEN AV DE GAMLE
-- ===========================================================================
-- De gamle policyene på competitions, events og rounds har uttrykket inline
-- (så en ny rad kan leses tilbake i samme forespørsel) og røres ikke. Flere
-- permissive policyer gjelder med «eller». Mengdene regnes én gang per
-- spørring (initplan), så de koster ikke per rad.
drop policy if exists competitions_select_staff on public.competitions;
create policy competitions_select_staff on public.competitions
  for select to authenticated
  using (id = any ((select public.my_staff_competition_ids())::uuid[]));

drop policy if exists events_select_competition on public.events;
create policy events_select_competition on public.events
  for select to authenticated
  using (competition_id = any ((select public.my_staff_competition_ids())::uuid[])
         or competition_id = any ((select public.my_entered_competition_ids())::uuid[]));

drop policy if exists rounds_select_competition on public.rounds;
create policy rounds_select_competition on public.rounds
  for select to authenticated
  using (event_id = any ((select public.my_competition_event_ids(true))::uuid[])
         or (status <> 'draft' and event_id = any ((select public.my_competition_event_ids(false))::uuid[])));


-- ===========================================================================
-- 6. STABEN: tak på 50 per turnering (031-vakta, ellers uendret)
-- ===========================================================================
create or replace function public.guard_competition_staff()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE'
     and (new.competition_id is distinct from old.competition_id
          or new.profile_id is distinct from old.profile_id) then
    raise exception 'Bare rollen kan endres' using errcode = '42501';
  end if;
  if tg_op = 'INSERT'
     and (select count(*) from public.competition_staff s where s.competition_id = new.competition_id) >= 50 then
    raise exception 'Grensen er nådd: høyst 50 i staben' using errcode = '54000';
  end if;
  if auth.uid() is null then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.added_by := auth.uid();
    if not public.can_see_profile(new.profile_id) then
      raise exception 'Du kan bare legge til folk du kjenner fra en klubb, runde eller turnering'
        using errcode = '42501';
    end if;
  elsif new.added_by is distinct from old.added_by
        and not (new.added_by is null
                 and not exists (select 1 from public.profiles p where p.id = old.added_by)) then
    raise exception 'Hvem som la til, endres ikke' using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_competition_staff() from public, anon, authenticated;


-- ===========================================================================
-- 7. PÅMELDING, VENTELISTE OG TILBUD
-- ===========================================================================
-- Intern: rydder utløpte tilbud og tilbyr ledige plasser til de neste i køen.
-- Ledige plasser = taket − aktive påmeldte − tilbud som står ute. Uten tak
-- får alle i køen tilbud. Kalles med turneringen låst (for update). Gir
-- antall nye tilbud.
create or replace function public.competition_fill(p_competition_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_c       public.competitions;
  v_active  integer;
  v_offers  integer;
  v_free    integer;
  v_n       integer;
begin
  select * into v_c from public.competitions where id = p_competition_id for update;
  if v_c.id is null then
    return 0;
  end if;
  delete from public.competition_waitlist w
   where w.competition_id = v_c.id and w.offer_expires_at <= now();
  if v_c.status = 'finished' then
    return 0;
  end if;
  select count(*) into v_active from public.competition_participants p
   where p.competition_id = v_c.id and p.status = 'active';
  select count(*) into v_offers from public.competition_waitlist w
   where w.competition_id = v_c.id and w.offered_at is not null;
  v_free := case when v_c.max_entrants is null then 5000
                 else v_c.max_entrants - v_active - v_offers end;
  if v_free <= 0 then
    return 0;
  end if;
  update public.competition_waitlist w
     set offered_at = now(),
         offer_expires_at = now() + make_interval(hours => public.waitlist_offer_hours())
   where w.id in (select w2.id from public.competition_waitlist w2
                   where w2.competition_id = v_c.id and w2.offered_at is null
                   order by w2.created_at, w2.id
                   limit v_free);
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke all on function public.competition_fill(uuid) from public, anon, authenticated;

-- Min status i flere turneringer i ett kall (mengde). Bare turneringer jeg
-- kan se, som er åpne for alle, eller der jeg står på ventelista.
--   state: entered | offered | expired | waitlisted | withdrawn | none
--   waitlist_position: plassen min i køen (1 = først), også med tilbud.
create or replace function public.competition_signup_status(p_competition_ids uuid[])
returns table (
  competition_id     uuid,
  state              text,
  waitlist_position  integer,
  offer_expires_at   timestamptz,
  entrants           integer,
  max_entrants       integer,
  waitlist           integer,
  signup_open        boolean,
  signup_audience    text,
  waitlist_enabled   boolean,
  signup_opens_at    timestamptz,
  signup_closes_at   timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  with me as (
    select auth.uid() as uid, public.my_member_ids() as members
  ), c as (
    select c.* from public.competitions c, me
     where c.id = any (coalesce(p_competition_ids, '{}')) and me.uid is not null
  )
  select c.id,
         case
           when exists (select 1 from public.competition_participants p, me
                         where p.competition_id = c.id and p.status = 'active'
                           and (p.profile_id = me.uid or p.member_id = any (me.members))) then 'entered'
           when w.id is not null and w.offered_at is not null and w.offer_expires_at > now() then 'offered'
           when w.id is not null and w.offered_at is not null then 'expired'
           when w.id is not null then 'waitlisted'
           when exists (select 1 from public.competition_participants p, me
                         where p.competition_id = c.id and p.status = 'withdrawn'
                           and (p.profile_id = me.uid or p.member_id = any (me.members))) then 'withdrawn'
           else 'none'
         end,
         case when w.id is null then null
              else (select count(*)::integer from public.competition_waitlist w2
                     where w2.competition_id = c.id
                       and (w2.created_at, w2.id) <= (w.created_at, w.id)) end,
         case when w.offered_at is not null then w.offer_expires_at end,
         (select count(*)::integer from public.competition_participants p
           where p.competition_id = c.id and p.status = 'active'),
         c.max_entrants,
         (select count(*)::integer from public.competition_waitlist w3 where w3.competition_id = c.id),
         c.signup_open,
         c.signup_audience,
         c.waitlist_enabled,
         c.signup_opens_at,
         c.signup_closes_at
    from c
    cross join me
    left join public.competition_waitlist w on w.competition_id = c.id and w.profile_id = me.uid
   where public.can_read_competition(c.id) or c.signup_audience = 'anyone' or w.id is not null;
$$;
revoke all on function public.competition_signup_status(uuid[]) from public, anon;
grant execute on function public.competition_signup_status(uuid[]) to authenticated;

-- Intern: statusen for én turnering som json (svaret fra RPC-ene under).
create or replace function public.competition_signup_json(p_competition_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select to_jsonb(s) from public.competition_signup_status(array[p_competition_id]) s),
                  jsonb_build_object('competition_id', p_competition_id, 'state', 'none'));
$$;
revoke all on function public.competition_signup_json(uuid) from public, anon, authenticated;

-- «Meld meg på». Med plass: påmeldt (klubbmedlem som medlemmet, ellers som
-- profil). Full og venteliste på: på ventelista. Full uten venteliste:
-- avvist. Idempotent: er du påmeldt eller i køen, får du statusen.
create or replace function public.competition_signup(p_competition_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_c       public.competitions;
  v_member  uuid;
  v_row     public.competition_participants;
  v_me      public.profiles;
  v_active  integer;
  v_offers  integer;
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select * into v_c from public.competitions where id = p_competition_id for update;
  if v_c.id is null
     or not (public.can_read_competition(v_c.id) or v_c.signup_audience = 'anyone'
             or exists (select 1 from public.competition_waitlist w
                         where w.competition_id = v_c.id and w.profile_id = v_uid)) then
    raise exception 'Fant ikke turneringen' using errcode = 'P0002';
  end if;

  if v_c.club_id is not null then
    select m.id into v_member from public.club_members m
     where m.club_id = v_c.club_id and m.user_id = v_uid and m.status = 'active'
     order by m.id limit 1;
  end if;
  select * into v_row from public.competition_participants p
   where p.competition_id = v_c.id
     and (p.profile_id = v_uid or (v_member is not null and p.member_id = v_member))
   order by (p.status = 'active') desc, p.created_at
   limit 1;
  if v_row.status = 'active'
     or exists (select 1 from public.competition_waitlist w
                 where w.competition_id = v_c.id and w.profile_id = v_uid) then
    return public.competition_signup_json(v_c.id);
  end if;

  if v_c.entry = 'club' then
    raise exception 'Hele troppen er med i denne turneringen' using errcode = '55000';
  end if;
  if v_c.status = 'finished' then
    raise exception 'Turneringen er ferdig' using errcode = '55000';
  end if;
  if not v_c.signup_open then
    raise exception 'Påmeldingen er ikke åpen' using errcode = '55000';
  end if;
  if v_c.signup_opens_at is not null and now() < v_c.signup_opens_at then
    raise exception 'Påmeldingen åpner %',
      to_char(v_c.signup_opens_at at time zone 'Europe/Oslo', 'DD.MM.YYYY "kl." HH24:MI')
      using errcode = '55000';
  end if;
  if v_c.signup_closes_at is not null and now() > v_c.signup_closes_at then
    raise exception 'Påmeldingen er stengt' using errcode = '55000';
  end if;
  if v_c.kind = 'cup' and exists (select 1 from public.competition_matches m where m.competition_id = v_c.id) then
    raise exception 'Cupen er trukket. Spør arrangøren.' using errcode = '55000';
  end if;
  if v_c.signup_audience = 'members' and v_c.club_id is not null and v_member is null then
    raise exception 'Du må være medlem i klubben' using errcode = '42501';
  end if;
  -- Som 025: en blokkering mellom deg og eieren av en privat turnering.
  if v_c.club_id is null and v_c.owner_id is not null and public.blocked_between(v_c.owner_id) then
    raise exception 'Du kan ikke bli med i denne turneringen' using errcode = 'DDB01';
  end if;

  perform public.competition_fill(v_c.id);
  select count(*) into v_active from public.competition_participants p
   where p.competition_id = v_c.id and p.status = 'active';
  select count(*) into v_offers from public.competition_waitlist w
   where w.competition_id = v_c.id and w.offered_at is not null;

  if v_c.max_entrants is null or v_active + v_offers < v_c.max_entrants then
    if v_row.id is not null then
      update public.competition_participants set status = 'active' where id = v_row.id;
    elsif v_member is not null then
      insert into public.competition_participants (competition_id, member_id) values (v_c.id, v_member);
    else
      v_me := public.ensure_profile();
      insert into public.competition_participants (competition_id, profile_id) values (v_c.id, v_me.id);
    end if;
  elsif v_c.waitlist_enabled then
    if (select count(*) from public.competition_waitlist w where w.competition_id = v_c.id) >= 1000 then
      raise exception 'Grensen er nådd: høyst 1000 på ventelista' using errcode = '54000';
    end if;
    v_me := public.ensure_profile();
    insert into public.competition_waitlist (competition_id, profile_id, member_id)
    values (v_c.id, v_me.id, v_member);
  else
    raise exception 'Turneringen er full' using errcode = '55000';
  end if;

  return public.competition_signup_json(v_c.id);
end;
$$;
revoke all on function public.competition_signup(uuid) from public, anon;
grant execute on function public.competition_signup(uuid) to authenticated;

-- «Meld meg av»: ut av ventelista, eller påmeldingen settes til withdrawn
-- (raden står, som leave_competition i 022). En ledig plass tilbys den neste
-- i køen med en gang.
create or replace function public.competition_withdraw(p_competition_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := auth.uid();
  v_id   uuid;
  v_n    integer;
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select c.id into v_id from public.competitions c where c.id = p_competition_id for update;
  if v_id is null then
    raise exception 'Fant ikke turneringen' using errcode = 'P0002';
  end if;
  delete from public.competition_waitlist w where w.competition_id = v_id and w.profile_id = v_uid;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    update public.competition_participants p
       set status = 'withdrawn'
     where p.competition_id = v_id and p.status = 'active'
       and (p.profile_id = v_uid or p.member_id = any (public.my_member_ids()));
  end if;
  perform public.competition_fill(v_id);
  return public.competition_signup_json(v_id);
end;
$$;
revoke all on function public.competition_withdraw(uuid) from public, anon;
grant execute on function public.competition_withdraw(uuid) to authenticated;

-- Svar på tilbudet: ta imot (påmeldt, plassen var holdt av) eller avslå (ut
-- av køen, plassen går videre). Et utløpt tilbud kan ikke tas.
create or replace function public.competition_offer_respond(p_competition_id uuid, p_accept boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := auth.uid();
  v_c    public.competitions;
  v_w    public.competition_waitlist;
  v_row  public.competition_participants;
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select * into v_c from public.competitions where id = p_competition_id for update;
  if v_c.id is null then
    raise exception 'Fant ikke turneringen' using errcode = 'P0002';
  end if;
  perform public.competition_fill(v_c.id);
  select * into v_w from public.competition_waitlist w
   where w.competition_id = v_c.id and w.profile_id = v_uid
     and w.offered_at is not null and w.offer_expires_at > now();
  if v_w.id is null then
    raise exception 'Du har ikke et tilbud om plass (det kan ha gått ut)' using errcode = '55000';
  end if;

  delete from public.competition_waitlist where id = v_w.id;
  if coalesce(p_accept, false) then
    select * into v_row from public.competition_participants p
     where p.competition_id = v_c.id
       and (p.profile_id = v_uid or (v_w.member_id is not null and p.member_id = v_w.member_id))
     limit 1;
    if v_row.id is not null then
      update public.competition_participants set status = 'active' where id = v_row.id;
    elsif v_w.member_id is not null
          and exists (select 1 from public.club_members m
                       where m.id = v_w.member_id and m.user_id = v_uid and m.status = 'active') then
      insert into public.competition_participants (competition_id, member_id) values (v_c.id, v_w.member_id);
    else
      insert into public.competition_participants (competition_id, profile_id) values (v_c.id, v_uid);
    end if;
  end if;
  perform public.competition_fill(v_c.id);
  return public.competition_signup_json(v_c.id);
end;
$$;
revoke all on function public.competition_offer_respond(uuid, boolean) from public, anon;
grant execute on function public.competition_offer_respond(uuid, boolean) to authenticated;

-- Ventelista med navn, for arrangøren og staben (organizer).
create or replace function public.competition_waitlist_entries(p_competition_id uuid)
returns table (
  id                uuid,
  waitlist_position integer,
  profile_id        uuid,
  member_id         uuid,
  display_name      text,
  created_at        timestamptz,
  offered_at        timestamptz,
  offer_expires_at  timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select w.id,
         (row_number() over (order by w.created_at, w.id))::integer,
         w.profile_id, w.member_id,
         coalesce(m.display_name, pf.display_name, 'Uten navn'),
         w.created_at, w.offered_at, w.offer_expires_at
    from public.competition_waitlist w
    left join public.club_members m on m.id = w.member_id
    left join public.profiles pf on pf.id = w.profile_id
   where w.competition_id = p_competition_id
     and public.is_competition_admin(p_competition_id)
   order by w.created_at, w.id;
$$;
revoke all on function public.competition_waitlist_entries(uuid) from public, anon;
grant execute on function public.competition_waitlist_entries(uuid) to authenticated;

-- Arrangørens innstillinger for påmeldingen. Sjekkene på competitions (031)
-- gjelder: venteliste krever tak, åpen for alle og offentlig liste krever en
-- påmeldingsliste (ikke hele troppen), vinduet må gå forover. Et høyere tak
-- tilbyr plassene til køen med en gang.
create or replace function public.set_competition_signup(
  p_competition_id    uuid,
  p_signup_open       boolean,
  p_audience          text,
  p_listed            boolean,
  p_max_entrants      integer,
  p_waitlist_enabled  boolean,
  p_opens_at          timestamptz,
  p_closes_at         timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_c public.competitions;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select * into v_c from public.competitions where id = p_competition_id for update;
  if v_c.id is null or not public.can_read_competition(v_c.id) then
    raise exception 'Fant ikke turneringen' using errcode = 'P0002';
  end if;
  if not public.is_competition_admin(v_c.id) then
    raise exception 'Bare arrangøren kan endre påmeldingen' using errcode = '42501';
  end if;
  if v_c.entry = 'club'
     and (coalesce(p_signup_open, false) or coalesce(p_audience, 'members') <> 'members'
          or coalesce(p_listed, false) or p_max_entrants is not null or coalesce(p_waitlist_enabled, false)) then
    raise exception 'Hele troppen er med i denne turneringen, så den har ingen påmelding'
      using errcode = '55000';
  end if;
  if coalesce(p_waitlist_enabled, false) and p_max_entrants is null then
    raise exception 'Venteliste krever et tak på antall påmeldte' using errcode = '22023';
  end if;
  if p_max_entrants is not null and p_max_entrants not between 2 and 5000 then
    raise exception 'Taket må være mellom 2 og 5000' using errcode = '22023';
  end if;
  if p_opens_at is not null and p_closes_at is not null and p_closes_at < p_opens_at then
    raise exception 'Påmeldingen må stenge etter at den åpner' using errcode = '22023';
  end if;
  if coalesce(p_listed, false) and v_c.club_id is null then
    raise exception 'Bare en klubb eller et senter kan vise turneringen i en offentlig liste'
      using errcode = '22023';
  end if;

  update public.competitions
     set signup_open      = coalesce(p_signup_open, false),
         signup_audience  = coalesce(p_audience, 'members'),
         listed           = coalesce(p_listed, false),
         max_entrants     = p_max_entrants,
         waitlist_enabled = coalesce(p_waitlist_enabled, false),
         signup_opens_at  = p_opens_at,
         signup_closes_at = p_closes_at
   where id = v_c.id;
  perform public.competition_fill(v_c.id);
  return public.competition_signup_json(v_c.id);
end;
$$;
revoke all on function public.set_competition_signup(uuid, boolean, text, boolean, integer, boolean, timestamptz, timestamptz)
  from public, anon;
grant execute on function public.set_competition_signup(uuid, boolean, text, boolean, integer, boolean, timestamptz, timestamptz)
  to authenticated;

-- Åpne turneringer (listed + anyone) for alle innloggede: navn, type, arena,
-- tid, sted og plasser. Ikke runder, tropp eller påmeldte (beslutning 3).
create or replace function public.public_competitions(p_club_id uuid default null)
returns table (
  id                uuid,
  kind              text,
  name              text,
  club_id           uuid,
  club_name         text,
  club_kind         text,
  status            text,
  starts_on         date,
  ends_on           date,
  venue             text,
  max_entrants      integer,
  entrants          integer,
  waitlist          integer,
  signup_open       boolean,
  waitlist_enabled  boolean,
  signup_opens_at   timestamptz,
  signup_closes_at  timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, c.kind, c.name, c.club_id, k.name, k.kind, c.status, c.starts_on, c.ends_on, c.venue,
         c.max_entrants,
         (select count(*)::integer from public.competition_participants p
           where p.competition_id = c.id and p.status = 'active'),
         (select count(*)::integer from public.competition_waitlist w where w.competition_id = c.id),
         c.signup_open, c.waitlist_enabled, c.signup_opens_at, c.signup_closes_at
    from public.competitions c
    join public.clubs k on k.id = c.club_id
   where auth.uid() is not null
     and c.listed and c.signup_audience = 'anyone' and c.status <> 'finished'
     and (p_club_id is null or c.club_id = p_club_id)
   order by c.starts_on nulls last, c.name
   limit 200;
$$;
revoke all on function public.public_competitions(uuid) from public, anon;
grant execute on function public.public_competitions(uuid) to authenticated;

-- Bare service_role (pg_cron): utløpte tilbud går videre, og ledige plasser
-- (for eksempel etter en avmelding fra et gammelt bygg eller en arrangør som
-- tok ut en påmeldt) tilbys køen. Gir antall nye tilbud.
create or replace function public.expire_competition_offers()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id  uuid;
  v_n   integer := 0;
begin
  for v_id in
    select distinct w.competition_id from public.competition_waitlist w order by 1
  loop
    v_n := v_n + public.competition_fill(v_id);
  end loop;
  return v_n;
end;
$$;
revoke all on function public.expire_competition_offers() from public, anon, authenticated;
grant execute on function public.expire_competition_offers() to service_role;


-- ===========================================================================
-- 8. STARTLISTA
-- ===========================================================================
-- Lagrer startlista for en runde i én transaksjon: pulje (rounds.wave_no) og
-- gruppene (round_start_groups) med starttid, starthull, bås/simulator og
-- funksjonær. Gruppene som ikke står i lista, slettes. Spillerne i gruppa er
-- round_players.bay_no (runde-oppsettet), så de røres ikke her.
-- p_groups: [{"group_no": 1, "starts_at": "18:00", "start_hole": 1,
--             "resource_label": "Bås 1", "scorer_id": null}, …]
create or replace function public.save_start_list(p_round_id uuid, p_wave_no integer, p_groups jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r            public.rounds;
  v_competition  uuid;
  v_holes        integer;
  v_g            jsonb;
  v_no           integer;
  v_hole         integer;
  v_label        text;
  v_scorer       uuid;
  v_nos          integer[] := '{}';
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select * into v_r from public.rounds where id = p_round_id for update;
  if v_r.id is null or not public.can_read_round(v_r.id) then
    raise exception 'Fant ikke runden' using errcode = 'P0002';
  end if;
  if not public.is_round_organizer(v_r.id) then
    raise exception 'Bare arrangøren kan lage startlista' using errcode = '42501';
  end if;
  if v_r.status = 'locked' then
    raise exception 'Runden er låst' using errcode = '55000';
  end if;
  if p_wave_no is null or p_wave_no not between 1 and 20 then
    raise exception 'Puljen må være mellom 1 og 20' using errcode = '22023';
  end if;
  if p_groups is null or jsonb_typeof(p_groups) <> 'array' or jsonb_array_length(p_groups) > 99 then
    raise exception 'Startlista må være en liste med høyst 99 grupper' using errcode = '22023';
  end if;

  select e.competition_id into v_competition from public.events e where e.id = v_r.event_id;
  select count(*) into v_holes from public.round_holes h where h.round_id = v_r.id;
  if v_holes = 0 then
    v_holes := coalesce(v_r.hole_count, 18);
  end if;

  for v_g in select * from jsonb_array_elements(p_groups) loop
    v_no := (v_g ->> 'group_no')::integer;
    if v_no is null or v_no not between 1 and 99 then
      raise exception 'Gruppenummeret må være mellom 1 og 99' using errcode = '22023';
    end if;
    if v_no = any (v_nos) then
      raise exception 'Gruppe % står to ganger', v_no using errcode = '22023';
    end if;
    v_nos := v_nos || v_no;
    v_hole := (v_g ->> 'start_hole')::integer;
    if v_hole is not null and v_hole not between 1 and v_holes then
      raise exception 'Starthullet må være mellom 1 og %', v_holes using errcode = '22023';
    end if;
    v_label := nullif(btrim(v_g ->> 'resource_label'), '');
    v_scorer := (v_g ->> 'scorer_id')::uuid;
    if v_scorer is not null
       and (v_competition is null
            or not exists (select 1 from public.competition_staff s
                            where s.competition_id = v_competition and s.profile_id = v_scorer)) then
      raise exception 'Funksjonæren må være i staben til turneringen' using errcode = '22023';
    end if;

    insert into public.round_start_groups (round_id, group_no, starts_at, start_hole, resource_label, scorer_id)
    values (v_r.id, v_no, (v_g ->> 'starts_at')::time, v_hole, v_label, v_scorer)
    on conflict (round_id, group_no) do update
      set starts_at      = excluded.starts_at,
          start_hole     = excluded.start_hole,
          resource_label = excluded.resource_label,
          scorer_id      = excluded.scorer_id;
  end loop;

  delete from public.round_start_groups g where g.round_id = v_r.id and not (g.group_no = any (v_nos));
  -- Puljen. To aktive runder i samme pulje på samme spilledag gir 23505
  -- (rounds_one_active_per_event_wave, 031).
  if v_r.wave_no is distinct from p_wave_no then
    update public.rounds set wave_no = p_wave_no where id = v_r.id;
  end if;
  return coalesce(array_length(v_nos, 1), 0);
end;
$$;
revoke all on function public.save_start_list(uuid, integer, jsonb) from public, anon;
grant execute on function public.save_start_list(uuid, integer, jsonb) to authenticated;

commit;


-- ===========================================================================
-- KONTROLL (kjør i SQL Editor etter fila, som én kjøring). Én rad per sjekk,
-- alle skal ha ok = true.
-- ===========================================================================
-- with f as (
--   select p.proname,
--          has_function_privilege('anon', p.oid, 'execute') as anon_kan,
--          has_function_privilege('authenticated', p.oid, 'execute') as auth_kan,
--          has_function_privilege('service_role', p.oid, 'execute') as service_kan,
--          p.proconfig, p.prosrc
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public'
--     and p.proname in ('waitlist_offer_hours', 'my_member_ids', 'my_entered_competition_ids',
--                       'my_staff_competition_ids', 'my_competition_event_ids', 'is_round_staff',
--                       'is_group_scorer', 'is_competition_participant', 'is_competition_admin',
--                       'can_read_competition', 'is_round_organizer', 'can_read_round', 'can_score',
--                       'guard_competition_staff', 'competition_fill', 'competition_signup_status',
--                       'competition_signup_json', 'competition_signup', 'competition_withdraw',
--                       'competition_offer_respond', 'competition_waitlist_entries',
--                       'set_competition_signup', 'public_competitions', 'expire_competition_offers',
--                       'save_start_list')
-- )
-- select 1 as nr, 'Alle 25 funksjonene finnes og har tom search_path' as sjekk,
--        (select count(*) = 25 and bool_and('search_path=""' = any(proconfig)) from f) as ok
-- union all
-- select 2, 'anon kan ikke kalle noen av dem',
--        (select bool_and(not anon_kan) from f)
-- union all
-- select 3, 'De gamle reglene står: én aktiv runde og sesong per klubb, én kveld per dato, én hovedturnering',
--        (select count(*) = 4 from pg_indexes where schemaname = 'public'
--          and indexname in ('rounds_one_active_per_club', 'seasons_one_active_per_club',
--                            'competitions_one_main_active', 'rounds_one_active_per_event_wave'))
--        and exists (select 1 from pg_constraint where conname = 'events_one_per_date'
--                     and conrelid = 'public.events'::regclass)
-- union all
-- select 4, 'Interne funksjoner kan ikke kalles av appen; utløp bare av service_role',
--        (select bool_and(not auth_kan) from f
--          where proname in ('competition_fill', 'competition_signup_json', 'guard_competition_staff',
--                            'expire_competition_offers'))
--        and (select service_kan from f where proname = 'expire_competition_offers')
-- union all
-- select 5, 'RPC-ene og hjelperne kan kalles av innloggede',
--        (select bool_and(auth_kan) from f
--          where proname not in ('competition_fill', 'competition_signup_json', 'guard_competition_staff',
--                                'expire_competition_offers'))
-- union all
-- select 6, 'Hjelperne fra 017 har grenene for staben',
--        (select count(*) = 5 from f
--          where proname in ('is_competition_admin', 'can_read_competition', 'is_round_organizer',
--                            'can_read_round', 'can_score')
--            and prosrc ~ '(competition_staff|is_round_staff|is_group_scorer)')
-- union all
-- select 7, 'De tre nye policyene finnes, og ingen annen policy fra før bruker staben',
--        (select count(*) = 3 from pg_policies where schemaname = 'public'
--          and policyname in ('competitions_select_staff', 'events_select_competition', 'rounds_select_competition'))
--        and not exists (select 1 from pg_policies where schemaname = 'public'
--                         and tablename not in ('app_config', 'competition_staff', 'competition_waitlist',
--                                               'round_start_groups')
--                         and policyname not in ('competitions_select_staff', 'events_select_competition',
--                                                'rounds_select_competition')
--                         and (coalesce(qual, '') || coalesce(with_check, ''))
--                             ~ '(competition_staff|my_staff_competition_ids|my_entered_competition_ids|my_competition_event_ids|signup_audience|listed|wave_no)')
-- union all
-- select 8, 'round_start_groups.scorer_id og app_config.waitlist_offer_hours finnes',
--        exists (select 1 from information_schema.columns where table_schema = 'public'
--                 and table_name = 'round_start_groups' and column_name = 'scorer_id')
--        and exists (select 1 from public.app_config where key = 'waitlist_offer_hours' and value ? 'hours')
-- union all
-- select 9, 'Ingen står på ventelista med et tilbud som har gått ut for mer enn en time siden (cron går)',
--        not exists (select 1 from public.competition_waitlist where offer_expires_at < now() - interval '1 hour')
-- union all
-- select 10, 'Paritet (Tavla): rundene via sesongens kvelder = rundene via turneringens spilledager = koblingene',
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
-- ETTER MIGRERINGEN: utløpte tilbud med pg_cron (IKKE satt opp, forslag)
-- ===========================================================================
-- Kjøres hvert 10. minutt. Utløpte tilbud slettes og plassen tilbys den neste
-- i køen. Uten cron skjer det samme neste gang noen melder seg på, av, eller
-- svarer på et tilbud i turneringen, så ingen plass blir lovet bort to ganger.
--
-- select cron.schedule('dd18-waitlist-offers', '*/10 * * * *',
--                      $$select public.expire_competition_offers()$$);
-- -- Fjerne igjen: select cron.unschedule('dd18-waitlist-offers');


-- ===========================================================================
-- RULLEBAKKE (bare test; startlistas funksjonærer og ventelistas tilbud går
-- tapt, påmeldingene står)
-- ===========================================================================
-- Hjelperne får 017-kroppene tilbake (kjør blokkene «create or replace
-- function public.is_competition_participant / can_read_competition /
-- is_competition_admin / can_read_round / is_round_organizer / can_score» fra
-- 017_fundament.sql på nytt), og guard_competition_staff fra 031. Så:
--
-- begin;
-- drop policy if exists competitions_select_staff on public.competitions;
-- drop policy if exists events_select_competition on public.events;
-- drop policy if exists rounds_select_competition on public.rounds;
-- drop function if exists public.save_start_list(uuid, integer, jsonb);
-- drop function if exists public.expire_competition_offers();
-- drop function if exists public.public_competitions(uuid);
-- drop function if exists public.set_competition_signup(uuid, boolean, text, boolean, integer, boolean, timestamptz, timestamptz);
-- drop function if exists public.competition_waitlist_entries(uuid);
-- drop function if exists public.competition_offer_respond(uuid, boolean);
-- drop function if exists public.competition_withdraw(uuid);
-- drop function if exists public.competition_signup(uuid);
-- drop function if exists public.competition_signup_json(uuid);
-- drop function if exists public.competition_signup_status(uuid[]);
-- drop function if exists public.competition_fill(uuid);
-- -- (hjelperne fra 017 og vakta fra 031 er gjenopprettet over, før disse)
-- drop function if exists public.is_group_scorer(uuid, smallint);
-- drop function if exists public.is_round_staff(uuid, text);
-- drop function if exists public.my_competition_event_ids(boolean);
-- drop function if exists public.my_staff_competition_ids(text);
-- drop function if exists public.my_entered_competition_ids();
-- drop function if exists public.my_member_ids();
-- drop index if exists public.round_start_groups_scorer_idx;
-- alter table public.round_start_groups drop column if exists scorer_id;
-- drop function if exists public.waitlist_offer_hours();
-- delete from public.app_config where key = 'waitlist_offer_hours';
-- commit;
