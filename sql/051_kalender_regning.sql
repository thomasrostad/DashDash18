-- 051: kalender og «Del regningen» (gjennomføringsplanen steg 10). Godkjent og kjørt på test 12.10.2026.
--
-- Krever 001–049 (045: signups.waitlisted_at; 046: push_group og grupper; 044: private-skjemaet).
-- Rører ikke 050 (reaksjoner, kommentarer, feed) og ikke push_group/push_group_map (se punkt 2e).
--
-- Beslutningene (Thomas 11.10.2026, docs/plan-konkurranser-og-sosialt.md):
--   Kalender: «Abonnement: kveldene du er påmeldt dukker opp og oppdateres selv.»
--   Del regningen: «Din del merkes «sendt» automatisk når du kommer tilbake fra Vipps. Mottakeren
--   bekrefter eller sier at den ikke kom. Ingen penger gjennom appen, ingen avtale med Vipps.»
--
-- Hva fila gjør:
--   1. KALENDER
--      calendar_tokens (user_id pk, token unik, created_at, revoked_at). Én lenke per innlogging.
--        Tokenet er 32 tegn base32 (a–z, 2–7), 160 tilfeldige bit fra gen_random_uuid (sterk
--        tilfeldighet i Postgres, uten pgcrypto). Ingen policyer: bare funksjonene under.
--      calendar_token(p_renew default false): ditt token. Lages når det mangler eller er trukket
--        tilbake. p_renew = true gir et nytt, og det gamle virker ikke lenger (P0002).
--      calendar_token_revoke(): skrur av lenken (revoked_at). calendar_token() gir en ny senere.
--      calendar_feed(p_token) for anon (som tv_board_data): kveldene innloggingen er bekreftet
--        påmeldt på (status yes og ikke på venteliste, 045), i alle klubber der hen er aktivt
--        medlem, fra i dag − 30 dager til i dag + 365 dager (norsk dato). Per kveld: id, klubbens
--        navn, turneringens navn og type, dato, starttid, sted, notat og updated_at (det seneste av
--        kvelden og påmeldingen). INGEN bruker-id, medlems-id, navn på personer eller e-post.
--        En kveld som slettes, eller en påmelding som endres til nei/kanskje/venteliste, forsvinner
--        fra svaret (og fra kalenderen ved neste henting). Ukjent eller tilbaketrukket token: P0002.
--        Workeren (web/atten-lenker, /kalender/<token>.ics) lager iCalendar av svaret.
--
--   2. DEL REGNINGEN
--      a) Tabellene
--      bill_splits (id, club_id, event_id, round_id, created_by, payee_profile_id, payee_name,
--                   payee_vipps, title, total_ore, created_at)
--      bill_split_shares (id, split_id, profile_id, name, amount_ore, is_payee, sent_at,
--                         confirmed_at, disputed_at, status (generert), created_at)
--        * Hvem: profiler (innlogginger). En del uten profil (gjest, medlem uten innlogging) har
--          bare navn og kan bare bekreftes av mottakeren (kontant, eller Vipps fra en annen).
--        * Mottakerens egen del lagres som en del med is_payee (bekreftet med en gang), så
--          summen av delene alltid er hele regningen: nullsum. Sjekkes ved slutten av
--          transaksjonen (utsatt constraint-trigger) og i RPC-en.
--        * Hører til en klubb (med eller uten kveld og runde) eller en løs runde (uten klubb).
--          En av dem kreves når den lages.
--      b) Personvern (besluttet her):
--        * Vipps-nummeret er en personopplysning. Det lagres bare på regningen (aldri på profilen),
--          bare når mottakeren selv legger det inn (mottakeren er den som lager regningen, eller
--          legger det inn etterpå med bill_split_set_vipps), og det slettes av seg selv når alle
--          delene er bekreftet, eller når mottakeren sletter kontoen. Andre enn mottakeren kan ikke
--          skrive et nummer for hen.
--        * Bare de som er med, ser regningen og delene: den som laget den, mottakeren og de som
--          skal betale (profil). Ikke arrangøren eller kassereren (rettigheten money gir ingenting
--          her: det er ingen penger gjennom appen, og gjengens oppgjør er deres eget).
--        * Aktivitetslinjene (Varsler/Hjem) har regningens id, del-id, tittel og navnet, ikke beløpet
--          (aktivitet med mottakere kan leses av arrangøren etter 001-regelen).
--      c) RPC-ene (alt skrives gjennom dem; ingen skrivepolicyer)
--        bill_split_create(tittel, total, mottakerens navn, deler, mottakerens profil, mottakerens
--                          egen del, vipps, klubb, kveld, runde) → {split_id, shares}
--          Hvem: et aktivt medlem i klubben (klubbregning), eller en som er med i den løse runden
--          (eier, deltaker med profil). Mottakeren og alle med profil må være med på samme måte.
--          Vipps-nummer bare når du selv er mottakeren. 1–50 deler, beløp i øre > 0, høyst 1 000 000 kr,
--          navn 1–40 tegn, tittel 1–60 tegn, ingen profil to ganger. Høyst 50 regninger i døgnet.
--        bill_split_set_vipps(regning, nummer): bare mottakeren; null fjerner det.
--        bill_share_mark_sent(del): bare den som skal betale (profilen). Appen kaller den selv når
--          brukeren kommer tilbake fra Vipps. Idempotent: allerede sendt eller bekreftet = ingen
--          endring. Etter «kom ikke» merkes den sendt på nytt. Ny «sendt» gir bill_share_sent til
--          mottakeren.
--        bill_share_confirm(del, mottatt): bare mottakeren (eller den som laget regningen, når
--          mottakeren ikke har innlogging). true = bekreftet (også uten «sendt», f.eks. kontant).
--          false = «kom ikke»: bare når delen er merket sendt eller bekreftet; gir bill_share_disputed
--          til den som skal betale. Når alle delene er bekreftet, slettes Vipps-nummeret.
--        bill_split_delete(regning): bare den som laget den, og bare når ingen del (utenom
--          mottakerens egen) er bekreftet.
--      d) Aktivitet: bill_share_sent (til mottakeren) og bill_share_disputed (til den som skal
--         betale), kategori social, bare for klubbregninger og bare til et aktivt medlem med
--         innlogging (activity krever klubb eller turnering og har medlemmer som mottakere).
--         Løse runder uten klubb får ingen linje; statusen står i regningen.
--      e) Push-gruppe: push_group('social', kind) = 'social' (Sosialt) etter 046 uten endring:
--         det er mellom personer, ikke arrangørens, og regningen trenger ikke en kveld.
--         push_group_map() (046) har ikke de to nye kind-ene. Den røres ikke her fordi 050
--         (Sosialt) også skriver den om; den som kommer sist, legger til
--         ('social', 'bill_share_sent') og ('social', 'bill_share_disputed').
--
-- Mønsteret fra 001–049: én transaksjon, idempotent, search_path = '', revoke etter hver
-- create or replace, kontroll og rullebakke nederst.
--
-- Appen må (ikke i denne fila):
--   * Deg → «Kalender»: «Legg til i kalenderen» åpner webcal://dashdash18.com/kalender/<token>.ics
--     (calendar_token()), «Ny lenke» (calendar_token(true)) og «Skru av» (calendar_token_revoke()).
--     Forklar at lenken er personlig (den som har den, ser kveldene dine).
--   * Del regningen: lagre med bill_split_create (mottakerens egen del som p_payee_share_ore,
--     de andre med profil-id når de har innlogging), liste «Mine oppgjør» (select på bill_splits og
--     bill_split_shares), «Åpne Vipps» → ved retur til appen (scenePhase .active) kalle
--     bill_share_mark_sent for delen; mottakeren får «Fikk du den?» med «Ja» / «Kom ikke»
--     (bill_share_confirm). Teksten «Nummeret lagres ikke» endres til at det lagres på regningen
--     til alle har betalt.
--   * Varsler/Hjem: tekst for bill_share_sent («Anders har sendt sin del for Simulatorleie») og
--     bill_share_disputed («Thomas sier at din del for Simulatorleie ikke kom»), og gruppen
--     Sosialt i innstillingene.
--   * push-send: tekst for de to kind-ene (data.title, data.name).

