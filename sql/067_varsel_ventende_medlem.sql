-- 067: varsel til arrangørene når noen vil bli med i klubben (1.0.1). IKKE KJØRT.
--
-- Bakgrunn: når en ny spiller skriver klubbkoden og et nytt navn, lager join_club (059, ca.
-- linje 454) en club_members-rad med status 'pending', og skjermen sier «Venter på
-- godkjenning». Arrangørene fikk verken push, varsel i bjella eller merke, og de ventende sto
-- bare under Arrangør → Troppen. Nye spillere ble derfor stående og vente.
--
-- Hva:
--   * Ny hendelse member_pending i activity (kategori club, gruppe Arrangør), skrevet av
--     serveren når en ventende rad lages: insert med status 'pending', eller en oppdatering
--     til 'pending' fra en annen status. Triggeren club_members_pending_notify (AFTER, per rad).
--       - Bare når raden lages eller endres av en innlogget (auth.uid() er satt): join_club,
--         der personen selv ber om å bli med, eller en arrangør som setter en rad tilbake til
--         'pending'. Importen, SQL Editor og service_role (auth.uid() er null) gir ingen
--         varsel, heller ikke om de skulle sette 'pending'. Importen setter 'active'.
--       - Bare medlemsrader (kind = 'member'), ikke deltakere fra 059.
--       - Mottakerne (recipients) er de aktive medlemmene med innlogging som har rettigheten
--         members (Medlemmer og invitasjon) eller er eier, samme regel som
--         private.has_club_right(klubb, 'members') i 044/059. Høyst 200. Ingen = ingen linje.
--       - Aktøren (actor_member_id) er den ventende raden, så push-send regner den som den som
--         står bak (blokkering) og aldri som mottaker.
--       - data: member (raden), name (navnet slik det ble skrevet) og club_name (klubben), så
--         appen og push-send kan skrive «Ola Nordmann vil bli med i Golfgutu Invitational» uten
--         å slå opp en rad de kanskje ikke ser.
--       - Én linje per ventende rad (unik indeks på data->>'member' for member_pending).
--     Push går gjennom den vanlige køen: push_enqueue_activity (054) legger linja i push_queue,
--     webhooken dd18_push_queue (062) vekker push-send, og push_job_payload (054) gir
--     mottakerne, gruppen og valgene. Ingen endring i køen eller payloaden.
--   * Varselet forsvinner når raden ikke lenger venter: godkjent ('active'), avvist
--     ('archived') eller slettet. Triggeren club_members_pending_cleanup sletter linja (og med
--     den jobben i push_queue og loggen i notifications, som har on delete cascade). Da står
--     ikke «vil bli med» igjen i bjella til de andre arrangørene etter at én har svart.
--   * push_group (046): member_pending hører til gruppen organizer (Arrangør), som
--     signup_dropped. Kategorien er club («Klubben»), så klubbens og spillerens kategorivalg
--     virker som for andre klubbhendelser. Gruppen Arrangør av = ingen push.
--   * push_group_map (054): de 31 radene fra 054 pluss ('club', 'member_pending') = 32.
--   * push_email_kinds (046): også member_pending, så arrangører uten push får e-post når SMTP
--     er satt opp (push_email_recipients fra 046 er uendret og leser lista).
--   * Rader som venter fra før, får én linje i bjella nå, med tiden raden ble laget. De går
--     ikke som push (push-send hopper over linjer eldre enn 30 minutter).
--
-- Krever: 044 (roller), 046 (grupper, e-post), 054 (push_group_map, køen), 059 (kind, join_club).
-- Etterpå: deploy push-send på nytt (tekst, dyplenke og e-post for member_pending), og slå på
-- PendingMembersFeature i appen.
--
-- Merk: 054s kontroll krever 31 rader i push_group_map, så 054 kan ikke kjøres på nytt etter
-- 067 uten at kontrollen der rettes (kontrollen i 067 sjekker 32).
--
-- Mønsteret fra 001–066: én transaksjon, idempotent, search_path = '', revoke etter hver
-- create or replace, kontroll og rullebakke nederst.

begin;


-- ===========================================================================
-- 1. GRUPPEN, KARTET OG E-POSTEN
-- ===========================================================================
-- Fra 046. Nytt: member_pending er Arrangør.
create or replace function public.push_group(p_category text, p_kind text default null)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_kind in ('signup_dropped', 'member_pending') then 'organizer'
    when p_kind = 'evening_started' then 'evening'
    when p_category in ('score', 'lead', 'side_prize', 'round', 'bet', 'tips') then 'game'
    when p_category in ('social', 'club', 'thread') then 'social'
    when p_category in ('signup', 'reminder', 'nudge', 'setup', 'announcement') then 'evening'
  end;
$$;
revoke all on function public.push_group(text, text) from public, anon;
grant execute on function public.push_group(text, text) to authenticated, service_role;

