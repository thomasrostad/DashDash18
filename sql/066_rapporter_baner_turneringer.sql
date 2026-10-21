-- 066: rapporter baner i det felles biblioteket og offentlige turneringer (1.0.1, App Review 1.2).
--
-- Bakgrunn: alle innloggede kan legge inn en bane med fritt navn i det felles biblioteket
-- (017, courses_select ved ca. linje 1288, og 059 ved ca. linje 221), og «Finn turneringer»
-- (public_competitions, 032) viser turneringsnavn, klubbnavn og sted som andre har skrevet.
-- Apple krever at innhold fra brukere som andre ser, kan rapporteres.
--
-- Hva:
--   * content_reports.kind godtar også 'course' og 'competition'.
--   * report_content(p_kind, …) (fra 054) tar de to nye typene:
--       - 'course': en bane i det felles biblioteket (club_id er null og source er null, altså
--         lagt inn av en bruker, ikke hentet fra slope.no) som en annen har lagt inn. Utdraget
--         er navnet. Innholdet er fra den som la inn banen (created_by_profile).
--       - 'competition': en turnering som står i «Finn turneringer» (listed og
--         signup_audience = 'anyone', med klubb). Utdraget er «navn · klubb».
--         Innholdet er fra eieren (owner_id), når den finnes.
--     club_id og competition_id står tomme for begge typene. Da ser verken klubbens arrangør
--     eller turneringens arrangør rapporten (de står bak innholdet), og ingen kan avgjøre den i
--     appen (can_moderate(null, null) er false). Vi følger dem opp fra e-posten (063) og i
--     databasen.
--   * Skjult for den som rapporterte, til rapporten er avvist (status 'dismissed'), slik
--     rapporterte meldinger skjules for deg:
--       - public_competitions (fra 032) tar ikke med turneringer du har rapportert.
--       - my_hidden_content(p_kinds text[]): det du har rapportert og som ikke er avvist
--         (kind, target_id). Appen skjuler banene i velgeren og biblioteket med denne, og
--         turneringene med det samme før lista er hentet på nytt. Bare dine egne rader (RLS og
--         reporter_id = auth.uid()).
--   * report_alert_payload (fra 063) gir også target_id, og for en turnering navnet og klubben
--     (fra turneringen, siden rapporten ikke har klubb). Triggeren dd18_report_alert (063)
--     fyrer som før for alle typer, siden den gjelder hver INSERT i content_reports.
--
-- Krever: 019, 032, 050, 054 (report_content med 'comment' og profilreglene), 063.
-- Edge Function-en report-alert bør deployes på nytt etter denne fila (tekst for de nye
-- typene). Den gamle virker også, men skriver typen rått («course»).
--
-- Rullebakke nederst. Idempotent.

begin;

-- --- Typene ---------------------------------------------------------------------
alter table public.content_reports drop constraint if exists content_reports_kind_check;
alter table public.content_reports add constraint content_reports_kind_check
  check (kind in ('message', 'image', 'member', 'profile', 'comment', 'course', 'competition'));

create index if not exists content_reports_reporter_idx
  on public.content_reports (reporter_id, kind);

-- --- Rapporter --------------------------------------------------------------------
-- Fra 054. Nytt: 'course' og 'competition' (uten klubb og turnering på rapporten).
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
  if p_kind is null or p_kind not in ('message', 'image', 'member', 'profile', 'comment',
                                      'course', 'competition') then
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
  elsif p_kind = 'course' then
    -- En bane i det felles biblioteket som en annen har lagt inn. Klubbens baner og hentede
    -- baner (slope.no) er ikke brukerinnhold i biblioteket.
    select null, c.created_by_profile, left(c.name, 600) into v_club, v_author, v_snapshot
    from public.courses c
    where c.id = p_target_id and c.club_id is null and c.source is null
      and c.created_by_profile is distinct from v_uid;
  elsif p_kind = 'competition' then
    -- En turnering i «Finn turneringer» (samme vilkår som public_competitions, uten status,
    -- så en som nettopp ble ferdig, også kan rapporteres).
    select null, c.owner_id,
           left(concat_ws(' · ', c.name, nullif(btrim(k.name), '')), 600)
      into v_club, v_author, v_snapshot
    from public.competitions c
    join public.clubs k on k.id = c.club_id
    where c.id = p_target_id and c.listed and c.signup_audience = 'anyone';
  else
    select null, p.id, left(p.display_name, 600) into v_club, v_author, v_snapshot
    from public.profiles p
    where p.id = p_target_id and p.id <> v_uid
      and (public.can_see_profile(p.id)
           or private.follow_any_between(v_uid, p.id)
           or (p.searchable and p.display_name is not null and not private.users_blocked(v_uid, p.id)));
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

-- --- Skjult for den som rapporterte ------------------------------------------------
-- Det du har rapportert, og som ikke er avvist. p_kinds null gir alle typer.
create or replace function public.my_hidden_content(p_kinds text[] default null)
returns table (kind text, target_id uuid)
language sql
stable
security invoker
set search_path = ''
as $$
  select distinct r.kind, r.target_id
    from public.content_reports r
   where r.reporter_id = auth.uid()
     and r.status <> 'dismissed'
     and (p_kinds is null or r.kind = any (p_kinds))
   limit 1000;
$$;
revoke all on function public.my_hidden_content(text[]) from public, anon;
grant execute on function public.my_hidden_content(text[]) to authenticated;

-- Fra 032. Nytt: turneringer du har rapportert (og som ikke er avvist), står ikke i lista.
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
     and not exists (select 1 from public.content_reports r
                      where r.reporter_id = auth.uid() and r.kind = 'competition'
                        and r.target_id = c.id and r.status <> 'dismissed')
   order by c.starts_on nulls last, c.name
   limit 200;