begin;


-- ===========================================================================
-- 1. KALENDER
-- ===========================================================================
create table if not exists public.calendar_tokens (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  token       text not null unique check (token ~ '^[a-z2-7]{32}$'),
  created_at  timestamptz not null default now(),
  revoked_at  timestamptz
);
comment on table public.calendar_tokens is
  'Personlig kalenderlenke (sql/051): dashdash18.com/kalender/<token>.ics. Skrives bare av calendar_token og calendar_token_revoke.';
alter table public.calendar_tokens enable row level security;
revoke all on table public.calendar_tokens from public, anon, authenticated;
grant all on table public.calendar_tokens to service_role;
-- Ingen policyer: tabellen leses og skrives bare gjennom funksjonene under.

-- 32 tegn base32 fra tre gen_random_uuid (byte 7 har versjonsbiten i de lave fem bitene og
-- hoppes over; byte 9 har variantbitene øverst, de lave fem er tilfeldige). 256 er delelig med
-- 32, så get_byte % 32 er jevnt fordelt.
create or replace function private.calendar_new_token()
returns text
language sql
volatile
security definer
set search_path = ''
as $$
  select string_agg(substr('abcdefghijklmnopqrstuvwxyz234567', 1 + get_byte(b, i) % 32, 1), '' order by n, i)
    from (select n, decode(replace(gen_random_uuid()::text, '-', ''), 'hex') as b
            from generate_series(1, 3) n) u
   cross join lateral (select i from generate_series(0, 15) i where i <> 6) x
   where (n - 1) * 15 + (case when i < 6 then i else i - 1 end) < 32;
$$;
revoke all on function private.calendar_new_token() from public, anon, authenticated;

create or replace function public.calendar_token(p_renew boolean default false)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := auth.uid();
  v_token text;
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if not coalesce(p_renew, false) then
    select t.token into v_token from public.calendar_tokens t
     where t.user_id = v_uid and t.revoked_at is null;
    if v_token is not null then return v_token; end if;
  end if;
  loop
    v_token := private.calendar_new_token();
    begin
      insert into public.calendar_tokens as t (user_id, token) values (v_uid, v_token)
      on conflict (user_id) do update set token = excluded.token, created_at = now(), revoked_at = null;
      return v_token;
    exception when unique_violation then
      -- Samme token som en annen (2^-160): prøv igjen.
    end;
  end loop;
end;
$$;
revoke all on function public.calendar_token(boolean) from public, anon;
grant execute on function public.calendar_token(boolean) to authenticated;

create or replace function public.calendar_token_revoke()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  update public.calendar_tokens set revoked_at = now()
   where user_id = auth.uid() and revoked_at is null;
end;
$$;
revoke all on function public.calendar_token_revoke() from public, anon;
grant execute on function public.calendar_token_revoke() to authenticated;