-- Fra 054, med member_pending.
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
    ('social', 'bill_share_sent'), ('social', 'bill_share_disputed'),
    ('social', 'follow_requested'), ('social', 'follow_accepted'), ('social', 'followed'),
    ('round', 'round_finished'),
    ('club', 'member_pending')
  ) as m (category, kind)
  order by 1, 2, 3;
$$;
revoke all on function public.push_group_map() from public, anon;
grant execute on function public.push_group_map() to authenticated, service_role;

-- Fra 046, med member_pending.
create or replace function public.push_email_kinds()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array['announcement', 'nudge', 'reminder', 'waitlist_promoted', 'signup_dropped',
               'member_pending']::text[];
$$;
revoke all on function public.push_email_kinds() from public, anon;
grant execute on function public.push_email_kinds() to authenticated, service_role;


-- ===========================================================================
-- 2. LINJA I ACTIVITY
-- ===========================================================================
-- Én linje per ventende rad.
create unique index if not exists activity_member_pending_once
  on public.activity ((data ->> 'member')) where kind = 'member_pending';

-- Mottakerne: aktive medlemmer med innlogging som har rettigheten members eller er eier
-- (som private.has_club_right(klubb, 'members') for hver av dem). Uten p_except.
create or replace function private.member_pending_recipients(p_club_id uuid, p_except uuid)
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(x.id order by x.id), '{}')
    from (select distinct m.id
            from public.club_members m
            join public.club_member_roles mr on mr.member_id = m.id
            join public.club_roles r on r.id = mr.role_id
           where m.club_id = p_club_id
             and m.status = 'active'
             and m.kind = 'member'
             and m.user_id is not null
             and m.id is distinct from p_except
             and (r.is_owner or 'members' = any (r.rights))) x;
$$;
revoke all on function private.member_pending_recipients(uuid, uuid) from public, anon, authenticated;

-- Skriver linja for en ventende rad. created_at null = nå.
create or replace function private.member_pending_activity(p_member public.club_members, p_created_at timestamptz)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prev text := current_setting('dd18.server_activity', true);
  v_to   uuid[];
  v_club text;
begin
  v_to := private.member_pending_recipients(p_member.club_id, p_member.id);
  if cardinality(v_to) = 0 then
    return;
  end if;
  select c.name into v_club from public.clubs c where c.id = p_member.club_id;

  perform set_config('dd18.server_activity', 'on', true);
  insert into public.activity (club_id, kind, category, data, actor_member_id, recipients, created_at)
  values (p_member.club_id, 'member_pending', 'club',
          jsonb_strip_nulls(jsonb_build_object(
            'member', p_member.id,
            'name', p_member.display_name,
            'club_name', v_club)),
          p_member.id, v_to[1:200], coalesce(p_created_at, now()))
  on conflict ((data ->> 'member')) where kind = 'member_pending' do nothing;
  perform set_config('dd18.server_activity', coalesce(v_prev, ''), true);
end;
$$;
revoke all on function private.member_pending_activity(public.club_members, timestamptz)
  from public, anon, authenticated;

-- Triggeren: bare med en innlogget bak (join_club, eller en arrangør). Ikke import og SQL.
create or replace function private.member_pending_notify()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or new.user_id is null then
    return null;
  end if;
  if new.status <> 'pending' or new.kind <> 'member' then
    return null;
  end if;
  if tg_op = 'UPDATE' and old.status = 'pending' then
    return null;
  end if;
  perform private.member_pending_activity(new, null);
  return null;
end;
$$;
revoke all on function private.member_pending_notify() from public, anon, authenticated;

drop trigger if exists club_members_pending_notify on public.club_members;
create trigger club_members_pending_notify
  after insert or update of status on public.club_members
  for each row
  when (new.status = 'pending')
  execute function private.member_pending_notify();

-- Raden venter ikke lenger (godkjent, avvist eller slettet): linja forsvinner.
create or replace function private.member_pending_cleanup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.status = 'pending' then
    return null;
  end if;
  delete from public.activity a
   where a.kind = 'member_pending'
     and a.club_id = old.club_id
     and a.data ->> 'member' = old.id::text;
  return null;
end;
$$;
revoke all on function private.member_pending_cleanup() from public, anon, authenticated;

drop trigger if exists club_members_pending_cleanup on public.club_members;
create trigger club_members_pending_cleanup
  after update of status or delete on public.club_members
  for each row
  when (old.status = 'pending')
  execute function private.member_pending_cleanup();


-- ===========================================================================
-- 3. DE SOM VENTER FRA FØR
-- ===========================================================================
-- Én linje i bjella per ventende rad, med tiden raden ble laget (for gammel til push).
do $$
declare
  v_row public.club_members;
begin
  for v_row in
    select m.* from public.club_members m
     where m.status = 'pending' and m.kind = 'member' and m.user_id is not null
       and not exists (select 1 from public.activity a
                        where a.kind = 'member_pending' and a.data ->> 'member' = m.id::text)
     order by m.created_at, m.id
  loop
    perform private.member_pending_activity(v_row, v_row.created_at);
  end loop;