$$;
revoke all on function public.public_competitions(uuid) from public, anon;
grant execute on function public.public_competitions(uuid) to authenticated;

-- --- Innholdet i e-posten (fra 063) ------------------------------------------------
-- Nytt: target_id, og for en turnering navnet og klubben fra turneringen selv (rapporten har
-- verken klubb eller turnering).
create or replace function public.report_alert_payload(p_report_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id',               r.id,
    'kind',             r.kind,
    'target_id',        r.target_id,
    'reason',           r.reason,
    'note',             left(r.note, 300),
    'excerpt',          left(r.snapshot, 300),
    'status',           r.status,
    'created_at',       r.created_at,
    'reporter_name',    coalesce(rp.display_name,
                          (select m.display_name from public.club_members m
                            where m.user_id = r.reporter_id and m.club_id = r.club_id
                            order by m.created_at limit 1)),
    'target_name',      coalesce(tp.display_name,
                          (select m.display_name from public.club_members m
                            where m.user_id = r.target_profile_id and m.club_id = r.club_id
                            order by m.created_at limit 1)),
    'club_name',        coalesce(c.name, tc.name),
    'competition_name', coalesce(k.name, t.name))
  from public.content_reports r
  left join public.profiles rp on rp.id = r.reporter_id
  left join public.profiles tp on tp.id = r.target_profile_id
  left join public.clubs c on c.id = r.club_id
  left join public.competitions k on k.id = r.competition_id
  left join public.competitions t on r.kind = 'competition' and t.id = r.target_id
  left join public.clubs tc on tc.id = t.club_id
  where r.id = p_report_id;
$$;
revoke all on function public.report_alert_payload(uuid) from public, anon, authenticated;
grant execute on function public.report_alert_payload(uuid) to service_role;

-- --- Kontroll -------------------------------------------------------------------
do $$
declare
  v_def text;
begin
  select pg_get_constraintdef(oid) into v_def from pg_constraint
   where conname = 'content_reports_kind_check' and conrelid = 'public.content_reports'::regclass;
  if v_def is null or v_def not like '%course%' or v_def not like '%competition%' or v_def not like '%comment%' then
    raise exception '066: content_reports_kind_check mangler en type: %', v_def;
  end if;
  if (select prosrc from pg_proc where oid = 'public.report_content(text, uuid, text, text)'::regprocedure)
       not like '%''competition''%' then
    raise exception '066: report_content kjenner ikke competition';
  end if;
  if (select prosrc from pg_proc where oid = 'public.public_competitions(uuid)'::regprocedure)
       not like '%content_reports%' then
    raise exception '066: public_competitions skjuler ikke rapporterte turneringer';
  end if;
  if has_function_privilege('anon', 'public.report_content(text, uuid, text, text)', 'execute')
     or has_function_privilege('anon', 'public.my_hidden_content(text[])', 'execute')
     or has_function_privilege('anon', 'public.public_competitions(uuid)', 'execute') then
    raise exception '066: anon kan kjøre report_content, my_hidden_content eller public_competitions';
  end if;
  if not has_function_privilege('authenticated', 'public.my_hidden_content(text[])', 'execute') then
    raise exception '066: authenticated kan ikke kjøre my_hidden_content';
  end if;
  if has_function_privilege('authenticated', 'public.report_alert_payload(uuid)', 'execute')
     or not has_function_privilege('service_role', 'public.report_alert_payload(uuid)', 'execute') then
    raise exception '066: report_alert_payload har feil rettigheter';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'dd18_report_alert'
                   and tgrelid = 'public.content_reports'::regclass) then
    raise notice '066: triggeren dd18_report_alert (063) finnes ikke, så ingen e-post ved nye rapporter';
  end if;
  raise notice '066 kontroll: 6 av 6';
end $$;

commit;

-- KONTROLL ETTERPÅ (bare lesing)
-- 1) Typene. Forventet: course og competition er med.
-- select pg_get_constraintdef(oid) from pg_constraint where conname = 'content_reports_kind_check';
-- 2) Nye rapporter om baner og turneringer (som postgres i SQL Editor).
-- select id, kind, target_id, snapshot, status, created_at from public.content_reports
--  where kind in ('course', 'competition') order by created_at desc limit 20;
-- 3) Etter en prøverapport: e-postkallet fra triggeren (063). Forventet: status_code 200.
-- select id, status_code, created from net._http_response order by id desc limit 5;

-- OPPFØLGING (som postgres i SQL Editor, når en rapport er vurdert)
-- Banen: gi den et nøytralt navn eller slett den (slettes ikke når runder bruker den), så:
--   update public.content_reports set status = 'removed', handled_at = now()
--    where kind = 'course' and target_id = '<bane-id>' and status = 'open';
-- Turneringen: ta den ut av lista (update public.competitions set listed = false where id = '<id>')
--   og sett status 'removed' på samme måte. Avvis med status = 'dismissed' (da vises innholdet
--   igjen for den som rapporterte).

-- RULLEBAKKE
-- Fjern først rapportene med de nye typene (ellers stopper den gamle sjekken):
-- begin;
-- delete from public.content_reports where kind in ('course', 'competition');
-- alter table public.content_reports drop constraint if exists content_reports_kind_check;
-- alter table public.content_reports add constraint content_reports_kind_check
--   check (kind in ('message', 'image', 'member', 'profile', 'comment'));
-- drop index if exists public.content_reports_reporter_idx;
-- drop function if exists public.my_hidden_content(text[]);
-- (gjenopprett report_content fra 054_folge.sql, public_competitions fra
--  032_turnering_kjerne_trinn2.sql og report_alert_payload fra 063_rapportvarsel.sql)
-- commit;
