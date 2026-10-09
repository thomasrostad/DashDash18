-- 038: Slette en turnering (Thomas 09.10.2026: «Slette turneringer er ikke mulig»).
--
-- I dag kan bare en planlagt sesong uten kvelder slettes (seasons_delete + events_season_fk
-- restrict), og liga, cup og morro har ingen sletting i appen. Denne funksjonen sletter hele
-- turneringen i én transaksjon:
--   1. rundene på turneringens kvelder/spilledager (alt under rundene følger med: hull, spillere,
--      scorer, matcher, sidepremier, spill, startlister, koblinger, veddemål på rundene),
--   2. kveldene/spilledagene (påmeldinger, komité og det sosiale følger med; aktivitet og
--      veddemål mister koblingen til kvelden),
--   3. sesongen (som tar turneringsraden med seg) eller turneringsraden (liga, cup, morro), med
--      påmeldte, stab, venteliste, invitasjoner, kamper og koblinger.
-- Runder som bare er koblet til turneringen («Teller også i …», løse runder) slettes ikke; bare
-- koblingen forsvinner.
--
-- Hvem: den som kan administrere turneringen (is_competition_admin: arrangør i klubben, eier av en
-- privat turnering, eller arrangør i staben). Navnet må skrives inn (p_confirm_name), så en feil
-- trykk ikke sletter en spilt sesong. Låste runder slettes også: det er hele poenget.
-- Svarer med antallene, så appen kan si hva som ble borte.
--
-- Bare en ny funksjon. Endrer ingen tabeller, policyer eller hjelpere. Idempotent.

create or replace function public.delete_tournament(p_competition_id uuid, p_confirm_name text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_comp    public.competitions%rowtype;
  v_events  uuid[];
  n_rounds  integer := 0;
  n_events  integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  select * into v_comp from public.competitions c where c.id = p_competition_id for update;
  if not found then
    raise exception 'Fant ingen turnering å slette. Er den alt borte?' using errcode = 'P0002';
  end if;
  if not public.is_competition_admin(p_competition_id) then
    raise exception 'Bare arrangøren kan slette turneringen' using errcode = '42501';
  end if;
  if lower(btrim(coalesce(p_confirm_name, ''))) <> lower(btrim(v_comp.name)) then
    raise exception 'Skriv navnet på turneringen for å slette den' using errcode = '22023';
  end if;
  if v_comp.season_id is not null then
    perform 1 from public.seasons s where s.id = v_comp.season_id for update;
  end if;

  -- Kveldene/spilledagene som hører til turneringen (sesongen eller turneringsraden).
  select coalesce(array_agg(e.id), '{}') into v_events
    from public.events e
   where e.competition_id = p_competition_id
      or (v_comp.season_id is not null and e.season_id = v_comp.season_id);

  delete from public.rounds r where r.event_id = any (v_events);
  get diagnostics n_rounds = row_count;
  delete from public.events e where e.id = any (v_events);
  get diagnostics n_events = row_count;

  if v_comp.season_id is not null then
    -- Sesongen tar turneringsraden med seg (competitions_season_fk on delete cascade).
    delete from public.seasons s where s.id = v_comp.season_id;
  else
    delete from public.competitions c where c.id = p_competition_id;
  end if;

  return jsonb_build_object('name', v_comp.name, 'rounds', n_rounds, 'events', n_events);
end;
$$;

revoke all on function public.delete_tournament(uuid, text) from public, anon;
grant execute on function public.delete_tournament(uuid, text) to authenticated;

-- Rull tilbake:
-- drop function if exists public.delete_tournament(uuid, text);
