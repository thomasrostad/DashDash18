-- Bare lesing: sammenligner tavla_data med RLS-spørringene som et vanlig medlem. Rulles tilbake.
begin;
create temp table sjekk (sesong text, del text, rpc bigint, rls bigint, lik boolean) on commit drop;
grant all on sjekk to authenticated;
do $$
declare s record; u uuid; d jsonb; t0 timestamptz; ms numeric;
begin
  for s in select se.id, se.name, se.club_id from public.seasons se
            where exists (select 1 from public.events e join public.rounds r on r.event_id = e.id where e.season_id = se.id)
  loop
    select m.user_id into u from public.club_members m
     where m.club_id = s.club_id and m.status = 'active' and m.user_id is not null and not m.is_organizer limit 1;
    if u is null then
      select m.user_id into u from public.club_members m
       where m.club_id = s.club_id and m.status = 'active' and m.user_id is not null limit 1;
    end if;
    perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    t0 := clock_timestamp();
    d := public.tavla_data(s.id);
    ms := extract(epoch from clock_timestamp() - t0) * 1000;
    insert into sjekk
    with ev as (select id from public.events where season_id = s.id),
         rr as (select * from public.rounds where event_id in (select id from ev) and status in ('active','locked')),
         cc as (select * from public.courses where id in (select course_id from rr))
    select s.name, x.del, x.a, x.b, x.ha = x.hb from (
      select 'events' del, jsonb_array_length(d->'events') a, (select count(*) from ev) b,
             (select md5(string_agg(v->>'id', ',' order by v->>'id')) from jsonb_array_elements(d->'events') v) ha,
             (select md5(string_agg(id::text, ',' order by id::text)) from ev) hb
      union all select 'members', jsonb_array_length(d->'members'), (select count(*) from public.club_members where club_id = s.club_id),
             (select md5(string_agg(v->>'id', ',' order by v->>'id')) from jsonb_array_elements(d->'members') v),
             (select md5(string_agg(id::text, ',' order by id::text)) from public.club_members where club_id = s.club_id)
      union all select 'rounds', jsonb_array_length(d->'rounds'), (select count(*) from rr),
             (select md5(string_agg(v->>'id', ',' order by v->>'id')) from jsonb_array_elements(d->'rounds') v),
             (select md5(string_agg(id::text, ',' order by id::text)) from rr)
      union all select 'round_holes', jsonb_array_length(d->'round_holes'), (select count(*) from public.round_holes where round_id in (select id from rr)),
             (select md5(string_agg(concat_ws('|', v->>'round_id', v->>'hole_index', v->>'par', v->>'stroke_index'), ',' order by concat_ws('|', v->>'round_id', v->>'hole_index', v->>'par', v->>'stroke_index'))) from jsonb_array_elements(d->'round_holes') v),
             (select md5(string_agg(concat_ws('|', round_id, hole_index, par, stroke_index), ',' order by concat_ws('|', round_id, hole_index, par, stroke_index))) from public.round_holes where round_id in (select id from rr))
      union all select 'players', jsonb_array_length(d->'players'), (select count(*) from public.round_players where round_id in (select id from rr)),
             (select md5(string_agg(concat_ws('|', v->>'round_id', v->>'member_id', v->>'playing_handicap'), ',' order by concat_ws('|', v->>'round_id', v->>'member_id', v->>'playing_handicap'))) from jsonb_array_elements(d->'players') v),
             (select md5(string_agg(concat_ws('|', round_id, member_id, playing_handicap), ',' order by concat_ws('|', round_id, member_id, playing_handicap))) from public.round_players where round_id in (select id from rr))
      union all select 'matches', jsonb_array_length(d->'matches'), (select count(*) from public.round_matches where round_id in (select id from rr)), null, null
      union all select 'claims', jsonb_array_length(d->'claims'), (select count(*) from public.side_claims where round_id in (select id from rr)), null, null
      union all select 'courses', jsonb_array_length(d->'courses'), (select count(*) from cc), null, null
      union all select 'course_holes', jsonb_array_length(d->'course_holes'), (select count(*) from public.course_holes where course_id in (select id from cc)), null, null
      union all select 'scores', jsonb_array_length(d->'scores'), (select count(*) from public.hole_scores where round_id in (select id from rr)),
             (select md5(string_agg(concat_ws('|', v->>'round_id', v->>'member_id', v->>'hole_index', v->>'strokes'), ',' order by concat_ws('|', v->>'round_id', v->>'member_id', v->>'hole_index', v->>'strokes'))) from jsonb_array_elements(d->'scores') v),
             (select md5(string_agg(concat_ws('|', round_id, member_id, hole_index, strokes), ',' order by concat_ws('|', round_id, member_id, hole_index, strokes))) from public.hole_scores where round_id in (select id from rr))
      union all select 'ms', round(ms), null, null, null
    ) x;
    execute 'reset role';
  end loop;
end $$;
select sesong, del, rpc, rls, coalesce(lik, rpc = rls) as ok from sjekk order by sesong, del;
rollback;
