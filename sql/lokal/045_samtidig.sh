#!/bin/bash
# ===========================================================================
# KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
# ===========================================================================
# Samtidighet for 045: mange økter melder seg på (og av) samme kveld på en gang.
# Skriver data som blir stående, så kjør på en kopi som kastes etterpå:
#
#   pg.sh createdb -T <base med 045> p045c
#   bash sql/lokal/045_samtidig.sh "<pg.sh> psql -d p045c"
#   pg.sh dropdb p045c
#
# Første argument er psql-kommandoen (med -d). Klubben Golfgutu fra den lokale
# verdenen (aaaaaaaa-…-0001) brukes. 30 nye spillere, kvelden har tak 7.
# Runde 1: alle 30 svarer «kommer» samtidig (halvparten med RPC-en, halvparten som
# gamle bygg med upsert), hver i en transaksjon som holder på litt etter svaret.
# Runde 2: 5 bekreftede melder av mens 5 på ventelista blir usikre, samtidig.
# Skal gi: aldri mer enn 7 bekreftet, ventelista i tidsrekkefølge, ingen venter
# mens det er ledig plass, og loggen har én linje per endring.
set -u
PSQL="$1"
G='aaaaaaaa-0000-0000-0000-000000000001'
E='eeeeeeee-0000-0000-0000-00000000045c'

$PSQL -q -v ON_ERROR_STOP=1 <<SQL
insert into auth.users (id)
select ('00000000-0000-0000-0000-0000000451' || lpad(n::text, 2, '0'))::uuid from generate_series(1, 30) n;
insert into public.club_members (id, club_id, user_id, display_name, status)
select ('11111111-0000-0000-0000-0000000451' || lpad(n::text, 2, '0'))::uuid, '$G',
       ('00000000-0000-0000-0000-0000000451' || lpad(n::text, 2, '0'))::uuid, 'Samtidig ' || n, 'active'
  from generate_series(1, 30) n;
insert into public.events (id, club_id, event_date, max_players) values ('$E', '$G', '2032-01-01', 7);
SQL

svar() { # n status måte
  local uid="00000000-0000-0000-0000-0000000451$(printf %02d "$1")"
  local mid="11111111-0000-0000-0000-0000000451$(printf %02d "$1")"
  local sql
  if [ "$3" = rpc ]; then
    sql="select public.evening_signup('$E', '$2');"
  else
    sql="insert into public.signups (event_id, member_id, club_id, status) values ('$E', '$mid', '$G', '$2')
         on conflict (event_id, member_id) do update set status = excluded.status;"
  fi
  $PSQL -q -o /dev/null <<SQL
set role authenticated;
select set_config('request.jwt.claim.sub', '$uid', false);
begin;
$sql
select pg_sleep(0.05);
commit;
SQL
}

for n in $(seq 1 30); do
  if [ $((n % 2)) -eq 0 ]; then svar "$n" yes rpc & else svar "$n" yes direct & fi
done
wait

$PSQL -At <<SQL
select 'runde 1: bekreftet ' || private.evening_confirmed('$E') || ', venteliste ' || (select count(*) from private.evening_waitlist('$E'));
SQL

# Runde 2: fem bekreftede melder av, fem på ventelista blir usikre, samtidig.
BEKREFTET=$($PSQL -At -c "select right(member_id::text, 2)::int from public.signups where event_id = '$E' and status = 'yes' and waitlisted_at is null order by member_id limit 5")
VENTER=$($PSQL -At -c "select right(w.member_id::text, 2)::int from private.evening_waitlist('$E') w order by w.place desc limit 5")
for n in $BEKREFTET; do svar "$n" no rpc & done
for n in $VENTER; do svar "$n" maybe direct & done
wait

$PSQL -At <<SQL
select 'runde 2: bekreftet ' || private.evening_confirmed('$E') || ', venteliste ' || (select count(*) from private.evening_waitlist('$E'));
select case when private.evening_confirmed('$E') = 7 then 'ok aldri over taket, og full etter opprykk'
            else 'FEIL bekreftet ' || private.evening_confirmed('$E') end;
select case when (select count(*) from private.evening_waitlist('$E')) = 30 - 5 - 5 - 7 then 'ok ventelista har resten (13)'
            else 'FEIL ventelista ' || (select count(*) from private.evening_waitlist('$E')) end;
select case when (select bool_and(a.waitlisted_at < b.waitlisted_at) from private.evening_waitlist('$E') a
                    join private.evening_waitlist('$E') b on b.place = a.place + 1)
            then 'ok ventelista i tidsrekkefølge' else 'FEIL rekkefølgen' end;
select case when (select count(*) from public.signup_log where event_id = '$E' and note = 'promoted') = 5
            then 'ok fem opprykk, ett per ledige plass' else 'FEIL opprykk ' ||
            (select count(*) from public.signup_log where event_id = '$E' and note = 'promoted') end;
select case when (select count(*) from public.signup_log where event_id = '$E') = 30 + 5 + 5 + 5
            then 'ok loggen: 30 svar, 5 av, 5 usikre, 5 opprykk' else 'FEIL loggen ' ||
            (select count(*) from public.signup_log where event_id = '$E') end;
select case when (select count(*) from public.activity where event_id = '$E' and kind = 'waitlist_promoted') = 5
            and (select count(*) from public.activity where event_id = '$E' and kind = 'signup_dropped') = 5
            then 'ok fem varsler om opprykk og fem om avmelding' else 'FEIL varslene' end;
SQL