-- Kveldene for kalenderen. Ingen personopplysninger i svaret.
create or replace function public.calendar_feed(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid   uuid;
  v_today date := (now() at time zone 'Europe/Oslo')::date;
begin
  if p_token is null or p_token !~ '^[a-z2-7]{32}$' then
    raise exception 'Fant ingen kalender for lenken' using errcode = 'P0002';
  end if;
  select t.user_id into v_uid from public.calendar_tokens t
   where t.token = p_token and t.revoked_at is null;
  if v_uid is null then
    raise exception 'Fant ingen kalender for lenken' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'generated_at', now(),
    'time_zone', 'Europe/Oslo',
    'events', (select coalesce(jsonb_agg(to_jsonb(x) order by x.date, x.start_time nulls first, x.id), '[]')
      from (
        select distinct on (e.id)
               e.id, k.name as club_name, c.name as competition_name, c.kind as competition_kind,
               e.event_date as date, e.start_time, e.venue, e.note,
               greatest(e.updated_at, s.updated_at) as updated_at
          from public.club_members m
          join public.signups s on s.member_id = m.id and s.club_id = m.club_id
          join public.events e on e.id = s.event_id and e.club_id = s.club_id
          join public.clubs k on k.id = e.club_id
          left join public.competitions c on c.id = e.competition_id
         where m.user_id = v_uid and m.status = 'active'
           and s.status = 'yes' and s.waitlisted_at is null
           and e.event_date between v_today - 30 and v_today + 365
         order by e.id, s.updated_at desc) x)
  );
end;
$$;
revoke all on function public.calendar_feed(text) from public;
grant execute on function public.calendar_feed(text) to anon, authenticated;


-- ===========================================================================
-- 2. DEL REGNINGEN
-- ===========================================================================
create table if not exists public.bill_splits (
  id                uuid primary key default gen_random_uuid(),
  club_id           uuid references public.clubs(id) on delete cascade,
  event_id          uuid,
  round_id          uuid references public.rounds(id) on delete set null,
  created_by        uuid references public.profiles(id) on delete set null,
  payee_profile_id  uuid references public.profiles(id) on delete set null,
  payee_name        text not null check (char_length(btrim(payee_name)) between 1 and 40),
  payee_vipps       text check (payee_vipps is null or payee_vipps ~ '^[49][0-9]{7}$'),
  title             text not null check (char_length(btrim(title)) between 1 and 60),
  total_ore         integer not null check (total_ore between 1 and 100000000),
  created_at        timestamptz not null default now(),
  constraint bill_splits_event_fk foreign key (event_id, club_id)
    references public.events (id, club_id) on delete set null (event_id),
  constraint bill_splits_event_needs_club check (event_id is null or club_id is not null)
);
comment on table public.bill_splits is
  'Del regningen (sql/051): én felles utgift, hvem som la ut (mottakeren) og Vipps-nummeret til alle har betalt. '
  'Leses av den som laget den, mottakeren og de som skal betale. Skrives bare av RPC-ene bill_split_*.';
comment on column public.bill_splits.payee_vipps is
  'Mottakerens mobilnummer (8 sifre), lagt inn av mottakeren selv. Slettes når alle delene er bekreftet og når mottakeren sletter kontoen.';
create index if not exists bill_splits_club_idx on public.bill_splits (club_id, created_at desc) where club_id is not null;
create index if not exists bill_splits_round_idx on public.bill_splits (round_id) where round_id is not null;
create index if not exists bill_splits_created_by_idx on public.bill_splits (created_by, created_at desc);
create index if not exists bill_splits_payee_idx on public.bill_splits (payee_profile_id) where payee_profile_id is not null;

create table if not exists public.bill_split_shares (
  id            uuid primary key default gen_random_uuid(),
  split_id      uuid not null references public.bill_splits(id) on delete cascade,
  profile_id    uuid references public.profiles(id) on delete set null,
  name          text not null check (char_length(btrim(name)) between 1 and 40),
  amount_ore    integer not null check (amount_ore between 0 and 100000000),
  is_payee      boolean not null default false,
  sent_at       timestamptz,
  confirmed_at  timestamptz,
  disputed_at   timestamptz,
  status        text generated always as (
                  case when confirmed_at is not null then 'confirmed'
                       when disputed_at is not null then 'disputed'
                       when sent_at is not null then 'sent'
                       else 'open' end) stored,
  created_at    timestamptz not null default now(),
  constraint bill_split_shares_not_both check (confirmed_at is null or disputed_at is null),
  constraint bill_split_shares_amount_positive check (is_payee or amount_ore > 0)
);
comment on table public.bill_split_shares is
  'Delene i en regning (sql/051). is_payee = mottakerens egen del (bekreftet). Summen av delene = total_ore. '
  'status: open, sent (merket sendt etter Vipps), confirmed (mottakeren fikk den), disputed (kom ikke).';
create index if not exists bill_split_shares_split_idx on public.bill_split_shares (split_id);
create index if not exists bill_split_shares_profile_idx on public.bill_split_shares (profile_id) where profile_id is not null;
create unique index if not exists bill_split_shares_one_per_profile
  on public.bill_split_shares (split_id, profile_id) where profile_id is not null;
create unique index if not exists bill_split_shares_one_payee
  on public.bill_split_shares (split_id) where is_payee;

-- Nullsum: summen av delene = regningen, sjekket ved slutten av transaksjonen.
create or replace function private.bill_split_check_sum()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ids   uuid[];
  v_split uuid;
  v_total integer;
  v_sum   bigint;
