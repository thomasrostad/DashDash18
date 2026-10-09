-- 037: Mengdebaserte RPC-er (fase 24, punkt 3).
--
-- Lasttesten (docs/fase-22-turnering-som-kjerne.md kap. 9) viste at «hent alt og la RLS filtrere»
-- vokser med hele tabellen: profiles-policyen kaller can_see_profile for hver profil i basen,
-- og rounds/competitions/activity sjekker hver rad. Funksjonene her finner først kandidatene
-- dine som mengder (klubbene, rundene og turneringene dine), og sjekker så bare dem med de samme
-- hjelperne som policyene bruker. Svaret er det samme som RLS gir. Appen sorterer og begrenser
-- som før (PostgREST: select, order og limit på svaret).
--
--   known_profiles()            «folk du kjenner»: profilene can_see_profile slipper gjennom, uten deg
--   my_loose_rounds()           løse runder du kan se (club_id null, ikke kladd)
--   my_competitions()           turneringene du kan se (competitions_select + competitions_select_staff)
--   my_activity(klubber, siden) aktiviteten du kan se i klubbene, fra et tidspunkt
--
-- Bare lesing. Endrer ingen tabeller, policyer eller hjelpere. Idempotent.

-- «Folk du kjenner»: de samme fem veiene som can_see_profile, som mengder.
create or replace function public.known_profiles()
returns setof public.profiles
language sql
stable
security definer
set search_path = ''
as $$
  with me as (select auth.uid() as id),
  candidates as (
    -- Felles klubb (du aktiv, den andre med hvilken som helst status).
    select b.user_id as id
      from public.club_members a join public.club_members b on b.club_id = a.club_id, me
     where a.user_id = me.id and a.status = 'active' and b.user_id is not null
    union
    -- Felles runde.
    select b.profile_id
      from public.round_participants a join public.round_participants b on b.round_id = a.round_id, me
     where a.profile_id = me.id and b.profile_id is not null
    union
    -- Løs runde du eier, eller som eieren har deg med i.
    select b.profile_id
      from public.rounds r join public.round_participants b on b.round_id = r.id, me
     where r.club_id is null and r.owner_id = me.id and b.profile_id is not null
    union
    select r.owner_id
      from public.rounds r join public.round_participants b on b.round_id = r.id, me
     where r.club_id is null and b.profile_id = me.id and r.owner_id is not null
    union
    -- Felles turnering (begge aktive).
    select b.profile_id
      from public.competition_participants a
      join public.competition_participants b on b.competition_id = a.competition_id, me
     where a.profile_id = me.id and b.profile_id is not null and a.status = 'active' and b.status = 'active'
    union
    -- Turnering uten klubb du eier, eller som eieren har deg med i.
    select b.profile_id
      from public.competitions c join public.competition_participants b on b.competition_id = c.id, me
     where c.club_id is null and b.status = 'active' and c.owner_id = me.id and b.profile_id is not null
    union
    select c.owner_id
      from public.competitions c join public.competition_participants b on b.competition_id = c.id, me
     where c.club_id is null and b.status = 'active' and b.profile_id = me.id and c.owner_id is not null
  )
  select p.*
    from public.profiles p, me
   where me.id is not null
     and p.id in (select id from candidates)
     and p.id <> me.id
     and not public.blocked_between(p.id);
$$;

-- Turneringene du kan lese: kandidatene som mengder, så can_read_competition per kandidat.
create or replace function public.my_competition_ids()
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(c.id), '{}')
    from public.competitions c
   where c.id in (
           select x.id from public.competitions x
            where x.club_id in (select m.club_id from public.club_members m
                                 where m.user_id = auth.uid() and m.status = 'active')
           union
           select x.id from public.competitions x where x.club_id is null and x.owner_id = auth.uid()
           union
           select unnest(public.my_entered_competition_ids())
           union
           select unnest(public.my_staff_competition_ids()))
     and public.can_read_competition(c.id);
$$;

create or replace function public.my_competitions()
returns setof public.competitions
language sql
stable
security definer
set search_path = ''
as $$
  select c.* from public.competitions c where c.id = any (public.my_competition_ids());
$$;

-- Løse runder du kan se. Kandidatene: du eier, du er med, rundene i turneringene du kan lese,
-- og rundene på spilledagene i turneringene der du er påmeldt eller i staben. Så can_read_round
-- per kandidat, som rounds-policyene.
create or replace function public.my_loose_rounds()
returns setof public.rounds
language sql
stable
security definer
set search_path = ''
as $$
  select r.*
    from public.rounds r
   where r.club_id is null
     and r.status <> 'draft'
     and r.id in (
           select x.id from public.rounds x where x.club_id is null and x.owner_id = auth.uid()
           union
           select p.round_id from public.round_participants p where p.profile_id = auth.uid()
           union
           select cr.round_id from public.competition_rounds cr
            where cr.competition_id = any (public.my_competition_ids())
           union
           select x.id from public.rounds x join public.events e on e.id = x.event_id
            where e.competition_id = any (public.my_entered_competition_ids() || public.my_staff_competition_ids()))
     and public.can_read_round(r.id);
$$;

-- Aktiviteten du kan se i klubbene, fra p_since: samme vilkår som activity_select, men
-- medlemskapet, medlems-id-en og arrangørrollen slås opp én gang per klubb.
create or replace function public.my_activity(p_club_ids uuid[], p_since timestamptz)
returns setof public.activity
language sql
stable
security definer
set search_path = ''
as $$
  with mine as (
    select c.id as club_id, public.my_member_id(c.id) as member_id, public.is_club_organizer(c.id) as organizer
      from unnest(p_club_ids) as c(id)
     where public.is_club_member(c.id)
  )
  select a.*
    from public.activity a join mine on mine.club_id = a.club_id
   where a.created_at >= p_since
     and (a.recipients is null or mine.member_id = any (a.recipients)
          or a.actor_member_id = mine.member_id or mine.organizer)
     and (a.round_id is null or public.can_read_round(a.round_id));
$$;

revoke all on function public.known_profiles() from public, anon;
revoke all on function public.my_competition_ids() from public, anon;
revoke all on function public.my_competitions() from public, anon;
revoke all on function public.my_loose_rounds() from public, anon;
revoke all on function public.my_activity(uuid[], timestamptz) from public, anon;
grant execute on function public.known_profiles() to authenticated;
grant execute on function public.my_competition_ids() to authenticated;
grant execute on function public.my_competitions() to authenticated;
grant execute on function public.my_loose_rounds() to authenticated;
grant execute on function public.my_activity(uuid[], timestamptz) to authenticated;

-- Rull tilbake:
-- drop function if exists public.my_activity(uuid[], timestamptz);
-- drop function if exists public.my_loose_rounds();
-- drop function if exists public.my_competitions();
-- drop function if exists public.my_competition_ids();
-- drop function if exists public.known_profiles();