end $$;


-- ===========================================================================
-- KONTROLL (kjøres i samme transaksjon; feiler ved avvik)
-- ===========================================================================
do $$
begin
  if public.push_group('club', 'member_pending') is distinct from 'organizer'
     or public.push_group('signup', 'signup_dropped') is distinct from 'organizer'
     or public.push_group('club', 'member_joined') is distinct from 'social' then
    raise exception '067: push_group gir feil gruppe';
  end if;
  if (select count(*) from public.push_group_map()) <> 32
     or not exists (select 1 from public.push_group_map()
                     where kind = 'member_pending' and category = 'club' and group_key = 'organizer')
     or exists (select 1 from public.push_group_map() where group_key is null) then
    raise exception '067: push_group_map har ikke de 32 radene med member_pending under Arrangør';
  end if;
  if not ('member_pending' = any (public.push_email_kinds()))
     or not ('signup_dropped' = any (public.push_email_kinds())) then
    raise exception '067: push_email_kinds mangler member_pending';
  end if;
  if exists (select 1 from public.activity a where public.push_group(a.category, a.kind) is null) then
    raise exception '067: en linje i activity har ingen gruppe';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'club_members_pending_notify'
                   and tgrelid = 'public.club_members'::regclass
                   and tgfoid = 'private.member_pending_notify()'::regprocedure)
     or not exists (select 1 from pg_trigger where tgname = 'club_members_pending_cleanup'
                      and tgrelid = 'public.club_members'::regclass
                      and tgfoid = 'private.member_pending_cleanup()'::regprocedure) then
    raise exception '067: triggerne på club_members mangler';
  end if;
  if has_function_privilege('anon', 'private.member_pending_activity(public.club_members, timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'private.member_pending_activity(public.club_members, timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'private.member_pending_recipients(uuid, uuid)', 'execute')
     or has_function_privilege('authenticated', 'private.member_pending_notify()', 'execute')
     or has_function_privilege('authenticated', 'private.member_pending_cleanup()', 'execute')
     or has_function_privilege('anon', 'public.push_group_map()', 'execute')
     or has_function_privilege('anon', 'public.push_email_kinds()', 'execute') then
    raise exception '067: feil rettigheter på funksjonene';
  end if;
  if exists (select 1 from public.club_members m
              where m.status = 'pending' and m.kind = 'member' and m.user_id is not null
                and cardinality(private.member_pending_recipients(m.club_id, m.id)) > 0
                and not exists (select 1 from public.activity a
                                 where a.kind = 'member_pending' and a.data ->> 'member' = m.id::text)) then
    raise exception '067: en ventende rad mangler linja i bjella';
  end if;
  if exists (select 1 from public.activity a
              where a.kind = 'member_pending'
                and not exists (select 1 from public.club_members m
                                 where m.id::text = a.data ->> 'member' and m.status = 'pending')) then
    raise exception '067: en member_pending-linje gjelder en rad som ikke venter';
  end if;
  raise notice '067 kontroll: 8 av 8 (% ventende med linje)',
    (select count(*) from public.activity where kind = 'member_pending');
end $$;

commit;

-- KONTROLL ETTERPÅ (bare lesing)
-- 1) Linjene som venter, med mottakerne. Forventet: én per ventende rad i klubber med en
--    arrangør som har Medlemmer og invitasjon.
-- select a.club_id, a.data ->> 'name' as navn, a.data ->> 'club_name' as klubb,
--        cardinality(a.recipients) as mottakere, a.created_at
--   from public.activity a where a.kind = 'member_pending' order by a.created_at desc;
-- 2) Etter en prøve (ny spiller med klubbkoden og et nytt navn): jobben og resultatet.
--    Forventet: done_at satt og result med sent > 0 (eller skipped når ingen har push).
-- select q.id, q.done_at, q.result, q.last_error from public.push_queue q
--   join public.activity a on a.id = q.activity_id
--  where a.kind = 'member_pending' order by q.id desc limit 5;
-- 3) Gruppen. Forventet: organizer.
-- select public.push_group('club', 'member_pending');

-- RULLEBAKKE
-- begin;
-- drop trigger if exists club_members_pending_notify on public.club_members;
-- drop trigger if exists club_members_pending_cleanup on public.club_members;
-- drop function if exists private.member_pending_notify();
-- drop function if exists private.member_pending_cleanup();
-- drop function if exists private.member_pending_activity(public.club_members, timestamptz);
-- drop function if exists private.member_pending_recipients(uuid, uuid);
-- delete from public.activity where kind = 'member_pending';
-- drop index if exists public.activity_member_pending_once;
-- (gjenopprett push_group og push_email_kinds fra 046_varsler.sql og push_group_map fra
--  054_folge.sql)
-- commit;
