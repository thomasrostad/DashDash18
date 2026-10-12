-- 050: sosialt (gjennomføringsplanen steg 9). Godkjent og kjørt på test 12.10.2026.
--
-- Krever 001–047 og 049 (kjøres på test etter dem): 008 (activity, activity_reactions,
-- thread_messages), 019 (blokkering, rapporter, delete_account_data), 034 (hendelser uten
-- klubb), 044 (private.has_club_right), 046 (push_group_map, push_job_payload, gruppen Sosialt).
-- Rører ikke 051 (kalender og Del regningen).
--
-- Beslutningene (Thomas 11.10.2026, docs/plan-konkurranser-og-sosialt.md):
--   Reaksjoner: fem faste (👍 😂 ⛳ 🔥 ❤️) først, alle andre emojier bak «+». På hendelser,
--               innlegg og kommentarer.
--   Kommentarer: flate, med @-omtale. Varsel til forfatteren og den som nevnes. «Følg tråden»
--               er et valg.
--   Bilder:     bildeoppfordring når runden låses.
--
-- Hva fila gjør:
--   1. Reaksjoner på alt: reactions (target_kind 'activity'|'message'|'comment', target_id,
--      club_id, competition_id, member_id eller profile_id, emoji, created_at). Én rad per mål,
--      person og emoji (person_id = member_id eller profile_id). I en klubb reagerer du som
--      medlem (member_id), i en turnering uten klubb som profil (profile_id), samme modell som
--      activity (actor_member_id) og push (034/046). Emoji: 1–16 tegn og ett «tegn» (én emoji
--      med hudfarge, ZWJ-sekvens, flagg eller tast), private.is_single_emoji. Høyst 20
--      forskjellige emojier per person og mål.
--      Lesing: du ser målet (private.can_read_target, samme regler som målets policy) og er ikke
--      blokkert mot den som reagerte (begge veier, blocked_between). Skriving bare med
--      react(kind, id, emoji, på/av).
--      Gamle bygg: activity_reactions BLIR STÅENDE som tabell og speiles begge veier med
--      triggere (fem-settet, hendelser i klubb). Valgt fordi appen i dag lytter på
--      activity_reactions med Realtime (HomeFeedModel, VarslerModel), og et view kan ikke være
--      med i en publikasjon, og fordi gamle bygg både leser, legger inn og sletter direkte.
--      Et gammelt bygg ser ikke de nye emojiene (de finnes bare i reactions). Innlegging i
--      activity_reactions krever nå i tillegg at du ser hendelsen og ikke er blokkert mot den
--      som gjorde den.
--   2. Kommentarer: comments (id, club_id, competition_id, target_kind 'activity'|'message',
--      target_id, member_id eller profile_id, body 1–1000 tegn, mentions, created_at,
--      edited_at, deleted_at, deleted_by). Flate: en kommentar kan ikke kommenteres (bare
--      reageres på). Lesing som målet, og ikke blokkert mot forfatteren. Skriving bare med
--      comment_add, comment_edit (bare forfatteren) og comment_delete (forfatteren, eller den
--      med rettigheten money i klubben, eller arrangøren av en turnering uten klubb).
--      Sletting er myk: raden står med deleted_at (så tråden, tellingen og Realtime ser det),
--      men teksten og omtalene tømmes. Rapporten har sitt eget øyeblikksbilde.
--      @-omtale: medlems-id-er i klubben (som thread_messages.mentions), profil-id-er uten klubb.
--      Den som nevnes må kunne se målet og ikke være blokkert mot forfatteren (ellers 22023).
--      Høyst 60 kommentarer på ti minutter per person.
--   3. «Følg tråden»: thread_follows (user_id, target_kind, target_id, following, created_at),
--      follow_thread(kind, id, på/av). Den som kommenterer, følger tråden (kan slås av med
--      p_follow = false eller follow_thread). Forfatteren av målet får varsel uten å følge,
--      men kan slå det av med follow_thread(…, false).
--      Varsler (activity, kategori social, gruppen Sosialt):
--        comment_added: mottakerne er forfatteren av målet og de som følger tråden, minus den
--                       som skrev, minus de som nevnes (de får mentioned i stedet, så ingen får
--                       to varsler), minus blokkerte og de som ikke lenger ser målet.
--        mentioned:     de som nevnes (også når en kommentar endres og får nye omtaler).
--      Mottakerlisten er medlems-id-er i klubben, profil-id-er uten klubb. For hendelser uten
--      klubb tillater activity_select nå også linjer med mottakerliste (auth.uid() i lista),
--      og activity_before_insert sjekker profil-id-ene i stedet for medlemskap.
--      push_group_map har de nye kindene under Sosialt (og bill_share_sent og
--      bill_share_disputed fra 051, som ikke endrer push_group_map selv og regner med at
--      050 lister dem). push_job_payload gir ingen collapse
--      for comment_added og mentioned (hver kommentar står, som tråden).
--   4. feed_page(klubber, før tid, før id, antall default 30): hendelser fra klubbene (null =
--      alle dine) og hendelser uten klubb i turneringer du kan lese, nyeste først, sidevis med
--      nøkkel (created_at, id). Samme regler som activity_select (også 034-grenen), og uten
--      hendelser fra noen du er blokkert mot. Per linje: reactions [{emoji, count}] (uten
--      blokkerte), my_reactions og comment_count (uten slettede og blokkerte).
--   5. Bildeoppfordring: når en vanlig runde i en klubb låses, lages én linje photo_prompt
--      (kategori social) med rundens spillere som mottakere. Unik per runde (låses runden igjen,
--      kommer ingen ny). Playoff og løse runder (uten klubb) får ingen. Gruppen Sosialt av gir
--      ingen push (046: group_off).
--   6. Moderering: content_reports.kind kan være 'comment', og content_reports.competition_id
--      (for kommentarer uten klubb). report_content tar 'comment'. resolve_report(…, 'remove')
--      sletter kommentaren mykt. Rapporter uten klubb avgjøres av turneringens arrangør.
--      delete_account_data sletter også kommentarene, reaksjonene og følgingen til kontoen.
--   7. Opprydding: når en hendelse, en melding eller en kommentar slettes, slettes reaksjonene,
--      kommentarene og følgingen på den.
--   8. Realtime: reactions og comments i supabase_realtime.
--
-- Mønsteret fra 001–049: én transaksjon, idempotent, search_path = '', revoke etter hver
-- create or replace, kontroll og rullebakke nederst.
--
-- Appen må (ikke i denne fila):
--   * Hjem: hente med feed_page i stedet for activity + activity_reactions (bla med siste
--     created_at og id), vise reactions/my_reactions/comment_count fra svaret;
--   * reaksjoner: de fem først, «+» åpner emojivelgeren; skrive med react (ikke direkte i
--     activity_reactions); lytte på reactions (Realtime) i stedet for activity_reactions;
--     reaksjoner også på meldinger i tråden og på kommentarer;
--   * kommentarer under hendelser og meldinger: lese comments (target_kind, target_id), skrive
--     med comment_add/_edit/_delete, @-velger med dem som ser innlegget, «Slettet» for rader med
--     deleted_at, «Følg tråden» med follow_thread (lese thread_follows);
--   * tekst i Hjem og Varsler for comment_added, mentioned og photo_prompt («Ta et bilde av
--     gjengen» med kamera rett i tråden);
--   * rapport på kommentar (report_content('comment', …)) og fjerning i rapportkøen.
-- push-send må: tekst for comment_added, mentioned og photo_prompt; filtrere på
--   activity.recipients også for jobber uten klubb (id-ene er da profil-id-er).

begin;


