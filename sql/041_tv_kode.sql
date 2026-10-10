-- 041: TV-visning med kode (Thomas 10.10.2026: «TV-visning bør være tilgjengelig fra en ekstern
-- enhet via en kode»). IKKE KJØRT. Krever godkjenning.
--
-- Arrangøren lager en kode for en turnering i appen. En skjerm uten appen (smart-TV, PC i
-- simulatorsenteret) åpner dashdash18.com/tv/KODE. Siden henter rådataene med tv_board_data(kode)
-- og regner tabellen med regelmotoren i TypeScript (web/golfgutu-core), samme fasit som appen.
--
-- Første versjon: turneringer med kvelder (sesongen, jakkeracet og serier). Liga og morro kommer
-- når web-siden kan regne dem (samme lesevei, rundene via competition_rounds).
--
-- Hva koden gir: turneringens navn, status og regelsett, kveldene, troppens visningsnavn,
-- handicap og seeding, rundene med hull, spillere, matcher, sidepremier, baner og scorer.
-- IKKE: innlogging (user_id), bilder, e-post, tråd, påmeldinger eller noe annet i klubben.
-- Koden er 10 tegn uten tegn som kan forveksles (32^10 ≈ 10^15), kan fornyes og trekkes tilbake,
-- og varer i ett år.
--
-- Én transaksjon, idempotent. Kontroll og rullebakke nederst.

begin;

create table if not exists public.tv_codes (
  code            text primary key check (code ~ '^[A-HJ-NP-Z2-9]{10}$'),
  competition_id  uuid not null references public.competitions(id) on delete cascade,
  created_by      uuid references public.profiles(id) on delete set null,
  created_at      timestamptz not null default now(),
  expires_at      timestamptz not null default now() + interval '1 year',
  revoked_at      timestamptz
);
comment on table public.tv_codes is
  'Koder for TV-visning av en turnering uten innlogging (sql/041). Skrives bare via tv_code og tv_code_revoke.';
create index if not exists tv_codes_competition_idx on public.tv_codes (competition_id);
alter table public.tv_codes enable row level security;
-- Ingen policyer: tabellen leses og skrives bare gjennom funksjonene under.

-- Koden for turneringen: den gyldige som finnes, eller en ny (p_renew trekker den gamle tilbake).
create or replace function public.tv_code(p_competition_id uuid, p_renew boolean default false)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if not public.is_competition_admin(p_competition_id) then
    raise exception 'Bare arrangøren kan lage TV-kode' using errcode = '42501';
  end if;
  if p_renew then
    update public.tv_codes set revoked_at = now()
     where competition_id = p_competition_id and revoked_at is null;
  else
    select t.code into v_code from public.tv_codes t
     where t.competition_id = p_competition_id and t.revoked_at is null and t.expires_at > now()
     order by t.created_at desc limit 1;
    if v_code is not null then return v_code; end if;
  end if;
  loop
    select string_agg(substr(v_alphabet, 1 + floor(random() * 32)::int, 1), '') into v_code
      from generate_series(1, 10);
    begin
      insert into public.tv_codes (code, competition_id, created_by) values (v_code, p_competition_id, auth.uid());
      return v_code;
    exception when unique_violation then
      -- Svært usannsynlig: prøv en ny.
    end;
  end loop;
end;
$$;
revoke all on function public.tv_code(uuid, boolean) from public, anon;
grant execute on function public.tv_code(uuid, boolean) to authenticated;

