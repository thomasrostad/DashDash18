begin;
create temp table svar(steg text, t text);
grant all on svar to authenticated;
do $$
declare s record; c uuid; org uuid; spiller uuid; r jsonb; gg_for bigint; gg_etter bigint;
begin
  select se.id, se.name, se.club_id into s from public.seasons se where se.name = 'Test golf' limit 1;
  select id into c from public.competitions where season_id = s.id;
  select m.user_id into org from public.club_members m where m.club_id = s.club_id and m.is_organizer and m.status='active' and m.user_id is not null limit 1;
  select m.user_id into spiller from public.club_members m where m.club_id = s.club_id and not m.is_organizer and m.status='active' and m.user_id is not null limit 1;
  select count(*) into gg_for from public.hole_scores h join public.rounds r on r.id=h.round_id join public.clubs k on k.id=r.club_id where k.name ilike 'Golfgutu%';
  insert into svar values ('før', format('runder %s, kvelder %s, turnering %s, spiller funnet %s',
    (select count(*) from public.rounds r join public.events e on e.id=r.event_id where e.season_id=s.id),
    (select count(*) from public.events where season_id=s.id), c is not null, spiller is not null));

  if spiller is not null then
    perform set_config('request.jwt.claims', json_build_object('sub', spiller, 'role','authenticated')::text, true);
    set local role authenticated;
    begin perform public.delete_tournament(c, s.name); insert into svar values ('spiller','FEIL: fikk slette');
    exception when sqlstate '42501' then insert into svar values ('spiller','ok 42501'); end;
    reset role;
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', org, 'role','authenticated')::text, true);
  set local role authenticated;
  begin perform public.delete_tournament(c, 'feil navn'); insert into svar values ('feil navn','FEIL: fikk slette');
  exception when sqlstate '22023' then insert into svar values ('feil navn','ok 22023'); end;
  r := public.delete_tournament(c, ' ' || upper(s.name) || ' ');
  insert into svar values ('slettet', r::text);
  reset role;

  insert into svar values ('etter', format('sesong %s, turnering %s, kvelder %s, runder i klubben uten kveld %s',
    (select count(*) from public.seasons where id=s.id), (select count(*) from public.competitions where id=c),
    (select count(*) from public.events where season_id=s.id),
    (select count(*) from public.rounds where club_id=s.club_id and event_id is null)));
  select count(*) into gg_etter from public.hole_scores h join public.rounds r on r.id=h.round_id join public.clubs k on k.id=r.club_id where k.name ilike 'Golfgutu%';
  insert into svar values ('golfgutu', format('hullscorer før %s, etter %s', gg_for, gg_etter));
end $$;
select steg, t from svar;
rollback;