begin
  if tg_table_name = 'bill_splits' then
    v_ids := array[new.id];
  elsif tg_op = 'DELETE' then
    v_ids := array[old.split_id];
  elsif tg_op = 'UPDATE' then
    v_ids := array[new.split_id, old.split_id];  -- en del som flyttes, sjekkes begge steder
  else
    v_ids := array[new.split_id];
  end if;
  foreach v_split in array v_ids loop
    select s.total_ore into v_total from public.bill_splits s where s.id = v_split;
    continue when v_total is null;  -- regningen er slettet
    select coalesce(sum(x.amount_ore), 0) into v_sum from public.bill_split_shares x where x.split_id = v_split;
    if v_sum <> v_total then
      raise exception 'Delene (% øre) er ikke lik regningen (% øre)', v_sum, v_total using errcode = '23514';
    end if;
  end loop;
  return null;
end;
$$;
revoke all on function private.bill_split_check_sum() from public, anon, authenticated;

drop trigger if exists bill_splits_check_sum on public.bill_splits;
create constraint trigger bill_splits_check_sum after insert or update of total_ore on public.bill_splits
  deferrable initially deferred for each row execute function private.bill_split_check_sum();
drop trigger if exists bill_split_shares_check_sum on public.bill_split_shares;
create constraint trigger bill_split_shares_check_sum after insert or update of amount_ore, split_id or delete
  on public.bill_split_shares
  deferrable initially deferred for each row execute function private.bill_split_check_sum();

-- Mottakeren sletter kontoen (payee_profile_id blir tom): nummeret går også.
create or replace function private.bill_splits_payee_gone()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.payee_profile_id is not null and new.payee_profile_id is null then
    new.payee_vipps := null;
  end if;
  return new;
end;
$$;
revoke all on function private.bill_splits_payee_gone() from public, anon, authenticated;
drop trigger if exists bill_splits_payee_gone on public.bill_splits;
create trigger bill_splits_payee_gone before update of payee_profile_id on public.bill_splits
  for each row execute function private.bill_splits_payee_gone();

-- Regningene innloggingen er med i (laget, mottaker eller skal betale). Mengdebasert for RLS.
create or replace function private.my_bill_split_ids()
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(distinct x.id), '{}') from (
    select s.id from public.bill_splits s
     where s.created_by = auth.uid() or s.payee_profile_id = auth.uid()
    union all
    select sh.split_id from public.bill_split_shares sh where sh.profile_id = auth.uid()
  ) x where auth.uid() is not null;
$$;
revoke all on function private.my_bill_split_ids() from public, anon;
grant execute on function private.my_bill_split_ids() to authenticated, service_role;

alter table public.bill_splits enable row level security;
alter table public.bill_split_shares enable row level security;
revoke all on table public.bill_splits from public, anon, authenticated;
revoke all on table public.bill_split_shares from public, anon, authenticated;
grant select on table public.bill_splits to authenticated;
grant select on table public.bill_split_shares to authenticated;
grant all on table public.bill_splits to service_role;
grant all on table public.bill_split_shares to service_role;

drop policy if exists bill_splits_select on public.bill_splits;
create policy bill_splits_select on public.bill_splits
  for select to authenticated
  using (id = any ((select private.my_bill_split_ids())::uuid[]));
drop policy if exists bill_split_shares_select on public.bill_split_shares;
create policy bill_split_shares_select on public.bill_split_shares
  for select to authenticated
  using (split_id = any ((select private.my_bill_split_ids())::uuid[]));

-- Profilene som er med i en løs runde: eieren, deltakere med profil, og medlemmer med innlogging
-- som spiller i den.
create or replace function private.round_profile_ids(p_round_id uuid)
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(distinct p), '{}') from (
    select r.owner_id as p from public.rounds r where r.id = p_round_id
    union all
    select rp.profile_id from public.round_participants rp where rp.round_id = p_round_id
    union all
    select m.user_id from public.round_players pl join public.club_members m on m.id = pl.member_id
     where pl.round_id = p_round_id
  ) x where p is not null;
$$;
revoke all on function private.round_profile_ids(uuid) from public, anon, authenticated;

