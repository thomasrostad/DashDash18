-- 055_markorkonflikt.sql — to markører som fører ulikt for samme spiller og hull
-- (UI-utbedringen K6/6.3, docs/ui-utbedring.md). TIL GODKJENNING: ikke kjørt.
--
-- I dag vinner den nyeste innsendingen (save_hole: recorded_at), og tallet som ble
-- overskrevet, forsvinner. Denne migreringen tar vare på det når en ANNEN person fører et
-- ANNET tall for samme hull kort tid etter (samtidig føring), så appen kan vise et ark med
-- begge tallene og hvem som førte dem, og la markøren eller arrangøren velge.
--
-- Avgrensning:
-- * Bare klubbrunder: updated_by er klubbmedlemmet (my_member_id). I løse runder er den null,
--   og da lages ingen konflikt.
-- * En retting lenge etter (arrangøren retter et hull etter runden) er ikke en konflikt.
--   Grensen er 15 minutter mellom de to føringene.
-- * Spillregler og poengberegning endres ikke. Tallet som står i hole_scores, er fortsatt
--   det som teller, til noen velger noe annet.
--
-- Kjøres etter 054. Idempotent. Rullebakk nederst.

begin;

-- --- Tabell ------------------------------------------------------------------
create table if not exists public.hole_score_conflicts (
  id             uuid primary key default gen_random_uuid(),
  round_id       uuid not null,
  member_id      uuid not null,
  hole_index     smallint not null check (hole_index between 0 and 17),
  -- Tallet som står nå (den siste føringen) og hvem som førte det.
  kept_strokes   smallint not null,
  kept_by        uuid references public.club_members(id) on delete set null,
  kept_at        timestamptz not null,
  -- Tallet som ble overskrevet.
  other_strokes  smallint not null,
  other_by       uuid references public.club_members(id) on delete set null,
  other_at       timestamptz not null,
  created_at     timestamptz not null default now(),
  resolved_at    timestamptz,
  resolved_by    uuid references public.club_members(id) on delete set null,
  constraint hole_score_conflicts_player_fk foreign key (round_id, member_id)
    references public.round_players (round_id, member_id) on delete cascade
);
create index if not exists hole_score_conflicts_open
  on public.hole_score_conflicts (round_id) where resolved_at is null;

alter table public.hole_score_conflicts enable row level security;
revoke all on public.hole_score_conflicts from anon;
grant select on public.hole_score_conflicts to authenticated;

-- De som kan føre for spilleren (markøren, spilleren selv, arrangøren) ser konflikten.
drop policy if exists hole_score_conflicts_select on public.hole_score_conflicts;
create policy hole_score_conflicts_select on public.hole_score_conflicts
  for select to authenticated using (public.can_score(round_id, member_id));
-- Ingen direkte skriving: triggeren lager, resolve_hole_conflict løser.

-- --- Trigger: ta vare på tallet som ble overskrevet ----------------------------
create or replace function public.capture_hole_score_conflict()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Valget i resolve_hole_conflict skal ikke lage en ny konflikt.
  if coalesce(current_setting('app.resolving_conflict', true), '') = 'on' then
    return new;
  end if;
  if new.strokes is distinct from old.strokes
     and old.updated_by is not null and new.updated_by is not null
     and old.updated_by <> new.updated_by
     and new.updated_at - old.updated_at < interval '15 minutes' then
    insert into public.hole_score_conflicts
      (round_id, member_id, hole_index, kept_strokes, kept_by, kept_at, other_strokes, other_by, other_at)
    values
      (new.round_id, new.member_id, new.hole_index, new.strokes, new.updated_by, new.updated_at,
       old.strokes, old.updated_by, old.updated_at);
  end if;
  return new;
end;
$$;
revoke all on function public.capture_hole_score_conflict() from public, anon, authenticated;

-- AFTER UPDATE: updated_by og updated_at er satt av stempel-triggeren (BEFORE UPDATE).
drop trigger if exists hole_scores_capture_conflict on public.hole_scores;
create trigger hole_scores_capture_conflict
  after update on public.hole_scores
  for each row execute function public.capture_hole_score_conflict();

-- --- RPC: velg hvilket tall som gjelder ----------------------------------------
create or replace function public.resolve_hole_conflict(p_conflict uuid, p_strokes integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.hole_score_conflicts;
begin
  select * into v from public.hole_score_conflicts where id = p_conflict for update;
  if not found then
    raise exception 'Fant ikke konflikten' using errcode = 'P0002';
  end if;
  if not public.can_score(v.round_id, v.member_id) then
    raise exception 'Du kan ikke føre for denne spilleren' using errcode = '42501';
  end if;
  if p_strokes not in (v.kept_strokes, v.other_strokes) then
    raise exception 'Velg ett av de to tallene' using errcode = '22023';
  end if;

  perform set_config('app.resolving_conflict', 'on', true);
  update public.hole_scores s
     set strokes = p_strokes, recorded_at = now()
   where s.round_id = v.round_id and s.member_id = v.member_id and s.hole_index = v.hole_index;
  perform set_config('app.resolving_conflict', 'off', true);

  update public.hole_score_conflicts
     set resolved_at = now(),
         resolved_by = (select public.my_member_id(r.club_id) from public.rounds r where r.id = v.round_id)
   where id = p_conflict;
end;
$$;
revoke all on function public.resolve_hole_conflict(uuid, integer) from public, anon;
grant execute on function public.resolve_hole_conflict(uuid, integer) to authenticated;

commit;

-- --- Kontroll (les) ------------------------------------------------------------
-- select count(*) from public.hole_score_conflicts;                                 -- 0
-- select tgname from pg_trigger where tgname = 'hole_scores_capture_conflict';      -- 1 rad
-- select has_function_privilege('anon', 'public.resolve_hole_conflict(uuid, integer)', 'execute'); -- false

-- --- Rullebakk -------------------------------------------------------------------
-- begin;
-- drop trigger if exists hole_scores_capture_conflict on public.hole_scores;
-- drop function if exists public.capture_hole_score_conflict();
-- drop function if exists public.resolve_hole_conflict(uuid, integer);
-- drop table if exists public.hole_score_conflicts;
-- commit;
