\set ON_ERROR_STOP on
\pset footer off
-- KUN LOKALT. Prøve for 040 (sanntid via Broadcast) i en database med 001–032 og 036–038.
-- Lager en stub av Supabase sitt realtime-skjema (messages, send, topic), kjører 040 to ganger,
-- og sjekker at meldingene får riktige kanaler og at tilgangen stemmer.

create schema if not exists realtime;
create table if not exists realtime.messages (
  id bigserial primary key, topic text, extension text, payload jsonb, event text, private boolean,
  inserted_at timestamptz default now());
alter table realtime.messages enable row level security;
create or replace function realtime.send(payload jsonb, event text, topic text, private boolean default true)
returns void language sql as $$
  insert into realtime.messages (topic, extension, payload, event, private)
  values (topic, 'broadcast', payload, event, private);
$$;
create or replace function realtime.topic() returns text language sql stable as $$
  select nullif(current_setting('realtime.topic', true), '')
$$;

\i 040_sanntid_broadcast.sql
\i 040_sanntid_broadcast.sql

create temp table resultat (nr int, sjekk text, ok boolean);

-- Data: en klubb, et medlem, en fremmed, en kveld og en runde.
insert into auth.users (id) values ('00000000-0000-4000-8000-0000000000a1'), ('00000000-0000-4000-8000-0000000000a2');
set session_replication_role = replica;
insert into public.clubs (id, name, join_code) values ('00000000-0000-4000-8000-0000000000c1', 'Prøveklubb', 'PROVE40X01');
insert into public.club_members (id, club_id, user_id, display_name, status, is_organizer)
values ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000c1',
        '00000000-0000-4000-8000-0000000000a1', 'Anna', 'active', true);
insert into public.seasons (id, club_id, name, status) values
  ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000c1', 'Høst', 'active');
insert into public.events (id, club_id, season_id, event_date) values
  ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-0000000000c1',
   '00000000-0000-4000-8000-0000000000f1', current_date);
set session_replication_role = origin;
insert into public.rounds (id, club_id, event_id, round_no, status, hole_count, first_hole, format,
                           handicap_allowance, external_handicap, weight, ld_enabled, kp_enabled)
values ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000c1',
        '00000000-0000-4000-8000-0000000000d1', 1, 'active', 18, 1, 'stableford', 1, false, 1, false, false);
insert into public.round_players (round_id, member_id, club_id, bay_no, is_marker)
values ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000e1',
        '00000000-0000-4000-8000-0000000000c1', 1, true);
delete from realtime.messages;
insert into public.hole_scores (round_id, member_id, hole_index, strokes)
values ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000e1', 0, 5);

insert into resultat values
 (1, 'en hullscore gir én melding på round: og én på club:',
  (select count(*) = 2 and bool_and(event = 'change' and private and payload ->> 'table' = 'hole_scores')
     and count(*) filter (where topic = 'round:00000000-0000-4000-8000-0000000000b1') = 1
     and count(*) filter (where topic = 'club:00000000-0000-4000-8000-0000000000c1') = 1
   from realtime.messages)),
 (2, 'fire triggere', (select count(*) = 4 from pg_trigger where tgname like '%\_broadcast' escape '\'));

delete from realtime.messages;
update public.rounds set status = 'locked', locked_at = now() where id = '00000000-0000-4000-8000-0000000000b1';
insert into resultat values (3, 'låsing av runden gir melding med table = rounds',
  (select count(*) = 2 and bool_and(payload ->> 'table' = 'rounds' and payload ->> 'op' = 'update') from realtime.messages));

-- Tilgangen: medlemmet kan lytte på runden og klubben, den fremmede ikke. Ukjente kanaler: nei.
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', false);
insert into resultat values
 (4, 'medlem: round: og club: ja',
  public.can_listen_topic('round:00000000-0000-4000-8000-0000000000b1')
  and public.can_listen_topic('club:00000000-0000-4000-8000-0000000000c1')),
 (5, 'ukjent kanal og ugyldig id: nei',
  not public.can_listen_topic('tavla:x') and not public.can_listen_topic('round:ikke-en-id')
  and not public.can_listen_topic('round:00000000-0000-4000-8000-0000000000b1; drop table x'));
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a2', false);
insert into resultat values
 (6, 'fremmed: nei',
  not public.can_listen_topic('round:00000000-0000-4000-8000-0000000000b1')
  and not public.can_listen_topic('club:00000000-0000-4000-8000-0000000000c1'));

-- Policyen bruker realtime.topic(): som medlem med kanalen satt ser man meldingene, som fremmed ikke.
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', false);
select set_config('realtime.topic', 'round:00000000-0000-4000-8000-0000000000b1', false);
grant usage on schema realtime to authenticated;
grant execute on function realtime.topic() to authenticated;
grant select on realtime.messages to authenticated;
set role authenticated;
create temp table sett_medlem as select count(*) n from realtime.messages;
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a2', false);
set role authenticated;
create temp table sett_fremmed as select count(*) n from realtime.messages;
reset role;
insert into resultat values (7, 'policy: medlemmet ser meldingene, den fremmede ikke',
  (select n > 0 from sett_medlem) and (select n = 0 from sett_fremmed));

-- Sendingen feiler: skrivingen går gjennom likevel.
create or replace function realtime.send(payload jsonb, event text, topic text, private boolean default true)
returns void language plpgsql as $$ begin raise exception 'nede'; end $$;
insert into public.hole_scores (round_id, member_id, hole_index, strokes)
values ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000e1', 1, 4);
insert into resultat values (8, 'feil i realtime.send stopper ikke føringen',
  (select count(*) = 2 from public.hole_scores where round_id = '00000000-0000-4000-8000-0000000000b1'));

select nr, sjekk, case when ok then 'ok' else 'FEIL' end as svar from resultat order by nr;