-- Medlems-id for en profil i en klubb (aktivt medlem), eller null.
create or replace function private.club_member_for_profile(p_club_id uuid, p_profile_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.id from public.club_members m
   where m.club_id = p_club_id and m.user_id = p_profile_id and m.status = 'active'
   limit 1;
$$;
revoke all on function private.club_member_for_profile(uuid, uuid) from public, anon, authenticated;

-- Norsk mobilnummer: 8 sifre som begynner på 4 eller 9, med eller uten +47/0047 og mellomrom.
create or replace function private.vipps_phone(p_raw text)
returns text
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v text := regexp_replace(coalesce(p_raw, ''), '[^0-9]', '', 'g');
begin
  if v = '' then return null; end if;
  if char_length(v) = 10 and left(v, 2) = '47' then v := substr(v, 3); end if;
  if char_length(v) = 12 and left(v, 4) = '0047' then v := substr(v, 5); end if;
  if v !~ '^[49][0-9]{7}$' then
    raise exception 'Skriv et norsk mobilnummer med 8 sifre' using errcode = '22023';
  end if;
  return v;
end;
$$;
revoke all on function private.vipps_phone(text) from public, anon, authenticated;

-- Aktivitet for en del (bare klubbregninger, bare til et aktivt medlem med innlogging).
create or replace function private.bill_activity(p_split public.bill_splits, p_share public.bill_split_shares,
                                                 p_kind text, p_actor uuid, p_recipient uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prev  text := current_setting('dd18.server_activity', true);
  v_to    uuid;
begin
  if p_split.club_id is null or p_recipient is null then
    return;
  end if;
  v_to := private.club_member_for_profile(p_split.club_id, p_recipient);
  if v_to is null then
    return;
  end if;
  perform set_config('dd18.server_activity', 'on', true);
  insert into public.activity (club_id, kind, category, data, actor_member_id, recipients)
  values (p_split.club_id, p_kind, 'social',
          jsonb_build_object('split_id', p_split.id, 'share_id', p_share.id, 'title', p_split.title,
                             'name', case when p_kind = 'bill_share_sent' then p_share.name else p_split.payee_name end),
          private.club_member_for_profile(p_split.club_id, p_actor), array[v_to]);
  perform set_config('dd18.server_activity', coalesce(v_prev, ''), true);
end;
$$;
revoke all on function private.bill_activity(public.bill_splits, public.bill_split_shares, text, uuid, uuid)
  from public, anon, authenticated;


create or replace function public.bill_split_create(
  p_title            text,
  p_total_ore        integer,
  p_payee_name       text,
  p_shares           jsonb,
  p_payee_profile_id uuid default null,
  p_payee_share_ore  integer default 0,
  p_payee_vipps      text default null,
  p_club_id          uuid default null,
  p_event_id         uuid default null,
  p_round_id         uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_club    uuid := p_club_id;
  v_round   public.rounds%rowtype;
  v_people  uuid[];
  v_split   uuid;
  v_phone   text;
  v_sum     bigint;
  v_n       integer;
  v_bad     bigint;
  v_outside bigint;
  v_dupes   bigint;
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  -- Hvor regningen hører til.
  if p_event_id is not null then
    select coalesce(v_club, e.club_id) into v_club from public.events e where e.id = p_event_id;
    if not found or not exists (select 1 from public.events e where e.id = p_event_id and e.club_id = v_club) then
      raise exception 'Fant ikke kvelden i klubben' using errcode = 'P0002';
    end if;
  end if;
  if p_round_id is not null then
    select * into v_round from public.rounds r where r.id = p_round_id;
    if v_round.id is null or not public.can_read_round(p_round_id) then
      raise exception 'Fant ikke runden' using errcode = 'P0002';
    end if;
    if v_round.club_id is not null then
      if v_club is null then v_club := v_round.club_id;
      elsif v_club <> v_round.club_id then
        raise exception 'Runden hører til en annen klubb' using errcode = '22023';
      end if;
    elsif v_club is not null then
      raise exception 'En løs runde hører ikke til en klubb' using errcode = '22023';
    end if;
  end if;
  if v_club is null and p_round_id is null then
    raise exception 'Regningen må høre til en klubb eller en runde' using errcode = '22023';
  end if;

  -- Hvem som er med: klubbens aktive medlemmer med innlogging, eller de som er med i den løse runden.
  if v_club is not null then
    if not public.is_club_member(v_club) then
      raise exception 'Du er ikke med i klubben' using errcode = '42501';
    end if;
    select coalesce(array_agg(m.user_id), '{}') into v_people from public.club_members m
     where m.club_id = v_club and m.status = 'active' and m.user_id is not null;
  else
    v_people := private.round_profile_ids(p_round_id);
    if not (v_uid = any (v_people)) then
      raise exception 'Du er ikke med i runden' using errcode = '42501';
    end if;
  end if;

  -- Grenser.
  select count(*) into v_n from public.bill_splits s
   where s.created_by = v_uid and s.created_at > now() - interval '1 day';
  if v_n >= 50 then
    raise exception 'Grensen er nådd: høyst 50 regninger i døgnet. Prøv igjen senere.' using errcode = '54000';
  end if;
  if char_length(btrim(coalesce(p_title, ''))) not between 1 and 60 then
    raise exception 'Skriv hva regningen gjelder (1–60 tegn)' using errcode = '22023';
  end if;
  if p_total_ore is null or p_total_ore not between 1 and 100000000 then
    raise exception 'Beløpet må være mellom 0,01 og 1 000 000 kr' using errcode = '22023';
  end if;
  if coalesce(p_payee_share_ore, -1) < 0 then
    raise exception 'Mottakerens del kan ikke være negativ' using errcode = '22023';
  end if;
  if jsonb_typeof(p_shares) is distinct from 'array' or jsonb_array_length(p_shares) not between 1 and 50 then
    raise exception 'Regningen må ha 1–50 som skal betale' using errcode = '22023';
  end if;
  if p_payee_profile_id is not null and not (p_payee_profile_id = any (v_people)) then
    raise exception 'Mottakeren er ikke med i klubben eller runden' using errcode = '22023';
  end if;

  -- Vipps-nummeret: bare ditt eget.
  v_phone := private.vipps_phone(p_payee_vipps);
  if v_phone is not null and p_payee_profile_id is distinct from v_uid then
    raise exception 'Bare mottakeren kan legge inn Vipps-nummeret sitt' using errcode = '42501';
  end if;

  -- Delene: [{profile_id (valgfri), name, amount_ore}].
  begin
    select count(*) filter (where char_length(btrim(coalesce(b.name, ''))) not between 1 and 40
                               or b.amount_ore is null or b.amount_ore not between 1 and 100000000),
           count(*) filter (where b.profile_id is not null and not (b.profile_id = any (v_people))),
           count(*) - count(distinct b.profile_id) - count(*) filter (where b.profile_id is null)
             + count(*) filter (where b.profile_id = p_payee_profile_id),
           coalesce(sum(b.amount_ore), 0) + p_payee_share_ore
      into v_bad, v_outside, v_dupes, v_sum
      from jsonb_to_recordset(p_shares) as b(profile_id uuid, name text, amount_ore integer);
  exception when invalid_text_representation or numeric_value_out_of_range or invalid_parameter_value
                 or datatype_mismatch then
    raise exception 'Delene har feil form ({profile_id, name, amount_ore})' using errcode = '22023';
  end;
  if v_bad > 0 then
    raise exception 'Hver del må ha navn (1–40 tegn) og et beløp over null' using errcode = '22023';
  end if;
  if v_outside > 0 then
    raise exception 'Noen som skal betale, er ikke med i klubben eller runden' using errcode = '22023';
  end if;
  if v_dupes > 0 then
    raise exception 'Samme person står to ganger' using errcode = '23505';
  end if;
  if v_sum <> p_total_ore then
    raise exception 'Delene (% øre) er ikke lik regningen (% øre)', v_sum, p_total_ore using errcode = '23514';
  end if;

  insert into public.bill_splits (club_id, event_id, round_id, created_by, payee_profile_id, payee_name,
                                  payee_vipps, title, total_ore)
  values (v_club, p_event_id, p_round_id, v_uid, p_payee_profile_id, btrim(p_payee_name),
          v_phone, btrim(p_title), p_total_ore)
  returning id into v_split;

  insert into public.bill_split_shares (split_id, profile_id, name, amount_ore, is_payee, sent_at, confirmed_at)
  values (v_split, p_payee_profile_id, btrim(p_payee_name), p_payee_share_ore, true, now(), now());
  insert into public.bill_split_shares (split_id, profile_id, name, amount_ore)
  select v_split, b.profile_id, btrim(b.name), b.amount_ore
    from rows from (jsonb_to_recordset(p_shares) as (profile_id uuid, name text, amount_ore integer))
         with ordinality as b(profile_id, name, amount_ore, n)
   order by b.n;

  return jsonb_build_object(
    'split_id', v_split,
    'shares', (select jsonb_agg(jsonb_build_object('id', s.id, 'profile_id', s.profile_id, 'name', s.name,
                                                   'amount_ore', s.amount_ore, 'is_payee', s.is_payee, 'status', s.status)
                                order by s.is_payee desc, s.created_at, s.name)
                 from public.bill_split_shares s where s.split_id = v_split));
end;
$$;
revoke all on function public.bill_split_create(text, integer, text, jsonb, uuid, integer, text, uuid, uuid, uuid) from public, anon;
grant execute on function public.bill_split_create(text, integer, text, jsonb, uuid, integer, text, uuid, uuid, uuid) to authenticated;


create or replace function public.bill_split_set_vipps(p_split_id uuid, p_phone text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_split public.bill_splits%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select * into v_split from public.bill_splits s where s.id = p_split_id
    and s.id = any (private.my_bill_split_ids()) for update;
  if v_split.id is null then
    raise exception 'Fant ikke regningen' using errcode = 'P0002';
  end if;
  if v_split.payee_profile_id is distinct from auth.uid() then
    raise exception 'Bare mottakeren kan legge inn Vipps-nummeret sitt' using errcode = '42501';
  end if;
  update public.bill_splits set payee_vipps = private.vipps_phone(p_phone) where id = p_split_id;
end;
$$;
revoke all on function public.bill_split_set_vipps(uuid, text) from public, anon;
grant execute on function public.bill_split_set_vipps(uuid, text) to authenticated;


create or replace function public.bill_share_mark_sent(p_share_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_share public.bill_split_shares%rowtype;
  v_split public.bill_splits%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select * into v_share from public.bill_split_shares s where s.id = p_share_id
    and s.split_id = any (private.my_bill_split_ids()) for update;
  if v_share.id is null then
    raise exception 'Fant ikke delen' using errcode = 'P0002';
  end if;
  if v_share.is_payee then
    raise exception 'Mottakerens egen del sendes ikke' using errcode = '22023';
  end if;
  if v_share.profile_id is distinct from auth.uid() then
    raise exception 'Bare den som skal betale, kan merke delen sendt' using errcode = '42501';
  end if;
  -- Allerede sendt (og ikke avvist) eller bekreftet: ingen endring, ingen ny linje.
  if v_share.confirmed_at is null and (v_share.sent_at is null or v_share.disputed_at is not null) then
    update public.bill_split_shares set sent_at = now(), disputed_at = null where id = p_share_id
    returning * into v_share;
    select * into v_split from public.bill_splits s where s.id = v_share.split_id;
    perform private.bill_activity(v_split, v_share, 'bill_share_sent', auth.uid(), v_split.payee_profile_id);
  end if;
  return jsonb_build_object('id', v_share.id, 'status', v_share.status, 'sent_at', v_share.sent_at);
end;
$$;
revoke all on function public.bill_share_mark_sent(uuid) from public, anon;
grant execute on function public.bill_share_mark_sent(uuid) to authenticated;


create or replace function public.bill_share_confirm(p_share_id uuid, p_received boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_share public.bill_split_shares%rowtype;
  v_split public.bill_splits%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if p_received is null then
    raise exception 'Si om du fikk den eller ikke' using errcode = '22023';
  end if;
  select * into v_share from public.bill_split_shares s where s.id = p_share_id
    and s.split_id = any (private.my_bill_split_ids());
  if v_share.id is null then
    raise exception 'Fant ikke delen' using errcode = 'P0002';
  end if;
  -- Regningen låses først (samme rekkefølge for alle delene), så delen.
  select * into v_split from public.bill_splits s where s.id = v_share.split_id for update;
  select * into v_share from public.bill_split_shares s where s.id = p_share_id for update;
  if not (v_split.payee_profile_id = auth.uid()
          or (v_split.payee_profile_id is null and v_split.created_by = auth.uid())) then
    raise exception 'Bare mottakeren kan bekrefte' using errcode = '42501';
  end if;
  if v_share.is_payee then
    raise exception 'Mottakerens egen del er alltid bekreftet' using errcode = '22023';
  end if;

  if p_received then
    if v_share.confirmed_at is null then
      update public.bill_split_shares set confirmed_at = now(), disputed_at = null where id = p_share_id
      returning * into v_share;
    end if;
    -- Alle har betalt: nummeret trengs ikke lenger.
    if v_split.payee_vipps is not null
       and not exists (select 1 from public.bill_split_shares s where s.split_id = v_split.id and s.confirmed_at is null) then
      update public.bill_splits set payee_vipps = null where id = v_split.id;
    end if;
  else
    if v_share.sent_at is null and v_share.confirmed_at is null then
      raise exception 'Delen er ikke merket sendt ennå' using errcode = '22023';
    end if;
    if v_share.disputed_at is null then
      update public.bill_split_shares set disputed_at = now(), confirmed_at = null where id = p_share_id
      returning * into v_share;
      perform private.bill_activity(v_split, v_share, 'bill_share_disputed', auth.uid(), v_share.profile_id);
    end if;
  end if;
  return jsonb_build_object('id', v_share.id, 'status', v_share.status,
                            'confirmed_at', v_share.confirmed_at, 'disputed_at', v_share.disputed_at);
end;
$$;
revoke all on function public.bill_share_confirm(uuid, boolean) from public, anon;
grant execute on function public.bill_share_confirm(uuid, boolean) to authenticated;


create or replace function public.bill_split_delete(p_split_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_split public.bill_splits%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select * into v_split from public.bill_splits s where s.id = p_split_id
    and s.id = any (private.my_bill_split_ids()) for update;
  if v_split.id is null then
    raise exception 'Fant ikke regningen' using errcode = 'P0002';
  end if;
  if v_split.created_by is distinct from auth.uid() then
    raise exception 'Bare den som laget regningen, kan slette den' using errcode = '42501';
  end if;
  if exists (select 1 from public.bill_split_shares s
              where s.split_id = p_split_id and not s.is_payee and s.confirmed_at is not null) then
    raise exception 'Noen har alt fått betalingen bekreftet. Regningen kan ikke slettes.' using errcode = '22023';
  end if;
  delete from public.bill_splits where id = p_split_id;
end;
$$;
revoke all on function public.bill_split_delete(uuid) from public, anon;
grant execute on function public.bill_split_delete(uuid) to authenticated;


-- ===========================================================================
-- KONTROLL
-- ===========================================================================
do $$
declare
  v_fail text := '';
begin
  -- 1. Tabellene finnes med RLS på.
  if (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname in ('calendar_tokens', 'bill_splits', 'bill_split_shares')
         and c.relrowsecurity) <> 3 then
    v_fail := v_fail || ' 1';
  end if;
  -- 2. calendar_tokens har ingen policyer; regningene har bare de to lesepolicyene.
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'calendar_tokens')
     or (select count(*) from pg_policies where schemaname = 'public'
           and tablename in ('bill_splits', 'bill_split_shares') and cmd = 'SELECT') <> 2
     or exists (select 1 from pg_policies where schemaname = 'public'
                 and tablename in ('bill_splits', 'bill_split_shares') and cmd <> 'SELECT') then
    v_fail := v_fail || ' 2';
  end if;
  -- 3. anon kan bare calendar_feed.
  if not has_function_privilege('anon', 'public.calendar_feed(text)', 'execute')
     or has_function_privilege('anon', 'public.calendar_token(boolean)', 'execute')
     or has_function_privilege('anon', 'public.calendar_token_revoke()', 'execute')
     or has_function_privilege('anon', 'public.bill_split_create(text, integer, text, jsonb, uuid, integer, text, uuid, uuid, uuid)', 'execute')
     or has_function_privilege('anon', 'public.bill_split_set_vipps(uuid, text)', 'execute')
     or has_function_privilege('anon', 'public.bill_share_mark_sent(uuid)', 'execute')
     or has_function_privilege('anon', 'public.bill_share_confirm(uuid, boolean)', 'execute')
     or has_function_privilege('anon', 'public.bill_split_delete(uuid)', 'execute')
     or has_table_privilege('anon', 'public.calendar_tokens', 'select')
     or has_table_privilege('anon', 'public.bill_splits', 'select')
     or has_table_privilege('anon', 'public.bill_split_shares', 'select') then
    v_fail := v_fail || ' 3';
  end if;
  -- 4. authenticated kan RPC-ene, men ikke lese tokenene eller skrive regningene direkte.
  if not has_function_privilege('authenticated', 'public.calendar_token(boolean)', 'execute')
     or not has_function_privilege('authenticated', 'public.bill_split_create(text, integer, text, jsonb, uuid, integer, text, uuid, uuid, uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.bill_share_mark_sent(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.bill_share_confirm(uuid, boolean)', 'execute')
     or not has_function_privilege('authenticated', 'public.bill_split_delete(uuid)', 'execute')
     or has_table_privilege('authenticated', 'public.calendar_tokens', 'select')
     or has_table_privilege('authenticated', 'public.bill_splits', 'insert')
     or has_table_privilege('authenticated', 'public.bill_splits', 'update')
     or has_table_privilege('authenticated', 'public.bill_split_shares', 'update')
     or has_table_privilege('authenticated', 'public.bill_split_shares', 'delete')
     or not has_table_privilege('authenticated', 'public.bill_split_shares', 'select') then
    v_fail := v_fail || ' 4';
  end if;
  -- 5. Hjelperne i private kan ikke kalles av appen (unntatt RLS-hjelperen).
  if has_function_privilege('authenticated', 'private.calendar_new_token()', 'execute')
     or has_function_privilege('authenticated', 'private.bill_split_check_sum()', 'execute')
     or has_function_privilege('authenticated', 'private.round_profile_ids(uuid)', 'execute')
     or has_function_privilege('authenticated', 'private.club_member_for_profile(uuid, uuid)', 'execute')
     or has_function_privilege('authenticated', 'private.vipps_phone(text)', 'execute')
     or has_function_privilege('authenticated', 'private.bill_activity(public.bill_splits, public.bill_split_shares, text, uuid, uuid)', 'execute')
     or not has_function_privilege('authenticated', 'private.my_bill_split_ids()', 'execute') then
    v_fail := v_fail || ' 5';
  end if;
  -- 6. Alle funksjonene her er security definer med tom search_path.
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where (n.nspname, p.proname) in (('public', 'calendar_token'), ('public', 'calendar_token_revoke'),
                                               ('public', 'calendar_feed'), ('public', 'bill_split_create'),
                                               ('public', 'bill_split_set_vipps'), ('public', 'bill_share_mark_sent'),
                                               ('public', 'bill_share_confirm'), ('public', 'bill_split_delete'),
                                               ('private', 'calendar_new_token'), ('private', 'bill_split_check_sum'),
                                               ('private', 'bill_splits_payee_gone'), ('private', 'my_bill_split_ids'),
                                               ('private', 'round_profile_ids'), ('private', 'club_member_for_profile'),
                                               ('private', 'vipps_phone'), ('private', 'bill_activity'))
               and (not p.prosecdef or not ('search_path=""' = any (p.proconfig))))
     or (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'public' and p.proname in ('calendar_token', 'calendar_token_revoke', 'calendar_feed',
                'bill_split_create', 'bill_split_set_vipps', 'bill_share_mark_sent', 'bill_share_confirm',
                'bill_split_delete')) <> 8 then
    v_fail := v_fail || ' 6';
  end if;
  -- 7. Nullsum-triggerne er utsatte constraint-triggere, og payee-triggeren står.
  if (select count(*) from pg_trigger where not tgisinternal and tgdeferrable and tginitdeferred
        and ((tgname = 'bill_splits_check_sum' and tgrelid = 'public.bill_splits'::regclass)
          or (tgname = 'bill_split_shares_check_sum' and tgrelid = 'public.bill_split_shares'::regclass))) <> 2
     or not exists (select 1 from pg_trigger where tgname = 'bill_splits_payee_gone'
                     and tgrelid = 'public.bill_splits'::regclass) then
    v_fail := v_fail || ' 7';
  end if;
  -- 8. Hver regning går i null: delene er lik regningen.
  if exists (select 1 from public.bill_splits s
              where s.total_ore <> (select coalesce(sum(x.amount_ore), 0) from public.bill_split_shares x where x.split_id = s.id)) then
    v_fail := v_fail || ' 8';
  end if;
  -- 9. Tokenene har riktig form, og et nytt token har det.
  if exists (select 1 from public.calendar_tokens where token !~ '^[a-z2-7]{32}$')
     or private.calendar_new_token() !~ '^[a-z2-7]{32}$' then
    v_fail := v_fail || ' 9';
  end if;
  -- 10. De nye linjene havner i gruppen Sosialt (046).
  if public.push_group('social', 'bill_share_sent') is distinct from 'social'
     or public.push_group('social', 'bill_share_disputed') is distinct from 'social' then
    v_fail := v_fail || ' 10';
  end if;

  if v_fail <> '' then
    raise exception '051 kontroll feilet:%', v_fail;
  end if;
  raise notice '051 kontroll: 10 av 10 (kalenderlenker: %, regninger: %, deler: %)',
    (select count(*) from public.calendar_tokens),
    (select count(*) from public.bill_splits),
    (select count(*) from public.bill_split_shares);
end $$;

commit;

-- ===========================================================================
-- RULLEBAKKE (sletter kalenderlenkene og alle regningene; aktivitetslinjene blir stående)
-- ===========================================================================
-- begin;
-- drop function if exists public.bill_split_delete(uuid);
-- drop function if exists public.bill_share_confirm(uuid, boolean);
-- drop function if exists public.bill_share_mark_sent(uuid);
-- drop function if exists public.bill_split_set_vipps(uuid, text);
-- drop function if exists public.bill_split_create(text, integer, text, jsonb, uuid, integer, text, uuid, uuid, uuid);
-- drop function if exists private.bill_activity(public.bill_splits, public.bill_split_shares, text, uuid, uuid);
-- drop function if exists private.vipps_phone(text);
-- drop function if exists private.club_member_for_profile(uuid, uuid);
-- drop function if exists private.round_profile_ids(uuid);
-- drop table if exists public.bill_split_shares;
-- drop table if exists public.bill_splits;
-- drop function if exists private.my_bill_split_ids();
-- drop function if exists private.bill_splits_payee_gone();
-- drop function if exists private.bill_split_check_sum();
-- drop function if exists public.calendar_feed(text);
-- drop function if exists public.calendar_token_revoke();
-- drop function if exists public.calendar_token(boolean);
-- drop function if exists private.calendar_new_token();
-- drop table if exists public.calendar_tokens;
-- commit;
