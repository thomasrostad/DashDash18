-- 040: Sanntid via Broadcast (fase 24, punkt 5). IKKE KJØRT. Krever godkjenning.
--
-- I dag følger Tavla med på postgres_changes for ALLE hullscorer, matcher og sidepremier
-- (filteret er bare på rounds.club_id), og Realtime sjekker RLS (can_read_round) for hver
-- abonnent ved hver endring. Ti tilskuere på en runde med 32 spillere gir 32 × 18 × 10
-- sjekker, og en Tavla-abonnent i én klubb får hendelser fra alle klubbene (avvist av RLS, men
-- sjekket). Se docs/fase-22-turnering-som-kjerne.md kap. 9.5 punkt 4.
--
-- Her sender en trigger en kort melding (Broadcast fra databasen, realtime.send) til to
-- private kanaler når en runde endres:
--   round:<runde-id>   runden som vises (føring, sidepremier, matcher, låsing)
--   club:<klubb-id>    Tavla og Hjem i klubben (bare klubbrunder)
-- Meldingen er bare { round_id, table, op }: telefonen henter selv det den trenger, som i dag.
-- Tilgangen sjekkes ÉN gang når telefonen kobler seg på kanalen (policy på realtime.messages):
-- round: can_read_round, club: is_club_member. Ingen kan sende på kanalene (ingen insert-policy).
--
-- Gamle bygg merker ingenting: publikasjonen supabase_realtime og postgres_changes står urørt.
-- Den nye appen bruker kanalene bak flagget BroadcastFeature, slått på etter at dette er kjørt.
--
-- Én transaksjon, idempotent. Kontroll og rullebakke nederst.

begin;

create or replace function public.broadcast_round_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row   jsonb;
  v_round uuid;
  v_club  uuid;
  v_msg   jsonb;
begin
  v_row := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  if tg_table_name = 'rounds' then
    v_round := (v_row ->> 'id')::uuid;
    v_club := (v_row ->> 'club_id')::uuid;
  else
    v_round := (v_row ->> 'round_id')::uuid;
    select r.club_id into v_club from public.rounds r where r.id = v_round;
  end if;
  if v_round is null then
    return null;
  end if;
  v_msg := jsonb_build_object('round_id', v_round, 'table', tg_table_name, 'op', lower(tg_op));
  -- Sanntid skal aldri stoppe en føring: feiler sendingen, går skrivingen gjennom likevel.
  begin
    perform realtime.send(v_msg, 'change', 'round:' || v_round::text, true);
    if v_club is not null then
      perform realtime.send(v_msg, 'change', 'club:' || v_club::text, true);
    end if;
  exception when others then
    null;
  end;
  return null;
end;
$$;
revoke all on function public.broadcast_round_change() from public, anon, authenticated;

drop trigger if exists hole_scores_broadcast on public.hole_scores;
create trigger hole_scores_broadcast
  after insert or update or delete on public.hole_scores
  for each row execute function public.broadcast_round_change();

drop trigger if exists side_claims_broadcast on public.side_claims;
create trigger side_claims_broadcast
  after insert or update or delete on public.side_claims
  for each row execute function public.broadcast_round_change();

drop trigger if exists round_matches_broadcast on public.round_matches;
create trigger round_matches_broadcast
  after insert or update or delete on public.round_matches
  for each row execute function public.broadcast_round_change();

-- Runden selv: start, låsing, sletting og oppsett (status, kladd → aktiv osv.).
drop trigger if exists rounds_broadcast on public.rounds;
create trigger rounds_broadcast
  after insert or update or delete on public.rounds
  for each row execute function public.broadcast_round_change();

-- Hvem kan lytte på kanalen (sjekkes når telefonen kobler seg på).
create or replace function public.can_listen_topic(p_topic text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_topic ~ '^round:[0-9a-f-]{36}$' then public.can_read_round(substr(p_topic, 7)::uuid)
    when p_topic ~ '^club:[0-9a-f-]{36}$' then public.is_club_member(substr(p_topic, 6)::uuid)
    else false
  end;
$$;
revoke all on function public.can_listen_topic(text) from public, anon;
grant execute on function public.can_listen_topic(text) to authenticated;

drop policy if exists atten_broadcast_listen on realtime.messages;
create policy atten_broadcast_listen on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast' and public.can_listen_topic(realtime.topic()));

commit;

-- Kontroll (les):
-- select tgname from pg_trigger where tgname like '%_broadcast' order by 1;  -- 4 rader
-- select policyname from pg_policies where schemaname = 'realtime' and policyname = 'atten_broadcast_listen';
--
-- Rull tilbake:
-- begin;
-- drop policy if exists atten_broadcast_listen on realtime.messages;
-- drop trigger if exists hole_scores_broadcast on public.hole_scores;
-- drop trigger if exists side_claims_broadcast on public.side_claims;
-- drop trigger if exists round_matches_broadcast on public.round_matches;
-- drop trigger if exists rounds_broadcast on public.rounds;
-- drop function if exists public.broadcast_round_change();
-- drop function if exists public.can_listen_topic(text);
-- commit;