-- ===========================================================================
-- 1. HJELPERE
-- ===========================================================================
-- Én emoji («grapheme-ish»): en base med variant, hudfarge og tagger, eventuelt flere
-- koblet med ZWJ; eller et flagg (to regionale bokstaver); eller en tast (1️⃣, #️⃣).
create or replace function private.is_single_emoji(p_text text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_text is not null and char_length(p_text) between 1 and 16 and p_text ~ (
    '^(?:'
    || '[#*0-9]️?⃣'
    || '|[\U0001F1E6-\U0001F1FF]{2}'
    || '|[©®‼⁉™ℹ↔-↙↩↪⌚-⏿Ⓜ'
    ||   '▪-➿⤴⤵⬅-⭕〰〽㊗㊙'
    ||   '\U0001F000-\U0001F1E5\U0001F200-\U0001FAFF]'
    || '[️⃣\U0001F3FB-\U0001F3FF\U000E0020-\U000E007F]*'
    || '(?:‍[©®‼-㊙\U0001F000-\U0001FAFF][️\U0001F3FB-\U0001F3FF]*)*'
    || ')$');
$$;
revoke all on function private.is_single_emoji(text) from public, anon, authenticated;

-- Det faste settet fra 008 (activity_reactions.emoji). Gamle bygg kjenner bare disse.
create or replace function private.legacy_reaction_emojis()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array['👍', '😂', '⛳', '🔥', '❤️']::text[];
$$;
revoke all on function private.legacy_reaction_emojis() from public, anon, authenticated;

-- Blokkert mellom to innlogginger (begge veier). null gir false.
create or replace function private.users_blocked(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_a is not null and p_b is not null and exists (
    select 1 from public.user_blocks b
     where (b.blocker_id = p_a and b.blocked_id = p_b) or (b.blocker_id = p_b and b.blocked_id = p_a));
$$;
revoke all on function private.users_blocked(uuid, uuid) from public, anon, authenticated;

-- Innloggingen bak et medlem eller en profil.
create or replace function private.person_user(p_member_id uuid, p_profile_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(p_profile_id, (select m.user_id from public.club_members m where m.id = p_member_id));
$$;
revoke all on function private.person_user(uuid, uuid) from public, anon, authenticated;

-- Er jeg blokkert mot dette medlemmet eller denne profilen (begge veier, 019 blocked_between)?
create or replace function private.person_blocked(p_member_id uuid, p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.users_blocked(auth.uid(), private.person_user(p_member_id, p_profile_id));
$$;
revoke all on function private.person_blocked(uuid, uuid) from public, anon, authenticated;
grant execute on function private.person_blocked(uuid, uuid) to authenticated;

-- Har medlemmet minst én rettighet (044: «arrangør» i gammel betydning)?
create or replace function private.member_has_any_right(p_member_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.club_member_roles mr join public.club_roles r on r.id = mr.role_id
     where mr.member_id = p_member_id
       and (r.is_owner or r.rights && array['tournaments', 'rounds', 'members', 'money']::text[]));
$$;
revoke all on function private.member_has_any_right(uuid) from public, anon, authenticated;

-- Målet: klubb, turnering, kveld, runde, forfatter og mottakerliste. Ingen rad = finnes ikke.
create or replace function private.target_info(p_kind text, p_id uuid)
returns table (club_id uuid, competition_id uuid, event_id uuid, round_id uuid,
               author_member_id uuid, author_profile_id uuid, recipients uuid[])
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_kind = 'activity' then
    return query
    select a.club_id, a.competition_id, a.event_id, a.round_id, a.actor_member_id, null::uuid, a.recipients
      from public.activity a where a.id = p_id;
  elsif p_kind = 'message' then
    return query
    select t.club_id, e.competition_id, t.event_id, null::uuid, t.member_id, null::uuid, null::uuid[]
      from public.thread_messages t left join public.events e on e.id = t.event_id
     where t.id = p_id;
  elsif p_kind = 'comment' then
    return query
    select c.club_id, c.competition_id, null::uuid, null::uuid, c.member_id, c.profile_id, null::uuid[]
      from public.comments c where c.id = p_id and c.deleted_at is null;
  end if;
end;
$$;
revoke all on function private.target_info(text, uuid) from public, anon, authenticated;

-- Kan innloggingen se målet? Hendelser: samme uttrykk som policyen activity_select (under),
-- meldinger: som thread_messages_select. I tillegg: ikke blokkert mot forfatteren (begge
-- veier). Kommentarer: ikke slettet, og målet til kommentaren kan ses.
create or replace function private.can_read_target(p_kind text, p_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_kind text;
  v_id   uuid;
begin
  if auth.uid() is null or p_id is null then
    return false;
  end if;
  if p_kind = 'activity' then
    return exists (
      select 1 from public.activity a
       where a.id = p_id
         and (   (a.club_id is not null and public.is_club_member(a.club_id)
                  and (a.recipients is null or public.my_member_id(a.club_id) = any (a.recipients)
                       or a.actor_member_id = public.my_member_id(a.club_id)
                       or public.is_club_organizer(a.club_id))
                  and (a.round_id is null or public.can_read_round(a.round_id)))
              or (a.club_id is null and a.competition_id is not null
                  and (a.recipients is null or auth.uid() = any (a.recipients))
                  and public.can_read_competition(a.competition_id)
                  and (a.round_id is null or public.can_read_round(a.round_id))))
         and not private.person_blocked(a.actor_member_id, null));
  elsif p_kind = 'message' then
    return exists (
      select 1 from public.thread_messages t
       where t.id = p_id and public.is_club_member(t.club_id)
         and not private.person_blocked(t.member_id, null));
  elsif p_kind = 'comment' then
    select c.target_kind, c.target_id into v_kind, v_id
      from public.comments c
     where c.id = p_id and c.deleted_at is null and not private.person_blocked(c.member_id, c.profile_id);
    if not found then
      return false;
    end if;
    return private.can_read_target(v_kind, v_id);
  end if;
  return false;
end;
$$;
revoke all on function private.can_read_target(text, uuid) from public, anon, authenticated;
grant execute on function private.can_read_target(text, uuid) to authenticated;

-- Kan en ANNEN innlogging se målet? Brukes for @-omtale og mottakerne av varsler. Samme
-- regler som over, med en forenkling for runder: en runde som er kladd, ses bare av dem med
-- en rettighet i klubben. Uten klubb: de som får push i turneringen (046, eier, deltakere, stab).
create or replace function private.user_can_read_target(p_uid uuid, p_kind text, p_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_kind text;
  v_id   uuid;
begin
  if p_uid is null or p_id is null then
    return false;
  end if;
  if p_kind = 'activity' then
    return exists (
      select 1 from public.activity a
       where a.id = p_id
         and (   (a.club_id is not null and exists (
                    select 1 from public.club_members m
                     where m.club_id = a.club_id and m.user_id = p_uid and m.status = 'active'
                       and (a.recipients is null or m.id = any (a.recipients) or m.id = a.actor_member_id
                            or private.member_has_any_right(m.id))
                       and (a.round_id is null or private.member_has_any_right(m.id)
                            or exists (select 1 from public.rounds r where r.id = a.round_id and r.status <> 'draft'))))
              or (a.club_id is null and a.competition_id is not null
                  and (a.recipients is null or p_uid = any (a.recipients))
                  and exists (select 1 from private.push_competition_audience(a.competition_id) au where au.user_id = p_uid)
                  and (a.round_id is null
                       or exists (select 1 from public.rounds r where r.id = a.round_id and r.status <> 'draft'))))
         and not private.users_blocked(p_uid, private.person_user(a.actor_member_id, null)));
  elsif p_kind = 'message' then
    return exists (
      select 1 from public.thread_messages t
        join public.club_members m on m.club_id = t.club_id and m.user_id = p_uid and m.status = 'active'
       where t.id = p_id
         and not private.users_blocked(p_uid, private.person_user(t.member_id, null)));
  elsif p_kind = 'comment' then
    select c.target_kind, c.target_id into v_kind, v_id
      from public.comments c
     where c.id = p_id and c.deleted_at is null
       and not private.users_blocked(p_uid, private.person_user(c.member_id, c.profile_id));
    if not found then
      return false;
    end if;
    return private.user_can_read_target(p_uid, v_kind, v_id);
  end if;
  return false;
end;
$$;
revoke all on function private.user_can_read_target(uuid, text, uuid) from public, anon, authenticated;

-- Moderator: rettigheten money i klubben, eller arrangøren av en turnering uten klubb.
create or replace function private.can_moderate(p_club_id uuid, p_competition_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_club_id is not null then private.has_club_right(p_club_id, 'money')
    when p_competition_id is not null then public.is_competition_admin(p_competition_id)
    else false
  end;
$$;
revoke all on function private.can_moderate(uuid, uuid) from public, anon, authenticated;
grant execute on function private.can_moderate(uuid, uuid) to authenticated;


-- ===========================================================================
-- 2. REAKSJONER PÅ ALT
-- ===========================================================================
create table if not exists public.reactions (
  target_kind    text not null check (target_kind in ('activity', 'message', 'comment')),
  target_id      uuid not null,
  club_id        uuid references public.clubs (id) on delete cascade,
  competition_id uuid references public.competitions (id) on delete set null,
  member_id      uuid,
  profile_id     uuid references public.profiles (id) on delete cascade,
  person_id      uuid not null generated always as (coalesce(member_id, profile_id)) stored,
  emoji          text not null,
  created_at     timestamptz not null default now(),
  constraint reactions_pkey primary key (target_kind, target_id, person_id, emoji),
  constraint reactions_emoji_check check (private.is_single_emoji(emoji)),
  constraint reactions_one_person check (num_nonnulls(member_id, profile_id) = 1),
  constraint reactions_member_in_club check ((member_id is not null) = (club_id is not null)),
  constraint reactions_member_fk foreign key (member_id, club_id)
    references public.club_members (id, club_id) on delete cascade
);
create index if not exists reactions_member_idx on public.reactions (member_id) where member_id is not null;
create index if not exists reactions_profile_idx on public.reactions (profile_id) where profile_id is not null;
create index if not exists reactions_club_idx on public.reactions (club_id, created_at) where club_id is not null;

alter table public.reactions enable row level security;
revoke all on table public.reactions from public, anon, authenticated;
grant select on table public.reactions to authenticated;
grant all on table public.reactions to service_role;
drop policy if exists reactions_select on public.reactions;
create policy reactions_select on public.reactions
  for select to authenticated
  using (private.can_read_target(target_kind, target_id) and not private.person_blocked(member_id, profile_id));

-- Speiling: activity_reactions (gamle bygg) <-> reactions. Hver vei stopper av seg selv:
-- on conflict do nothing gir ingen ny rad (og ingen ny trigger), og sletting av en rad som
-- alt er borte, sletter ingenting.
create or replace function private.reactions_mirror_legacy()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.target_kind = 'activity' and new.member_id is not null
       and new.emoji = any (private.legacy_reaction_emojis()) then
      insert into public.activity_reactions (activity_id, member_id, club_id, emoji, created_at)
      select new.target_id, new.member_id, new.club_id, new.emoji, new.created_at
       where exists (select 1 from public.activity a where a.id = new.target_id and a.club_id = new.club_id)
      on conflict do nothing;
    end if;
    return null;
  end if;
  if old.target_kind = 'activity' and old.member_id is not null
     and old.emoji = any (private.legacy_reaction_emojis()) then
    delete from public.activity_reactions r
     where r.activity_id = old.target_id and r.member_id = old.member_id and r.emoji = old.emoji;
  end if;
  return null;
end;
$$;
revoke all on function private.reactions_mirror_legacy() from public, anon, authenticated;

drop trigger if exists reactions_mirror_legacy on public.reactions;
create trigger reactions_mirror_legacy
  after insert or delete on public.reactions
  for each row execute function private.reactions_mirror_legacy();

create or replace function private.activity_reactions_mirror()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.reactions (target_kind, target_id, club_id, competition_id, member_id, emoji, created_at)
    select 'activity', new.activity_id, new.club_id, a.competition_id, new.member_id, new.emoji, new.created_at
      from public.activity a where a.id = new.activity_id
    on conflict do nothing;
    return null;
  end if;
  delete from public.reactions r
   where r.target_kind = 'activity' and r.target_id = old.activity_id
     and r.member_id = old.member_id and r.emoji = old.emoji;
  return null;
end;
$$;
revoke all on function private.activity_reactions_mirror() from public, anon, authenticated;

drop trigger if exists activity_reactions_mirror on public.activity_reactions;
create trigger activity_reactions_mirror
  after insert or delete on public.activity_reactions
  for each row execute function private.activity_reactions_mirror();

-- Det som alt finnes.
insert into public.reactions (target_kind, target_id, club_id, competition_id, member_id, emoji, created_at)
select 'activity', r.activity_id, r.club_id, a.competition_id, r.member_id, r.emoji, r.created_at
  from public.activity_reactions r join public.activity a on a.id = r.activity_id
on conflict do nothing;

-- Gamle bygg: innlegging krever i tillegg at du ser hendelsen (og ikke er blokkert mot den
-- som gjorde den). Lesing og sletting er som i 019.
drop policy if exists activity_reactions_insert on public.activity_reactions;
create policy activity_reactions_insert on public.activity_reactions
  for insert to authenticated
  with check (public.owns_member(member_id) and private.can_read_target('activity', activity_id));

-- Reager (p_on = true) eller ta bort reaksjonen. Svarer p_on.
create or replace function public.react(p_kind text, p_id uuid, p_emoji text, p_on boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := auth.uid();
  v_t      record;
  v_member uuid;
  v_n      integer;
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if p_kind is null or p_kind not in ('activity', 'message', 'comment') then
    raise exception 'Ukjent type innhold' using errcode = '22023';
  end if;
  if p_on is null then
    raise exception 'Velg på eller av' using errcode = '22023';
  end if;
  if p_on and not private.is_single_emoji(p_emoji) then
    raise exception 'Reaksjonen må være én emoji' using errcode = '22023';
  end if;
  select * into v_t from private.target_info(p_kind, p_id) limit 1;
  if not found or not private.can_read_target(p_kind, p_id) then
    raise exception 'Fant ikke innholdet' using errcode = 'P0002';
  end if;
  if v_t.club_id is not null then
    v_member := public.my_member_id(v_t.club_id);
    if v_member is null then
      raise exception 'Du er ikke med i klubben' using errcode = '42501';
    end if;
  end if;

  if not p_on then
    delete from public.reactions r
     where r.target_kind = p_kind and r.target_id = p_id
       and r.person_id = coalesce(v_member, v_uid) and r.emoji = p_emoji;
    return false;
  end if;

  select count(*) into v_n from public.reactions r
   where r.target_kind = p_kind and r.target_id = p_id and r.person_id = coalesce(v_member, v_uid)
     and r.emoji <> p_emoji;
  if v_n >= 20 then
    raise exception 'Høyst 20 forskjellige reaksjoner' using errcode = '22023';
  end if;
  insert into public.reactions (target_kind, target_id, club_id, competition_id, member_id, profile_id, emoji)
  values (p_kind, p_id, v_t.club_id, v_t.competition_id, v_member,
          case when v_member is null then v_uid end, p_emoji)
  on conflict do nothing;
  return true;
end;
$$;
revoke all on function public.react(text, uuid, text, boolean) from public, anon;
grant execute on function public.react(text, uuid, text, boolean) to authenticated;


-- ===========================================================================
-- 3. KOMMENTARER
-- ===========================================================================
create table if not exists public.comments (
  id             uuid primary key default gen_random_uuid(),
  club_id        uuid references public.clubs (id) on delete cascade,
  competition_id uuid references public.competitions (id) on delete set null,
  target_kind    text not null check (target_kind in ('activity', 'message')),
  target_id      uuid not null,
  member_id      uuid,
  profile_id     uuid references public.profiles (id) on delete cascade,
  body           text not null,
  mentions       uuid[] not null default '{}',
  created_at     timestamptz not null default now(),
  edited_at      timestamptz,
  deleted_at     timestamptz,
  deleted_by     uuid references public.profiles (id) on delete set null,
  constraint comments_body_check check (
    char_length(body) <= 1000
    and (case when deleted_at is null then char_length(btrim(body)) >= 1 else body = '' end)),
  constraint comments_mentions_check check (cardinality(mentions) <= 50),
  constraint comments_one_author check (num_nonnulls(member_id, profile_id) = 1),
  constraint comments_member_in_club check ((member_id is not null) = (club_id is not null)),
  constraint comments_member_fk foreign key (member_id, club_id)
    references public.club_members (id, club_id) on delete cascade
);
create index if not exists comments_target_idx on public.comments (target_kind, target_id, created_at);
create index if not exists comments_member_idx on public.comments (member_id, created_at) where member_id is not null;
create index if not exists comments_profile_idx on public.comments (profile_id, created_at) where profile_id is not null;

alter table public.comments enable row level security;
revoke all on table public.comments from public, anon, authenticated;
grant select on table public.comments to authenticated;
grant all on table public.comments to service_role;
drop policy if exists comments_select on public.comments;
create policy comments_select on public.comments
  for select to authenticated
  using (private.can_read_target(target_kind, target_id) and not private.person_blocked(member_id, profile_id));


-- ===========================================================================
-- 4. «FØLG TRÅDEN» OG VARSLENE
-- ===========================================================================
create table if not exists public.thread_follows (
  user_id     uuid not null references auth.users (id) on delete cascade,
  target_kind text not null check (target_kind in ('activity', 'message')),
  target_id   uuid not null,
  following   boolean not null default true,
  created_at  timestamptz not null default now(),
  primary key (user_id, target_kind, target_id)
);
create index if not exists thread_follows_target_idx on public.thread_follows (target_kind, target_id) where following;
alter table public.thread_follows enable row level security;
revoke all on table public.thread_follows from public, anon, authenticated;
grant select on table public.thread_follows to authenticated;
grant all on table public.thread_follows to service_role;
drop policy if exists thread_follows_select on public.thread_follows;
create policy thread_follows_select on public.thread_follows
  for select to authenticated using (user_id = (select auth.uid()));

create or replace function public.follow_thread(p_kind text, p_id uuid, p_on boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if p_kind is null or p_kind not in ('activity', 'message') or p_on is null then
    raise exception 'Ukjent tråd eller valg' using errcode = '22023';
  end if;
  if not private.can_read_target(p_kind, p_id) then
    raise exception 'Fant ikke innholdet' using errcode = 'P0002';
  end if;
  insert into public.thread_follows (user_id, target_kind, target_id, following)
  values (auth.uid(), p_kind, p_id, p_on)
  on conflict (user_id, target_kind, target_id) do update set following = excluded.following;
  return p_on;
end;
$$;
revoke all on function public.follow_thread(text, uuid, boolean) from public, anon;
grant execute on function public.follow_thread(text, uuid, boolean) to authenticated;

-- @-omtale: medlems-id-er i klubben eller profil-id-er uten klubb. Den som skriver tas bort.
-- Alle andre må finnes, se målet og ikke være blokkert mot den som skriver.
create or replace function private.valid_mentions(p_kind text, p_id uuid, p_club_id uuid,
                                                  p_mentions uuid[], p_author_uid uuid)
returns uuid[]
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_ids  uuid[];
  v_out  uuid[] := '{}';
  v_id   uuid;
  v_user uuid;
begin
  select coalesce(array_agg(distinct x), '{}') into v_ids from unnest(coalesce(p_mentions, '{}')) x where x is not null;
  if cardinality(v_ids) > 50 then
    raise exception 'Høyst 50 omtaler' using errcode = '22023';
  end if;
  foreach v_id in array v_ids loop
    if p_club_id is not null then
      select m.user_id into v_user from public.club_members m
       where m.id = v_id and m.club_id = p_club_id and m.status = 'active';
    else
      select p.id into v_user from public.profiles p where p.id = v_id;
    end if;
    if v_user is not null and v_user = p_author_uid then
      continue;
    end if;
    if v_user is null or not private.user_can_read_target(v_user, p_kind, p_id)
       or private.users_blocked(v_user, p_author_uid) then
      raise exception 'Du kan bare nevne noen som ser innlegget' using errcode = '22023';
    end if;
    v_out := v_out || v_id;
  end loop;
  return v_out;
end;
$$;
revoke all on function private.valid_mentions(text, uuid, uuid, uuid[], uuid) from public, anon, authenticated;

-- Varslene for en kommentar: comment_added (p_comment) og mentioned (p_mentions).
create or replace function private.comment_notify(p_comment public.comments, p_mentions uuid[], p_new_comment boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prev    text := current_setting('dd18.server_activity', true);
  v_t       record;
  v_author  uuid := private.person_user(p_comment.member_id, p_comment.profile_id);
  v_name    text;
  v_mention_users uuid[];
  v_users   uuid[];
  v_recips  uuid[];
  v_data    jsonb;
begin
  select * into v_t from private.target_info(p_comment.target_kind, p_comment.target_id) limit 1;
  if not found then
    return;
  end if;
  if p_comment.member_id is not null then
    select m.display_name into v_name from public.club_members m where m.id = p_comment.member_id;
  else
    select p.display_name into v_name from public.profiles p where p.id = p_comment.profile_id;
  end if;
  v_data := jsonb_strip_nulls(jsonb_build_object(
    'target_kind', p_comment.target_kind, 'target_id', p_comment.target_id,
    'comment_id', p_comment.id, 'preview', left(p_comment.body, 140), 'author_name', v_name,
    'author_profile', p_comment.profile_id));

  select coalesce(array_agg(private.person_user(case when p_comment.club_id is not null then x end,
                                                 case when p_comment.club_id is null then x end)), '{}')
    into v_mention_users from unnest(coalesce(p_mentions, '{}')) x;

  perform set_config('dd18.server_activity', 'on', true);

  if p_new_comment then
    -- Forfatteren av målet (uten å følge, men ikke om hen har slått tråden av) og de som følger.
    select coalesce(array_agg(distinct u), '{}') into v_users
      from (
        select private.person_user(v_t.author_member_id, v_t.author_profile_id) as u
         where not exists (select 1 from public.thread_follows f
                            where f.target_kind = p_comment.target_kind and f.target_id = p_comment.target_id
                              and f.user_id = private.person_user(v_t.author_member_id, v_t.author_profile_id)
                              and not f.following)
        union
        select f.user_id from public.thread_follows f
         where f.target_kind = p_comment.target_kind and f.target_id = p_comment.target_id and f.following
      ) x
     where u is not null and u <> v_author and not (u = any (v_mention_users))
       and not private.users_blocked(u, v_author)
       and private.user_can_read_target(u, p_comment.target_kind, p_comment.target_id);

    if p_comment.club_id is not null then
      select coalesce(array_agg(m.id order by m.id), '{}') into v_recips
        from public.club_members m
       where m.club_id = p_comment.club_id and m.status = 'active' and m.user_id = any (v_users);
    else
      select coalesce(array_agg(u order by u), '{}') into v_recips from unnest(v_users) u;
    end if;

    if cardinality(v_recips) > 0 then
      insert into public.activity (club_id, competition_id, kind, category, data, actor_member_id,
                                   event_id, round_id, recipients)
      values (p_comment.club_id, v_t.competition_id, 'comment_added', 'social', v_data,
              p_comment.member_id, v_t.event_id, v_t.round_id, v_recips[1:200]);
    end if;
  end if;

  if cardinality(coalesce(p_mentions, '{}')) > 0 then
    insert into public.activity (club_id, competition_id, kind, category, data, actor_member_id,
                                 event_id, round_id, recipients)
    values (p_comment.club_id, v_t.competition_id, 'mentioned', 'social', v_data,
            p_comment.member_id, v_t.event_id, v_t.round_id, p_mentions);
  end if;

  perform set_config('dd18.server_activity', coalesce(v_prev, ''), true);
end;
$$;
revoke all on function private.comment_notify(public.comments, uuid[], boolean) from public, anon, authenticated;

create or replace function public.comment_add(p_kind text, p_id uuid, p_body text,
                                              p_mentions uuid[] default '{}', p_follow boolean default true)
returns public.comments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := auth.uid();
  v_body     text := btrim(p_body);
  v_t        record;
  v_member   uuid;
  v_mentions uuid[];
  v_n        integer;
  v_row      public.comments;
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if p_kind is null or p_kind not in ('activity', 'message') then
    raise exception 'Bare hendelser og meldinger kan kommenteres' using errcode = '22023';
  end if;
  if v_body is null or char_length(v_body) < 1 or char_length(v_body) > 1000 then
    raise exception 'Kommentaren må ha 1–1000 tegn' using errcode = '22023';
  end if;
  select * into v_t from private.target_info(p_kind, p_id) limit 1;
  if not found or not private.can_read_target(p_kind, p_id) then
    raise exception 'Fant ikke innholdet' using errcode = 'P0002';
  end if;
  if v_t.club_id is not null then
    v_member := public.my_member_id(v_t.club_id);
    if v_member is null then
      raise exception 'Du er ikke med i klubben' using errcode = '42501';
    end if;
  elsif v_t.competition_id is null then
    raise exception 'Fant ikke innholdet' using errcode = 'P0002';
  end if;

  select count(*) into v_n from public.comments c
   where (c.member_id = v_member or c.profile_id = v_uid) and c.created_at > now() - interval '10 minutes';
  if v_n >= 60 then
    raise exception 'Grensen er nådd: høyst 60 kommentarer på ti minutter. Prøv igjen senere.'
      using errcode = '54000';
  end if;

  v_mentions := private.valid_mentions(p_kind, p_id, v_t.club_id, p_mentions, v_uid);

  insert into public.comments (club_id, competition_id, target_kind, target_id, member_id, profile_id,
                               body, mentions)
  values (v_t.club_id, v_t.competition_id, p_kind, p_id, v_member,
          case when v_member is null then v_uid end, v_body, v_mentions)
  returning * into v_row;

  if coalesce(p_follow, true) then
    insert into public.thread_follows (user_id, target_kind, target_id, following)
    values (v_uid, p_kind, p_id, true)
    on conflict do nothing;
  end if;

  perform private.comment_notify(v_row, v_mentions, true);
  return v_row;
end;
$$;
revoke all on function public.comment_add(text, uuid, text, uuid[], boolean) from public, anon;
grant execute on function public.comment_add(text, uuid, text, uuid[], boolean) to authenticated;

-- Bare forfatteren. p_mentions null = uendret. Nye omtaler får mentioned.
create or replace function public.comment_edit(p_id uuid, p_body text, p_mentions uuid[] default null)
returns public.comments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := auth.uid();
  v_body     text := btrim(p_body);
  v_row      public.comments;
  v_mentions uuid[];
  v_added    uuid[];
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select * into v_row from public.comments c where c.id = p_id for update;
  if not found or v_row.deleted_at is not null or not private.can_read_target(v_row.target_kind, v_row.target_id) then
    raise exception 'Fant ikke kommentaren' using errcode = 'P0002';
  end if;
  if private.person_user(v_row.member_id, v_row.profile_id) is distinct from v_uid
     or (v_row.member_id is not null and not public.owns_member(v_row.member_id)) then
    raise exception 'Bare den som skrev kan endre kommentaren' using errcode = '42501';
  end if;
  if v_body is null or char_length(v_body) < 1 or char_length(v_body) > 1000 then
    raise exception 'Kommentaren må ha 1–1000 tegn' using errcode = '22023';
  end if;
  if p_mentions is null then
    v_mentions := v_row.mentions;
  else
    v_mentions := private.valid_mentions(v_row.target_kind, v_row.target_id, v_row.club_id, p_mentions, v_uid);
  end if;
  select coalesce(array_agg(x), '{}') into v_added from unnest(v_mentions) x where not (x = any (v_row.mentions));

  update public.comments c set body = v_body, mentions = v_mentions, edited_at = now()
   where c.id = p_id returning * into v_row;
  if cardinality(v_added) > 0 then
    perform private.comment_notify(v_row, v_added, false);
  end if;
  return v_row;
end;
$$;
revoke all on function public.comment_edit(uuid, text, uuid[]) from public, anon;
grant execute on function public.comment_edit(uuid, text, uuid[]) to authenticated;

-- Myk sletting: raden står, teksten og omtalene tømmes, reaksjonene på den slettes.
create or replace function private.comment_soft_delete(p_id uuid, p_by uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.comments c
     set deleted_at = now(), deleted_by = p_by, body = '', mentions = '{}'
   where c.id = p_id and c.deleted_at is null;
  if not found then
    return false;
  end if;
  delete from public.reactions r where r.target_kind = 'comment' and r.target_id = p_id;
  return true;
end;
$$;
revoke all on function private.comment_soft_delete(uuid, uuid) from public, anon, authenticated;

-- Forfatteren, eller moderator (money i klubben, arrangøren uten klubb). Svarer om noe ble slettet.
create or replace function public.comment_delete(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.comments;
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select * into v_row from public.comments c where c.id = p_id for update;
  if not found then
    raise exception 'Fant ikke kommentaren' using errcode = 'P0002';
  end if;
  if not (   (private.person_user(v_row.member_id, v_row.profile_id) = v_uid
              and (v_row.member_id is null or public.owns_member(v_row.member_id)))
          or private.can_moderate(v_row.club_id, v_row.competition_id)) then
    if private.can_read_target(v_row.target_kind, v_row.target_id) then
      raise exception 'Bare den som skrev, eller en moderator, kan slette kommentaren' using errcode = '42501';
    end if;
    raise exception 'Fant ikke kommentaren' using errcode = 'P0002';
  end if;
  return private.comment_soft_delete(p_id, v_uid);
end;
$$;
revoke all on function public.comment_delete(uuid) from public, anon;
grant execute on function public.comment_delete(uuid) to authenticated;


-- ===========================================================================
-- 5. ACTIVITY: MOTTAKERE UTEN KLUBB, BILDEOPPFORDRING, OPPRYDDING
-- ===========================================================================
-- Fra 008/045. Nytt: uten klubb er mottakerlisten profil-id-er (sjekkes mot profiles).
create or replace function public.activity_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.club_id is not null then
    new.recipients := public.clean_member_list(new.recipients, new.club_id);
  elsif new.recipients is not null then
    select coalesce(array_agg(distinct u), '{}') into new.recipients
      from unnest(new.recipients) u where u is not null;
    if exists (select 1 from unnest(new.recipients) u
                where not exists (select 1 from public.profiles p where p.id = u)) then
      raise exception 'Lista har noen som ikke finnes' using errcode = '23503';
    end if;
  end if;

  if auth.uid() is null then
    return new;
  end if;
  -- 045: laget av serveren (opprykk, avmelding): aktøren og mottakerne er satt av funksjonen.
  if coalesce(current_setting('dd18.server_activity', true), '') = 'on' then
    return new;
  end if;

  new.actor_member_id := public.my_member_id(new.club_id);
  new.created_at := now();

  if (new.category in ('announcement', 'nudge', 'reminder') or new.recipients is not null)
     and not public.is_club_organizer(new.club_id) then
    raise exception 'Bare arrangøren kan sende til alle, purre eller velge mottakere'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function public.activity_before_insert() from public, anon, authenticated;

-- Fra 034. Nytt: hendelser uten klubb med mottakerliste ses av mottakerne (profil-id).
drop policy if exists activity_select on public.activity;
create policy activity_select on public.activity
  for select to authenticated
  using (
    (club_id is not null and public.is_club_member(club_id)
     and (recipients is null or public.my_member_id(club_id) = any (recipients)
          or actor_member_id = public.my_member_id(club_id) or public.is_club_organizer(club_id))
     and (round_id is null or public.can_read_round(round_id)))
    or (club_id is null and competition_id is not null
        and (recipients is null or (select auth.uid()) = any (recipients))
        and public.can_read_competition(competition_id)
        and (round_id is null or public.can_read_round(round_id))));

-- Bildeoppfordring: én per runde.
create unique index if not exists activity_photo_prompt_once
  on public.activity (round_id) where kind = 'photo_prompt';

create or replace function private.rounds_photo_prompt()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prev    text := current_setting('dd18.server_activity', true);
  v_players uuid[];
  v_date    date;
  v_course  text;
begin
  if new.status <> 'locked' or old.status = 'locked' or new.kind <> 'normal' or new.club_id is null then
    return null;
  end if;
  select coalesce(array_agg(p.member_id order by p.member_id), '{}') into v_players
    from public.round_players p
    join public.club_members m on m.id = p.member_id and m.club_id = new.club_id and m.status = 'active'
   where p.round_id = new.id;
  if cardinality(v_players) = 0 then
    return null;
  end if;
  select e.event_date into v_date from public.events e where e.id = new.event_id;
  select c.name into v_course from public.courses c where c.id = new.course_id;

  perform set_config('dd18.server_activity', 'on', true);
  insert into public.activity (club_id, kind, category, data, actor_member_id, event_id, round_id, recipients)
  values (new.club_id, 'photo_prompt', 'social',
          jsonb_strip_nulls(jsonb_build_object(
            'event_date', to_char(v_date, 'YYYY-MM-DD'),
            'round_no', new.round_no,
            'course_name', v_course)),
          null, new.event_id, new.id, v_players[1:200])
  on conflict (round_id) where kind = 'photo_prompt' do nothing;
  perform set_config('dd18.server_activity', coalesce(v_prev, ''), true);
  return null;
end;
$$;
revoke all on function private.rounds_photo_prompt() from public, anon, authenticated;

drop trigger if exists rounds_photo_prompt on public.rounds;
create trigger rounds_photo_prompt
  after update of status on public.rounds
  for each row
  when (new.status = 'locked')
  execute function private.rounds_photo_prompt();

-- Opprydding når en hendelse, melding eller kommentar slettes.
create or replace function private.social_cleanup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kind text := case tg_table_name when 'activity' then 'activity'
                                    when 'thread_messages' then 'message'
                                    else 'comment' end;
begin
  delete from public.reactions r where r.target_kind = v_kind and r.target_id = old.id;
  if v_kind <> 'comment' then
    delete from public.comments c where c.target_kind = v_kind and c.target_id = old.id;
    delete from public.thread_follows f where f.target_kind = v_kind and f.target_id = old.id;
  end if;
  return null;
end;
$$;
revoke all on function private.social_cleanup() from public, anon, authenticated;

drop trigger if exists activity_social_cleanup on public.activity;
create trigger activity_social_cleanup
  after delete on public.activity for each row execute function private.social_cleanup();
drop trigger if exists thread_messages_social_cleanup on public.thread_messages;
create trigger thread_messages_social_cleanup
  after delete on public.thread_messages for each row execute function private.social_cleanup();
drop trigger if exists comments_social_cleanup on public.comments;
create trigger comments_social_cleanup
  after delete on public.comments for each row execute function private.social_cleanup();


-- ===========================================================================
-- 6. PUSH: GRUPPEN SOSIALT
-- ===========================================================================
-- Fra 046, med comment_added, mentioned og photo_prompt (kategori social → Sosialt).
create or replace function public.push_group_map()
returns table (group_key text, category text, kind text)
language sql
immutable
set search_path = ''
as $$
  select public.push_group(m.category, m.kind), m.category, m.kind
  from (values
    ('round', 'round_started'), ('round', 'round_locked'), ('round', 'round_deleted'),
    ('round', 'table_changed'), ('round', 'evening_started'),
    ('score', 'big_score'), ('lead', 'lead_changed'), ('side_prize', 'side_prize'),
    ('setup', 'score_corrected'),
    ('signup', 'signup'), ('signup', 'waitlist_promoted'), ('signup', 'signup_dropped'),
    ('nudge', 'nudge'), ('reminder', 'reminder'), ('announcement', 'announcement'),
    ('social', 'committee_drawn'), ('club', 'member_joined'), ('tips', 'tips_king'),
    ('bet', 'bet_created'), ('bet', 'bet_challenge'), ('bet', 'bet_resolved'),
    ('thread', 'thread_message'),
    ('social', 'comment_added'), ('social', 'mentioned'), ('social', 'photo_prompt'),
    ('social', 'bill_share_sent'), ('social', 'bill_share_disputed')
  ) as m (category, kind)
  order by 1, 2, 3;
$$;
revoke all on function public.push_group_map() from public, anon;
grant execute on function public.push_group_map() to authenticated, service_role;

-- Fra 046. Eneste endring: ingen collapse for comment_added og mentioned.
create or replace function public.push_job_payload(p_job_id bigint)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with q as (
    select * from public.push_queue where id = p_job_id
  ),
  a as (
    select a.* from public.activity a join q on a.id = q.activity_id
  ),
  t as (
    select t.* from public.thread_messages t join q on t.id = q.thread_message_id
  ),
  ctx as (
    select q.id as job_id,
           q.club_id,
           coalesce(q.competition_id, (select a.competition_id from a)) as competition_id,
           coalesce((select a.event_id from a),
                    (select r.event_id from a join public.rounds r on r.id = a.round_id),
                    (select t.event_id from t)) as event_id,
           case when q.activity_id is not null then (select a.category from a) else 'thread' end as category,
           case when q.activity_id is not null
                then public.push_group((select a.category from a), (select a.kind from a))
                else 'social' end as grp
      from q
  ),
  club_aud as (
    select m.id, m.user_id, m.display_name, m.is_organizer,
           (m.status = 'active' and m.user_id is not null) as active,
           (m.status = 'active') as may_have_devices,
           coalesce(p.disabled_categories, '{}'::text[]) as disabled_categories,
           coalesce(p.thread_mode, 'mentions') as thread_mode,
           coalesce(p.disabled_groups, '{}'::text[]) as disabled_groups,
           coalesce(p.email_fallback, true) as email_fallback
      from ctx
      join public.club_members m on m.club_id = ctx.club_id
      left join public.push_preferences p on p.member_id = m.id
  ),
  comp_aud as (
    select ca.user_id as id, ca.user_id,
           coalesce(pr.display_name, 'Noen') as display_name,
           ca.is_organizer,
           true as active,
           true as may_have_devices,
           coalesce((select array_agg(distinct c order by c)
                       from public.club_members m
                       join public.push_preferences p on p.member_id = m.id,
                            unnest(p.disabled_categories) c
                      where m.user_id = ca.user_id and m.status = 'active'), '{}'::text[]) as disabled_categories,
           'mentions'::text as thread_mode,
           coalesce((select array_agg(distinct g order by g)
                       from public.club_members m
                       join public.push_preferences p on p.member_id = m.id,
                            unnest(p.disabled_groups) g
                      where m.user_id = ca.user_id and m.status = 'active'), '{}'::text[]) as disabled_groups,
           coalesce((select bool_and(p.email_fallback)
                       from public.club_members m
                       join public.push_preferences p on p.member_id = m.id
                      where m.user_id = ca.user_id and m.status = 'active'), true) as email_fallback
      from ctx
      cross join lateral private.push_competition_audience(ctx.competition_id) ca
      left join public.profiles pr on pr.id = ca.user_id
     where ctx.club_id is null
  ),
  aud as (
    select x.*,
           (ctx.category <> 'announcement' and ctx.event_id is not null and x.user_id is not null
            and exists (select 1 from public.push_event_mutes mu
                         where mu.user_id = x.user_id and mu.event_id = ctx.event_id)) as muted,
           (ctx.category <> 'announcement' and ctx.grp = any (x.disabled_groups)) as group_off
      from (select * from club_aud union all select * from comp_aud) x, ctx
  )
  select jsonb_build_object(
    'job_id', q.id,
    'kind', case when q.activity_id is not null then 'activity' else 'thread' end,
    'club', case
      when c.id is not null then jsonb_build_object(
        'id', c.id,
        'name', c.name,
        'disabled_categories', to_jsonb(c.push_disabled_categories))
      else jsonb_build_object('id', null, 'name', co.name, 'disabled_categories', '[]'::jsonb)
    end,
    'activity', (
      select jsonb_build_object(
        'id', a.id, 'kind', a.kind, 'category', a.category, 'data', a.data,
        'actor_member_id', a.actor_member_id, 'event_id', a.event_id,
        'round_id', a.round_id, 'recipients', to_jsonb(a.recipients),
        'created_at', a.created_at,
        'round_status', (select r.status from public.rounds r where r.id = a.round_id))
      from a
    ),
    'message', (
      select jsonb_build_object(
        'id', t.id, 'event_id', t.event_id, 'member_id', t.member_id,
        'body', t.body, 'mentions', to_jsonb(t.mentions),
        'has_image', t.image_path is not null, 'created_at', t.created_at,
        'pushed_at', t.pushed_at,
        'event_date', (select e.event_date from public.events e where e.id = t.event_id))
      from t
    ),
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id,
        'display_name', m.display_name,
        'is_organizer', m.is_organizer,
        'active', m.active,
        'disabled_categories', to_jsonb(m.disabled_categories),
        'thread_mode', m.thread_mode,
        'devices', case when m.muted or m.group_off then '[]'::jsonb else coalesce((
          select jsonb_agg(jsonb_build_object(
                   'token', d.token, 'environment', d.environment, 'bundle_id', d.bundle_id)
                 order by d.device_id)
          from public.push_devices d
          where m.may_have_devices and d.user_id = m.user_id
        ), '[]'::jsonb) end,
        'user_id', m.user_id,
        'disabled_groups', to_jsonb(m.disabled_groups),
        'email_fallback', m.email_fallback,
        'muted', m.muted,
        'group_off', m.group_off
      ) order by m.id)
      from aud m
    ), '[]'::jsonb),
    'group', ctx.grp,
    'event_id', ctx.event_id,
    'collapse', case when q.activity_id is not null and ctx.event_id is not null and ctx.grp is not null
                      and coalesce((select a.kind from a), '') not in ('comment_added', 'mentioned')
                     then 'event-' || ctx.event_id || '-' || ctx.grp end,
    'competition', case when co.id is not null then jsonb_build_object('id', co.id, 'name', co.name) end,
    'audience', case when q.club_id is not null then 'club' else 'competition' end
  )
  from q
  cross join ctx
  left join public.clubs c on c.id = q.club_id
  left join public.competitions co on co.id = ctx.competition_id;
$$;
revoke all on function public.push_job_payload(bigint) from public, anon, authenticated;
grant execute on function public.push_job_payload(bigint) to service_role;


-- ===========================================================================
-- 7. FEED MED SIDER
-- ===========================================================================
-- Nøkkel (created_at, id), nyeste først. p_before_ts null = første side. p_before_id null med
-- en tid = alt som er eldre enn tiden. p_limit 1–100 (default 30).
create or replace function public.feed_page(p_club_ids uuid[], p_before_ts timestamptz default null,
                                            p_before_id uuid default null, p_limit integer default 30)
returns table (id uuid, club_id uuid, competition_id uuid, kind text, category text, data jsonb,
               actor_member_id uuid, event_id uuid, round_id uuid, recipients uuid[],
               created_at timestamptz, reactions jsonb, my_reactions text[], comment_count integer)
language sql
stable
security definer
set search_path = ''
as $$
  with lim as (
    select least(greatest(coalesce(p_limit, 30), 1), 100) as n,
           coalesce(p_before_id, '00000000-0000-0000-0000-000000000000'::uuid) as before_id
  ),
  blocked as (
    select b.blocked_id as uid from public.user_blocks b where b.blocker_id = auth.uid()
    union
    select b.blocker_id from public.user_blocks b where b.blocked_id = auth.uid()
  ),
  mine as (
    select c.id as club_id, public.my_member_id(c.id) as member_id, public.is_club_organizer(c.id) as organizer
      from (select distinct x from unnest(coalesce(p_club_ids,
              (select array_agg(m.club_id) from public.club_members m
                where m.user_id = auth.uid() and m.status = 'active'))) x) as c(id)
     where public.is_club_member(c.id)
  ),
  cand as (
    select a.* from mine cross join lateral (
      select a.* from public.activity a, lim
       where a.club_id = mine.club_id
         and (p_before_ts is null or (a.created_at, a.id) < (p_before_ts, lim.before_id))
         and (a.recipients is null or mine.member_id = any (a.recipients)
              or a.actor_member_id = mine.member_id or mine.organizer)
         and (a.round_id is null or public.can_read_round(a.round_id))
         and not exists (select 1 from public.club_members am join blocked on blocked.uid = am.user_id
                          where am.id = a.actor_member_id)
       order by a.created_at desc, a.id desc
       limit (select n from lim)) a
    union all
    select a.* from unnest(public.my_competition_ids()) as comp(id) cross join lateral (
      select a.* from public.activity a, lim
       where a.club_id is null and a.competition_id = comp.id
         and (p_before_ts is null or (a.created_at, a.id) < (p_before_ts, lim.before_id))
         and (a.recipients is null or auth.uid() = any (a.recipients))
         and (a.round_id is null or public.can_read_round(a.round_id))
       order by a.created_at desc, a.id desc
       limit (select n from lim)) a
  ),
  page as (
    select * from cand order by created_at desc, id desc limit (select n from lim)
  )
  select p.id, p.club_id, p.competition_id, p.kind, p.category, p.data, p.actor_member_id,
         p.event_id, p.round_id, p.recipients, p.created_at,
         coalesce((
           select jsonb_agg(jsonb_build_object('emoji', x.emoji, 'count', x.n) order by x.n desc, x.first, x.emoji)
             from (select r.emoji, count(*) as n, min(r.created_at) as first
                     from public.reactions r
                     left join public.club_members rm on rm.id = r.member_id
                    where r.target_kind = 'activity' and r.target_id = p.id
                      and not exists (select 1 from blocked where blocked.uid = coalesce(r.profile_id, rm.user_id))
                    group by r.emoji) x), '[]'::jsonb),
         coalesce((
           select array_agg(r.emoji order by r.created_at, r.emoji)
             from public.reactions r
            where r.target_kind = 'activity' and r.target_id = p.id
              and r.person_id = coalesce(public.my_member_id(p.club_id), auth.uid())), '{}'::text[]),
         (select count(*)::integer
            from public.comments c
            left join public.club_members cm on cm.id = c.member_id
           where c.target_kind = 'activity' and c.target_id = p.id and c.deleted_at is null
             and not exists (select 1 from blocked where blocked.uid = coalesce(c.profile_id, cm.user_id)))
    from page p
   order by p.created_at desc, p.id desc;
$$;
revoke all on function public.feed_page(uuid[], timestamptz, uuid, integer) from public, anon;
grant execute on function public.feed_page(uuid[], timestamptz, uuid, integer) to authenticated;


-- ===========================================================================
-- 8. MODERERING
-- ===========================================================================
alter table public.content_reports
  add column if not exists competition_id uuid references public.competitions (id) on delete cascade;
alter table public.content_reports drop constraint if exists content_reports_kind_check;
alter table public.content_reports add constraint content_reports_kind_check
  check (kind in ('message', 'image', 'member', 'profile', 'comment'));

drop policy if exists content_reports_select on public.content_reports;
create policy content_reports_select on public.content_reports
  for select to authenticated
  using (reporter_id = (select auth.uid())
         or (club_id is not null and private.has_club_right(club_id, 'money'))
         or (club_id is null and competition_id is not null and public.is_competition_admin(competition_id)));

-- Fra 019. Nytt: 'comment' (med turneringen når kommentaren ikke har klubb).
create or replace function public.report_content(p_kind text, p_target_id uuid, p_reason text, p_note text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid := auth.uid();
  v_club      uuid;
  v_comp      uuid;
  v_author    uuid;
  v_snapshot  text;
  v_id        uuid;
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if p_kind is null or p_kind not in ('message', 'image', 'member', 'profile', 'comment') then
    raise exception 'Ukjent type innhold' using errcode = '22023';
  end if;
  if p_reason is null or p_reason not in ('offensive', 'harassment', 'spam', 'inappropriate_image',
                                          'impersonation', 'other') then
    raise exception 'Ukjent grunn' using errcode = '22023';
  end if;
  if p_note is not null and char_length(p_note) > 500 then
    raise exception 'Kommentaren kan være høyst 500 tegn' using errcode = '22023';
  end if;

  if p_kind in ('message', 'image') then
    select t.club_id, m.user_id,
           case when p_kind = 'image' then t.image_path else left(t.body, 600) end
      into v_club, v_author, v_snapshot
    from public.thread_messages t
    join public.club_members m on m.id = t.member_id
    where t.id = p_target_id and public.is_club_member(t.club_id)
      and (p_kind = 'message' or t.image_path is not null);
  elsif p_kind = 'member' then
    select m.club_id, m.user_id, left(m.display_name, 600) into v_club, v_author, v_snapshot
    from public.club_members m
    where m.id = p_target_id and public.is_club_member(m.club_id);
  elsif p_kind = 'comment' then
    select c.club_id, case when c.club_id is null then c.competition_id end,
           private.person_user(c.member_id, c.profile_id), left(c.body, 600)
      into v_club, v_comp, v_author, v_snapshot
    from public.comments c
    where c.id = p_target_id and private.can_read_target('comment', c.id);
  else
    select null, p.id, left(p.display_name, 600) into v_club, v_author, v_snapshot
    from public.profiles p
    where p.id = p_target_id and p.id <> v_uid and public.can_see_profile(p.id);
  end if;
  if not found then
    raise exception 'Fant ikke innholdet' using errcode = 'P0002';
  end if;

  insert into public.content_reports (reporter_id, kind, target_id, club_id, competition_id,
                                      target_profile_id, reason, note, snapshot)
  values (v_uid, p_kind, p_target_id, v_club, v_comp, v_author, p_reason, nullif(btrim(p_note), ''), v_snapshot)
  on conflict (reporter_id, kind, target_id) where status = 'open'
  do update set reason = excluded.reason, note = excluded.note
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.report_content(text, uuid, text, text) from public, anon;
grant execute on function public.report_content(text, uuid, text, text) to authenticated;

-- Fra 019/044. Nytt: 'comment' slettes mykt; rapporter uten klubb avgjøres av turneringens
-- arrangør.
create or replace function public.resolve_report(p_report_id uuid, p_action text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_report  public.content_reports;
  v_image   text;
  v_status  text;
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if p_action is null or p_action not in ('remove', 'dismiss') then
    raise exception 'Handlingen må være remove eller dismiss' using errcode = '22023';
  end if;
  select * into v_report from public.content_reports r where r.id = p_report_id for update;
  if not found or not private.can_moderate(v_report.club_id, v_report.competition_id) then
    raise exception 'Bare arrangøren i klubben kan avgjøre rapporten' using errcode = '42501';
  end if;
  if v_report.status <> 'open' then
    raise exception 'Rapporten er allerede avgjort' using errcode = '55000';
  end if;

  v_status := case p_action when 'remove' then 'removed' else 'dismissed' end;
  if p_action = 'remove' and v_report.kind in ('message', 'image') then
    delete from public.thread_messages t
     where t.id = v_report.target_id and t.club_id = v_report.club_id
    returning t.image_path into v_image;
  elsif p_action = 'remove' and v_report.kind = 'comment' then
    perform private.comment_soft_delete(c.id, v_uid)
       from public.comments c
      where c.id = v_report.target_id
        and c.club_id is not distinct from v_report.club_id
        and (v_report.club_id is not null or c.competition_id = v_report.competition_id);
  end if;

  -- Alle åpne rapporter om det samme innholdet avgjøres samtidig.
  update public.content_reports r
     set status = v_status, handled_by = v_uid, handled_at = now()
   where r.status = 'open' and r.target_id = v_report.target_id
     and r.club_id is not distinct from v_report.club_id
     and r.competition_id is not distinct from v_report.competition_id
     and (r.kind = v_report.kind or (r.kind in ('message', 'image') and v_report.kind in ('message', 'image')));

  return jsonb_build_object('status', v_status, 'image_path', v_image);
end;
$$;
revoke all on function public.resolve_report(uuid, text) from public, anon;
grant execute on function public.resolve_report(uuid, text) to authenticated;

-- Fra 044. Nytt: kommentarene, reaksjonene og følgingen til kontoen slettes også.
create or replace function public.delete_account_data(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_members   uuid[];
  v_messages  integer := 0;
  v_comments  integer := 0;
  v_promoted  integer := 0;
  v_owners    integer := 0;
  v_rounds    integer := 0;
  v_row       record;
  v_heir      uuid;
begin
  if p_user_id is null then
    raise exception 'Mangler bruker' using errcode = '22023';
  end if;

  select coalesce(array_agg(m.id), '{}') into v_members
  from public.club_members m where m.user_id = p_user_id;

  -- Klubben skal ikke stå uten arrangør: er dette den siste, overtar det
  -- eldste aktive medlemmet med innlogging.
  for v_row in
    select m.club_id from public.club_members m
    where m.user_id = p_user_id and m.is_organizer and m.status = 'active'
      and not exists (select 1 from public.club_members o
                      where o.club_id = m.club_id and o.id <> m.id and o.is_organizer
                        and o.status = 'active' and o.user_id is not null)
  loop
    update public.club_members o set is_organizer = true
     where o.id = (select n.id from public.club_members n
                   where n.club_id = v_row.club_id and n.status = 'active'
                     and n.user_id is not null and n.user_id <> p_user_id
                   order by n.created_at, n.id limit 1);
    if found then v_promoted := v_promoted + 1; end if;
  end loop;

  -- 044: og ikke uten eier. Den eldste gjenværende arrangøren overtar, ellers det
  -- eldste aktive medlemmet med innlogging.
  for v_row in
    select m.id, m.club_id from public.club_members m
    where m.user_id = p_user_id and private.member_is_last_owner(m.id)
  loop
    select n.id into v_heir from public.club_members n
     where n.club_id = v_row.club_id and n.status = 'active'
       and n.user_id is not null and n.user_id <> p_user_id
     order by n.is_organizer desc, n.created_at, n.id limit 1;
    if v_heir is not null then
      insert into public.club_member_roles (club_id, member_id, role_id)
      select v_row.club_id, v_heir, r.id from public.club_roles r
       where r.club_id = v_row.club_id and r.is_owner
      on conflict do nothing;
      v_owners := v_owners + 1;
    end if;
  end loop;
  delete from public.club_member_roles mr where mr.member_id = any (v_members);

  -- Innholdet personen har skrevet.
  delete from public.thread_messages t where t.member_id = any (v_members);
  get diagnostics v_messages = row_count;
  delete from public.activity_reactions r where r.member_id = any (v_members);
  -- 050: kommentarer, reaksjoner og følging.
  delete from public.comments c where c.member_id = any (v_members) or c.profile_id = p_user_id;
  get diagnostics v_comments = row_count;
  delete from public.reactions r where r.member_id = any (v_members) or r.profile_id = p_user_id;
  delete from public.thread_follows f where f.user_id = p_user_id;
  delete from public.push_preferences p where p.member_id = any (v_members);
  delete from public.push_devices d where d.user_id = p_user_id;
  delete from public.user_blocks b where b.blocker_id = p_user_id or b.blocked_id = p_user_id;

  -- Troppen: navnet står som «Slettet spiller», arkivert (kan ikke tas av en
  -- annen innlogging), uten roller, portrett eller innlogging.
  update public.club_members m
     set display_name = 'Slettet spiller', avatar_path = null, is_organizer = false,
         is_treasurer = false, status = 'archived', user_id = null
   where m.id = any (v_members);

  -- Løse runder: deltakeren blir en gjest med navnet «Slettet spiller».
  update public.round_participants rp set display_name = 'Slettet spiller'
   where rp.profile_id = p_user_id;
  get diagnostics v_rounds = row_count;

  update public.profiles p
     set display_name = null, avatar_path = null, handicap_index = null
   where p.id = p_user_id;

  return jsonb_build_object('memberships', cardinality(v_members), 'messages', v_messages,
                            'comments', v_comments,
                            'loose_rounds', v_rounds, 'organizers_promoted', v_promoted,
                            'owners_promoted', v_owners);
end;
$$;
revoke all on function public.delete_account_data(uuid) from public, anon, authenticated;
grant execute on function public.delete_account_data(uuid) to service_role;


-- ===========================================================================
-- 9. REALTIME
-- ===========================================================================
do $$
declare
  t text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'Publikasjonen supabase_realtime finnes ikke – hopper over realtime';
    return;
  end if;
  foreach t in array array['reactions', 'comments'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;


-- ===========================================================================
-- KONTROLL (kjøres i samme transaksjon; feiler ved avvik)
-- ===========================================================================
do $$
declare
  v_fail text := '';
  v_fn   text;
begin
  -- 1. De nye tabellene har RLS, og appen kan bare lese.
  if exists (select 1 from pg_class
              where oid in ('public.reactions'::regclass, 'public.comments'::regclass,
                            'public.thread_follows'::regclass) and not relrowsecurity)
     or has_table_privilege('authenticated', 'public.reactions', 'insert')
     or has_table_privilege('authenticated', 'public.comments', 'insert')
     or has_table_privilege('authenticated', 'public.comments', 'update')
     or has_table_privilege('authenticated', 'public.thread_follows', 'insert')
     or has_table_privilege('anon', 'public.reactions', 'select')
     or has_table_privilege('anon', 'public.comments', 'select') then
    v_fail := v_fail || ' 1';
  end if;
  -- 2. Speilingen: hver gammel reaksjon finnes i reactions, og hver reaksjon fra fem-settet på
  --    en hendelse i klubb finnes i activity_reactions.
  if exists (select 1 from public.activity_reactions o
              where not exists (select 1 from public.reactions r
                                 where r.target_kind = 'activity' and r.target_id = o.activity_id
                                   and r.member_id = o.member_id and r.emoji = o.emoji))
     or exists (select 1 from public.reactions r
                 where r.target_kind = 'activity' and r.member_id is not null
                   and r.emoji = any (private.legacy_reaction_emojis())
                   and not exists (select 1 from public.activity_reactions o
                                    where o.activity_id = r.target_id and o.member_id = r.member_id
                                      and o.emoji = r.emoji)) then
    v_fail := v_fail || ' 2';
  end if;
  -- 3. Emojisjekken: de fem og noen andre ja, tekst og to emojier nei.
  if not (select bool_and(private.is_single_emoji(e))
            from unnest(private.legacy_reaction_emojis() || array['🏌️‍♂️', '🇳🇴', '👍🏽', '1️⃣']) e)
     or (select bool_or(private.is_single_emoji(e)) from unnest(array['a', '👍👍', '', ' 👍', 'ok']) e) then
    v_fail := v_fail || ' 3';
  end if;
  -- 4. Kartet: de nye kindene er i Sosialt, og alle kinds i activity har en gruppe.
  if (select count(*) from public.push_group_map()
       where kind in ('comment_added', 'mentioned', 'photo_prompt') and group_key = 'social') <> 3
     or exists (select 1 from public.activity a where public.push_group(a.category, a.kind) is null) then
    v_fail := v_fail || ' 4';
  end if;
  -- 5. RPC-ene: innlogget ja, anon nei.
  foreach v_fn in array array['public.react(text, uuid, text, boolean)',
                              'public.comment_add(text, uuid, text, uuid[], boolean)',
                              'public.comment_edit(uuid, text, uuid[])',
                              'public.comment_delete(uuid)',
                              'public.follow_thread(text, uuid, boolean)',
                              'public.feed_page(uuid[], timestamptz, uuid, integer)'] loop
    if not has_function_privilege('authenticated', v_fn, 'execute')
       or has_function_privilege('anon', v_fn, 'execute') then
      v_fail := v_fail || ' 5(' || v_fn || ')';
    end if;
  end loop;
  -- 6. Triggerne.
  if (select count(*) from pg_trigger where not tgisinternal
        and ((tgname = 'reactions_mirror_legacy' and tgrelid = 'public.reactions'::regclass)
          or (tgname = 'activity_reactions_mirror' and tgrelid = 'public.activity_reactions'::regclass)
          or (tgname = 'rounds_photo_prompt' and tgrelid = 'public.rounds'::regclass)
          or (tgname = 'activity_social_cleanup' and tgrelid = 'public.activity'::regclass)
          or (tgname = 'thread_messages_social_cleanup' and tgrelid = 'public.thread_messages'::regclass)
          or (tgname = 'comments_social_cleanup' and tgrelid = 'public.comments'::regclass))) <> 6 then
    v_fail := v_fail || ' 6';
  end if;
  -- 7. Én bildeoppfordring per runde.
  if to_regclass('public.activity_photo_prompt_once') is null
     or exists (select 1 from public.activity where kind = 'photo_prompt'
                 group by round_id having count(*) > 1) then
    v_fail := v_fail || ' 7';
  end if;
  -- 8. Rapporter: 'comment' og competition_id.
  if not exists (select 1 from pg_constraint where conname = 'content_reports_kind_check'
                  and pg_get_constraintdef(oid) like '%comment%')
     or not exists (select 1 from information_schema.columns where table_schema = 'public'
                     and table_name = 'content_reports' and column_name = 'competition_id') then
    v_fail := v_fail || ' 8';
  end if;
  -- 9. Kommentarene: én forfatter, klubb eller turnering, slettede uten tekst.
  if exists (select 1 from public.comments c
              where (c.club_id is null and c.competition_id is null and c.deleted_at is null)
                 or (c.deleted_at is not null and (c.body <> '' or cardinality(c.mentions) > 0))) then
    v_fail := v_fail || ' 9';
  end if;
  -- 10. Senderens funksjon er fortsatt bare for service_role, og alle jobber gir svar.
  if has_function_privilege('authenticated', 'public.push_job_payload(bigint)', 'execute')
     or exists (select 1 from public.push_queue q where public.push_job_payload(q.id) is null) then
    v_fail := v_fail || ' 10';
  end if;

  if v_fail <> '' then
    raise exception '050 kontroll feilet:%', v_fail;
  end if;
  raise notice '050 kontroll: 10 av 10 (reaksjoner: %, fra gamle bygg: %, kommentarer: %, bildeoppfordringer: %)',
    (select count(*) from public.reactions),
    (select count(*) from public.activity_reactions),
    (select count(*) from public.comments),
    (select count(*) from public.activity where kind = 'photo_prompt');
end $$;

commit;

-- ===========================================================================
-- RULLEBAKKE (før appen bruker reaksjonene, kommentarene eller feeden)
-- ===========================================================================
-- Nye emojier og kommentarer går tapt. activity_reactions står med det fem-settet har.
-- begin;
-- (gjenopprett delete_account_data fra 044_roller.sql, resolve_report og report_content fra
--  019_konto_og_moderering.sql (resolve_report med has_club_right fra 044))
-- delete from public.content_reports where kind = 'comment';
-- alter table public.content_reports drop constraint if exists content_reports_kind_check;
-- alter table public.content_reports add constraint content_reports_kind_check
--   check (kind in ('message', 'image', 'member', 'profile'));
-- drop policy if exists content_reports_select on public.content_reports;
-- create policy content_reports_select on public.content_reports for select to authenticated
--   using (reporter_id = auth.uid() or (club_id is not null and private.has_club_right(club_id, 'money')));
-- alter table public.content_reports drop column if exists competition_id;
-- drop function if exists public.feed_page(uuid[], timestamptz, uuid, integer);
-- (gjenopprett push_job_payload og push_group_map fra 046_varsler.sql)
-- drop trigger if exists comments_social_cleanup on public.comments;
-- drop trigger if exists thread_messages_social_cleanup on public.thread_messages;
-- drop trigger if exists activity_social_cleanup on public.activity;
-- drop function if exists private.social_cleanup();
-- drop trigger if exists rounds_photo_prompt on public.rounds;
-- drop function if exists private.rounds_photo_prompt();
-- delete from public.activity where kind in ('photo_prompt', 'comment_added', 'mentioned');
-- drop index if exists public.activity_photo_prompt_once;
-- (gjenopprett activity_select fra 034_turnering_kjerne_trinn4.sql og activity_before_insert
--  fra 045_pamelding_kveld.sql)
-- drop function if exists public.comment_delete(uuid);
-- drop function if exists private.comment_soft_delete(uuid, uuid);
-- drop function if exists public.comment_edit(uuid, text, uuid[]);
-- drop function if exists public.comment_add(text, uuid, text, uuid[], boolean);
-- drop function if exists private.comment_notify(public.comments, uuid[], boolean);
-- drop function if exists private.valid_mentions(text, uuid, uuid, uuid[], uuid);
-- drop function if exists public.follow_thread(text, uuid, boolean);
-- drop table if exists public.thread_follows;
-- drop table if exists public.comments;
-- drop policy if exists activity_reactions_insert on public.activity_reactions;
-- create policy activity_reactions_insert on public.activity_reactions for insert to authenticated
--   with check (public.owns_member(member_id));
-- drop function if exists public.react(text, uuid, text, boolean);
-- drop trigger if exists activity_reactions_mirror on public.activity_reactions;
-- drop function if exists private.activity_reactions_mirror();
-- drop table if exists public.reactions;   -- også ut av supabase_realtime
-- drop function if exists private.reactions_mirror_legacy();
-- drop function if exists private.can_moderate(uuid, uuid);
-- drop function if exists private.user_can_read_target(uuid, text, uuid);
-- drop function if exists private.can_read_target(text, uuid);
-- drop function if exists private.target_info(text, uuid);
-- drop function if exists private.member_has_any_right(uuid);
-- drop function if exists private.person_blocked(uuid, uuid);
-- drop function if exists private.person_user(uuid, uuid);
-- drop function if exists private.users_blocked(uuid, uuid);
-- drop function if exists private.legacy_reaction_emojis();
-- drop function if exists private.is_single_emoji(text);
-- commit;
