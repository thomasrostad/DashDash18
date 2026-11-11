-- 077_finn_fra_kontakter.sql — finn folk å følge fra kontaktene på telefonen (e-post og telefonnummer).
-- Thomas 11.11.2026: «Kan man legge til sånn finn fra kontakter?» og «Få til med telefonnr også».
-- Telefonnummeret bekreftes ikke (Thomas 11.11: «Dropp bekreftelse for nå»).
--
-- Personvern:
--   * Kontaktlista sendes aldri. Appen gjør hver e-post (små bokstaver, uten mellomrom) og hvert
--     nummer (E.164, +47 når landskoden mangler) om til sha256 (hex) på telefonen og sender bare
--     disse. Serveren sammenligner og lagrer ingenting av det som ble sendt.
--   * Bare søkbare profiler (profiles.searchable, «Kan finnes i søk») blir funnet, som i
--     search_people. Ikke deg selv, ikke blokkerte (begge veier), bare profiler med navn.
--   * Høyst 10 oppslag i timen per bruker (54000) og høyst 3000 koder per oppslag (22023).
--   * Telefonnummeret ligger i private.profile_phones (ikke i profiles, som andre kan lese).
--     Bare eieren leser det (my_phone). Slettes kontoen, slettes raden med profilen (cascade).
--   * Nummeret er ikke bekreftet. Appen viser navnet fra kontaktene ved siden av Atten-navnet,
--     så et feil nummer synes.
--
-- Nytt:
--   private.profile_phones (user_id, phone, phone_hash)
--   set_my_phone(tekst)  null eller tom = fjern. Godtar +landskode og 8 sifre (norsk, +47).
--                        Gir nummeret slik det er lagret (E.164) eller null.
--   my_phone()           eget nummer eller null.
--   find_contacts(e-postkoder, nummerkoder)  én rad per profil som traff: id, navn, bilde, ÉN klubb,
--                        min følgestatus, følger meg, og hvilke koder som traff (matched), så appen
--                        kan vise navnet fra kontakten. Følg med follow_request(id, 'suggestion').
--   people_rate_log.kind får 'contacts'.
--
-- Bare legg til (docs/utgivelser.md punkt 4): ny tabell, tre nye funksjoner, én verdi til i en
-- check. Ingen endring i follow_request (kilden er 'suggestion', som finnes). Krever 054.
-- Idempotent. Kontroll og rullebakk nederst.

begin;

alter table private.people_rate_log drop constraint if exists people_rate_log_kind_check;
alter table private.people_rate_log add constraint people_rate_log_kind_check
  check (kind in ('search', 'follow', 'code', 'contacts'));

create table if not exists private.profile_phones (
  user_id     uuid primary key references public.profiles (id) on delete cascade,
  phone       text not null check (phone ~ '^\+[1-9][0-9]{6,14}$'),
  phone_hash  text not null,
  updated_at  timestamptz not null default now()
);
comment on table private.profile_phones is
  '077: telefonnummer for «Finn fra kontakter» (ikke bekreftet). Bare set_my_phone, my_phone og find_contacts.';
create index if not exists profile_phones_hash_idx on private.profile_phones (phone_hash);
revoke all on table private.profile_phones from public, anon, authenticated;

