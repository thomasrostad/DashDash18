-- 076_vis_oppstilling.sql — spillerne ser laget og båsen sin før runden starter.
-- Thomas 11.11.2026: «Det hadde vært fint å se hvem man skal spille på lag med, når det er satt opp,
-- før man starter runden.»
--
-- Før: runden er en kladd (status 'draft') til arrangøren starter den, og bare arrangøren ser kladden
-- (rounds_select, can_read_round). Oppstillingen (round_players: bås, lag, markør) var skjult til start.
-- Nå: arrangøren trykker «Vis oppstillingen for spillerne» i rundeoppsettet (web-admin). Da:
--   * rounds.lineup_shared_at settes (ny kolonne, null = ikke vist).
--   * Spillerne i runden får push: en «Melding til alle»-linje (kind announcement, 008/046) med
--     recipients = spillerne i runden. Ingen endring i push-køen eller push-send; eldre apper viser
--     den som en vanlig melding.
--   * Klubbens medlemmer leser oppstillingen med event_lineups(event): én rad per spiller i de
--     viste kladdene for kvelden. Endrer arrangøren oppstillingen etterpå, ser alle det nye.
-- «Skjul» (p_on = false) setter kolonnen tilbake til null; ingen push.
--
-- Kladden er fortsatt en kladd: rounds_select og can_read_round er uendret, så ingen eldre app ser
-- kladderunder andre steder. event_lineups er den eneste veien inn, og gir bare navn, bås, lag og
-- markør (det medlemmene uansett ser når runden starter).
--
-- Bare legg til (docs/utgivelser.md punkt 4): ny kolonne med null som standard, to nye funksjoner.
-- Krever 046 (activity.recipients), 059 (is_club_member, my_member_id). Idempotent.
-- Kontroll og rullebakk nederst.

begin;

alter table public.rounds add column if not exists lineup_shared_at timestamptz;

-- --- Vis eller skjul oppstillingen ------------------------------------------------
-- Samme rett som å endre runden (rounds_update): has_club_right(klubb, 'rounds').
-- Gir tidspunktet (null når skjult). 42501 = ikke lov, 55000 = runden er ikke en kladd,
-- 22023 = ingen spillere i runden.
create or replace function public.share_round_lineup(p_round_id uuid, p_on boolean)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_club    uuid;
  v_status  text;
  v_event   uuid;
  v_before  timestamptz;
  v_date    date;
  v_players uuid[];
  v_prev    text := current_setting('dd18.server_activity', true);
  v_text    text;
begin
  select r.club_id, r.status, r.event_id, r.lineup_shared_at into v_club, v_status, v_event, v_before
  from public.rounds r where r.id = p_round_id;
  if v_club is null or not private.has_club_right(v_club, 'rounds') then
    raise exception 'Ikke lov' using errcode = '42501';
  end if;
  if v_status <> 'draft' then
    raise exception 'Runden er startet' using errcode = '55000';
  end if;

  if not p_on then
    update public.rounds set lineup_shared_at = null where id = p_round_id;
    return null;
  end if;

  select array_agg(rp.member_id) into v_players
  from public.round_players rp where rp.round_id = p_round_id;
  if v_players is null then
    raise exception 'Ingen spillere i runden' using errcode = '22023';
  end if;

  if v_before is not null then
    return v_before;  -- allerede vist: ingen ny push
  end if;

  update public.rounds set lineup_shared_at = now() where id = p_round_id;

  select e.event_date into v_date from public.events e where e.id = v_event;
  v_text := 'Lagene' || coalesce(' for ' || to_char(v_date, 'DD.MM'), '')
         || ' er klare. Åpne Atten og se hvem du spiller med.';
  perform set_config('dd18.server_activity', 'on', true);
  insert into public.activity (club_id, kind, category, data, actor_member_id, event_id, recipients)
  values (v_club, 'announcement', 'announcement', jsonb_build_object('text', v_text),
          public.my_member_id(v_club), v_event, v_players);
  perform set_config('dd18.server_activity', coalesce(v_prev, ''), true);

  return (select r.lineup_shared_at from public.rounds r where r.id = p_round_id);
end;
$$;
revoke all on function public.share_round_lineup(uuid, boolean) from public, anon;
grant execute on function public.share_round_lineup(uuid, boolean) to authenticated;

-- --- Les oppstillingen for en kveld -------------------------------------------------
-- Én rad per spiller i kveldens kladder som er vist. Bare for medlemmer av klubben.
create or replace function public.event_lineups(p_event_id uuid)
returns table (round_id uuid, round_no smallint, round_name text, format text, tee_time text,
               member_id uuid, name text, bay_no smallint, team_no smallint, is_marker boolean,
               shared_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select r.id, r.round_no::smallint, r.name, r.format, r.tee_time::text,
         rp.member_id, m.display_name, rp.bay_no::smallint, rp.team_no::smallint, rp.is_marker,
         r.lineup_shared_at
  from public.rounds r
  join public.round_players rp on rp.round_id = r.id
  join public.club_members m on m.id = rp.member_id
  where r.event_id = p_event_id
    and r.status = 'draft'
    and r.lineup_shared_at is not null
    and public.is_club_member(r.club_id)
  order by r.round_no, rp.bay_no nulls last, rp.team_no nulls last, m.display_name;
$$;
revoke all on function public.event_lineups(uuid) from public, anon;
grant execute on function public.event_lineups(uuid) to authenticated;

commit;

-- --- Kontroll (les) ------------------------------------------------------------
-- select count(*) from information_schema.columns
--  where table_schema = 'public' and table_name = 'rounds' and column_name = 'lineup_shared_at';   -- 1
-- select has_function_privilege('anon', 'public.share_round_lineup(uuid, boolean)', 'execute');     -- false
-- select has_function_privilege('authenticated', 'public.share_round_lineup(uuid, boolean)', 'execute'); -- true
-- select has_function_privilege('anon', 'public.event_lineups(uuid)', 'execute');                  -- false
-- select has_function_privilege('authenticated', 'public.event_lineups(uuid)', 'execute');         -- true
-- Som medlem: select * from public.event_lineups('<kveld>');  -- tom før «Vis», spillerne etter
-- --- Rullebakk -------------------------------------------------------------------
-- drop function if exists public.event_lineups(uuid);
-- drop function if exists public.share_round_lineup(uuid, boolean);
-- alter table public.rounds drop column if exists lineup_shared_at;