create or replace function public.tv_code_revoke(p_competition_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_competition_admin(p_competition_id) then
    raise exception 'Bare arrangøren kan trekke tilbake TV-koden' using errcode = '42501';
  end if;
  update public.tv_codes set revoked_at = now() where competition_id = p_competition_id and revoked_at is null;
end;
$$;
revoke all on function public.tv_code_revoke(uuid) from public, anon;
grant execute on function public.tv_code_revoke(uuid) to authenticated;

-- Rådataene for TV-siden. Samme form som tavla_data (036), uten innloggingsfelt og bilder, og med
-- turneringen øverst. Ugyldig, utløpt eller tilbaketrukket kode: P0002.
create or replace function public.tv_board_data(p_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_comp    public.competitions%rowtype;
  v_events  uuid[];
  v_rounds  uuid[];
  v_courses uuid[];
begin
  select c.* into v_comp
    from public.tv_codes t join public.competitions c on c.id = t.competition_id
   where t.code = upper(btrim(coalesce(p_code, ''))) and t.revoked_at is null and t.expires_at > now();
  if v_comp.id is null or v_comp.season_id is null then
    raise exception 'Fant ingen TV-visning for koden' using errcode = 'P0002';
  end if;

  select coalesce(array_agg(e.id), '{}') into v_events
    from public.events e where e.season_id = v_comp.season_id;
  select coalesce(array_agg(r.id), '{}') into v_rounds
    from public.rounds r where r.event_id = any (v_events) and r.status in ('active', 'locked');
  select coalesce(array_agg(distinct r.course_id), '{}') into v_courses
    from public.rounds r where r.id = any (v_rounds) and r.course_id is not null;

  return jsonb_build_object(
    'competition', jsonb_build_object('id', v_comp.id, 'name', v_comp.name, 'kind', v_comp.kind,
                                      'status', v_comp.status, 'season_id', v_comp.season_id,
                                      'club_id', v_comp.club_id, 'rules', v_comp.rules,
                                      'club_name', (select k.name from public.clubs k where k.id = v_comp.club_id)),
    'events', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select e.id, e.club_id, e.season_id, e.event_date, e.start_time, e.venue
          from public.events e where e.id = any (v_events)) x),
    'members', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select m.id, m.club_id, null::uuid as user_id, m.display_name, m.handicap_index, m.seed_group,
               m.is_organizer, m.is_treasurer, m.status, null::text as avatar_path
          from public.club_members m where m.club_id = v_comp.club_id) x),
    'rounds', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select r.id, r.club_id, r.event_id, r.course_id, r.round_no, r.name, r.status, r.hole_count,
               r.first_hole, r.tee_time, r.format, r.handicap_allowance, r.external_handicap, r.weight,
               r.ld_enabled, r.ld_hole_index, r.kp_enabled, r.kp_hole_index, r.cut_rule, r.cut_after,
               r.par_confirmed_by, r.par_confirmed_at, r.started_at, r.locked_at, r.venue,
               r.tee_id, r.tee_name, r.course_rating, r.slope_rating, r.tee_par
          from public.rounds r where r.id = any (v_rounds)) x),
    'round_holes', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select h.round_id, h.hole_index, h.par, h.stroke_index, h.length_m
          from public.round_holes h where h.round_id = any (v_rounds)) x),
    'players', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select p.round_id, p.member_id, p.club_id, p.handicap_index, p.seed_group, p.playing_handicap,
               p.bay_no, p.is_marker, p.team_no
          from public.round_players p where p.round_id = any (v_rounds)) x),
    'matches', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select m.round_id, m.match_no, m.player_a, m.player_b, m.player_c, m.team_a, m.team_b, m.result
          from public.round_matches m where m.round_id = any (v_rounds)) x),
    'claims', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select c.id, c.round_id, c.member_id, c.kind, c.meters, c.hole_index, c.created_at
          from public.side_claims c where c.round_id = any (v_rounds)) x),
    'courses', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select c.id, c.club_id, c.name, c.external_name, c.course_rating, c.slope_rating, c.in_use,
               null::uuid as confirmed_by, null::timestamptz as confirmed_at
          from public.courses c where c.id = any (v_courses)) x),
    'course_holes', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select h.course_id, h.hole_number, h.par, h.stroke_index, h.length_m
          from public.course_holes h where h.course_id = any (v_courses)) x),
    'scores', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select s.round_id, s.member_id, s.hole_index, s.strokes
          from public.hole_scores s where s.round_id = any (v_rounds)) x)
  );
end;
$$;
revoke all on function public.tv_board_data(text) from public;
grant execute on function public.tv_board_data(text) to anon, authenticated;

commit;

-- Kontroll (les):
-- select count(*) from pg_proc where proname in ('tv_code', 'tv_code_revoke', 'tv_board_data');  -- 3
-- select has_function_privilege('anon', 'public.tv_board_data(text)', 'execute');                -- true
-- select has_function_privilege('anon', 'public.tv_code(uuid,boolean)', 'execute');              -- false
--
-- Rull tilbake:
-- begin;
-- drop function if exists public.tv_board_data(text);
-- drop function if exists public.tv_code_revoke(uuid);
-- drop function if exists public.tv_code(uuid, boolean);
-- drop table if exists public.tv_codes;
-- commit;