-- --- Eget telefonnummer -------------------------------------------------------------
create or replace function public.set_my_phone(p_phone text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_p   text := regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g');
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if v_p = '' then
    delete from private.profile_phones where user_id = v_uid;
    return null;
  end if;
  if v_p like '00%' then
    v_p := '+' || substr(v_p, 3);
  elsif v_p ~ '^[0-9]{8}$' then
    v_p := '+47' || v_p;
  end if;
  if v_p !~ '^\+[1-9][0-9]{6,14}$' then
    raise exception 'Ugyldig telefonnummer' using errcode = '22023';
  end if;
  insert into private.profile_phones (user_id, phone, phone_hash, updated_at)
  values (v_uid, v_p, encode(sha256(convert_to(v_p, 'UTF8')), 'hex'), now())
  on conflict (user_id) do update
    set phone = excluded.phone, phone_hash = excluded.phone_hash, updated_at = now();
  return v_p;
end;
$$;
revoke all on function public.set_my_phone(text) from public, anon;
grant execute on function public.set_my_phone(text) to authenticated;

create or replace function public.my_phone()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select p.phone from private.profile_phones p where p.user_id = auth.uid();
$$;
revoke all on function public.my_phone() from public, anon;
grant execute on function public.my_phone() to authenticated;

-- --- Finn fra kontakter -------------------------------------------------------------
create or replace function public.find_contacts(p_email_hashes text[], p_phone_hashes text[])
returns table (id uuid, display_name text, avatar_path text, club_name text,
               my_status text, follows_me boolean, matched text[])
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := auth.uid();
  v_emails text[] := coalesce(p_email_hashes, '{}');
  v_phones text[] := coalesce(p_phone_hashes, '{}');
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if cardinality(v_emails) + cardinality(v_phones) > 3000 then
    raise exception 'For mange kontakter (høyst 3000)' using errcode = '22023';
  end if;
  if cardinality(v_emails) + cardinality(v_phones) = 0 then
    return;
  end if;
  perform private.people_rate_hit('contacts', null, 10, interval '1 hour', 'oppslag i kontaktene i timen');

  return query
  with hits as (
    select u.id as uid, encode(sha256(convert_to(lower(btrim(u.email)), 'UTF8')), 'hex') as h
      from auth.users u
     where u.email is not null
       and encode(sha256(convert_to(lower(btrim(u.email)), 'UTF8')), 'hex') = any (v_emails)
    union
    select ph.user_id, ph.phone_hash
      from private.profile_phones ph
     where ph.phone_hash = any (v_phones)
  )
  select p.id, p.display_name, p.avatar_path,
         (select c.name from public.club_members m join public.clubs c on c.id = m.club_id
           where m.user_id = p.id and m.status = 'active'
           order by m.created_at, m.id limit 1),
         coalesce((select f.status from public.follows f where f.follower_id = v_uid and f.followee_id = p.id), 'none'),
         exists (select 1 from public.follows f
                  where f.follower_id = p.id and f.followee_id = v_uid and f.status = 'accepted'),
         array_agg(distinct hits.h)
    from hits
    join public.profiles p on p.id = hits.uid
   where p.searchable
     and p.display_name is not null
     and p.id <> v_uid
     and not private.users_blocked(v_uid, p.id)
   group by p.id, p.display_name, p.avatar_path
   order by lower(p.display_name), p.id;
end;
$$;
revoke all on function public.find_contacts(text[], text[]) from public, anon;
grant execute on function public.find_contacts(text[], text[]) to authenticated;

commit;

-- --- Kontroll (les) ------------------------------------------------------------
-- select pg_get_constraintdef(oid) from pg_constraint where conname = 'people_rate_log_kind_check';  -- med 'contacts'
-- select has_table_privilege('authenticated', 'private.profile_phones', 'select');                  -- false
-- select has_function_privilege('anon', 'public.find_contacts(text[], text[])', 'execute');         -- false
-- select has_function_privilege('authenticated', 'public.find_contacts(text[], text[])', 'execute'); -- true
-- select has_function_privilege('anon', 'public.set_my_phone(text)', 'execute');                    -- false
-- select has_function_privilege('anon', 'public.my_phone()', 'execute');                            -- false
-- --- Rullebakk -------------------------------------------------------------------
-- drop function if exists public.find_contacts(text[], text[]);
-- drop function if exists public.my_phone();
-- drop function if exists public.set_my_phone(text);
-- drop table if exists private.profile_phones;
-- delete from private.people_rate_log where kind = 'contacts';
-- alter table private.people_rate_log drop constraint people_rate_log_kind_check;
-- alter table private.people_rate_log add constraint people_rate_log_kind_check
--   check (kind in ('search', 'follow', 'code'));
