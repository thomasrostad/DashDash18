-- 073: birdie og shank i feeden, uten push (21.10.2026, som 068_stille_score på test 22.10).
-- Regelen for klubbtype lagt til 26.10.2026. IKKE KJØRT.
--
-- Bakgrunn: feeden viste bare brutto eagle og bedre (big_score), og hver linje i activity går
-- som push (push_enqueue_activity, 054). Thomas vil ha birdie i feeden («gir mestring for de som
-- ikke er så gode») og shank (firedobbel bogey eller verre, valg i regelsettet, av som
-- standard), men ikke som push: det blir for mange varsler en kveld.
--
-- Hva:
--   * Ny hendelse quiet_score i activity, kategori score. data som big_score: member, hole,
--     hole_index, name ('birdie' eller 'shank'), strokes og par. Appen skriver den (som
--     big_score), ingen trigger.
--   * push_enqueue_activity (054): quiet_score legges aldri i push_queue, som round_started og
--     round_finished. Ellers uendret.
--   * Én linje per runde, spiller og hull, som big_score (indeksen fra 011). To telefoner som
--     lagrer samme hull, gir én linje.
--   * Bare i gjenger (Thomas 26.10): quiet_score lagres ikke når klubben (direkte eller via
--     turneringen) er golf_club eller simulator_center (clubs.kind, 031). Uten klubb (løse
--     runder, private turneringer) lagres den. Regelen står i databasen, så den gjelder alle
--     appversjoner.
--
-- Eldre apper (1.0.1) kjenner ikke quiet_score og viser «Ny hendelse i klubben» i Varsler til
-- de oppdaterer. Ingen push.

-- ===========================================================================
-- 1. INGEN PUSH
-- ===========================================================================
-- Fra 054, med quiet_score.
create or replace function public.push_enqueue_activity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.club_id is null and new.competition_id is null
     and (new.actor_profile_id is null or new.recipients is null) then
    return null;
  end if;
  if new.kind in ('round_started', 'round_finished', 'quiet_score') then
    return null;
  end if;
  if new.round_id is not null
     and exists (select 1 from public.rounds r where r.id = new.round_id and r.status = 'draft') then
    return null;
  end if;
  insert into public.push_queue (club_id, competition_id, activity_id)
  values (new.club_id, new.competition_id, new.id)
  on conflict do nothing;
  return null;
end;
$$;
revoke all on function public.push_enqueue_activity() from public, anon, authenticated;

-- ===========================================================================
-- 2. ÉN GANG PER HULL
-- ===========================================================================
create unique index if not exists activity_quiet_score_once_per_hole
  on public.activity (round_id, ((data ->> 'member')), ((data ->> 'hole_index')))
  where kind = 'quiet_score' and round_id is not null and data ? 'member' and data ? 'hole_index';

-- ===========================================================================
-- 3. BARE I GJENGER
-- ===========================================================================
-- Kjører etter activity_fill_competition (triggerne går i navnerekkefølge), så competition_id
-- er fylt når raden bare har runden.
create or replace function public.activity_quiet_score_gate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_club uuid := new.club_id;
begin
  if new.kind <> 'quiet_score' then
    return new;
  end if;
  if v_club is null and new.competition_id is not null then
    select c.club_id into v_club from public.competitions c where c.id = new.competition_id;
  end if;
  if v_club is not null
     and exists (select 1 from public.clubs c where c.id = v_club and c.kind <> 'group') then
    return null;
  end if;
  return new;
end;
$$;
revoke all on function public.activity_quiet_score_gate() from public, anon, authenticated;

drop trigger if exists activity_quiet_score_gate on public.activity;
create trigger activity_quiet_score_gate
  before insert on public.activity
  for each row execute function public.activity_quiet_score_gate();

-- ===========================================================================
-- SJEKK (les)
-- ===========================================================================
-- select indexname from pg_indexes where indexname = 'activity_quiet_score_once_per_hole';
-- select tgname from pg_trigger where tgname = 'activity_quiet_score_gate';
-- select position('quiet_score' in pg_get_functiondef('public.push_enqueue_activity()'::regprocedure)) > 0;

-- ===========================================================================
-- RULLE TILBAKE
-- ===========================================================================
-- drop trigger if exists activity_quiet_score_gate on public.activity;
-- drop function if exists public.activity_quiet_score_gate();
-- drop index if exists public.activity_quiet_score_once_per_hole;
-- Kjør push_enqueue_activity fra 054_folge.sql på nytt.
