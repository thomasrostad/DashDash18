\set ON_ERROR_STOP on
\pset footer off
-- KUN LOKALT. Prøve for 041 (TV-kode) og 042 (tidsvindu) i en database med 001–040 og dataene fra
-- lokal/033_for.sql. Kjører begge filene to ganger, så sjekkene. Alt som skrives, rulles tilbake.

\i 041_tv_kode.sql
\i 041_tv_kode.sql
\i 042_tidsvindu.sql
\i 042_tidsvindu.sql

begin;
create temp table resultat (nr int, sjekk text, ok boolean);
grant all on resultat to anon, authenticated;
create temp table fakta (k text primary key, v text);
grant all on fakta to anon, authenticated;

-- ===== 042: tidsvindu =====
insert into fakta values
  ('gg_lenker', (select count(*)::text from public.competition_rounds cr join public.competitions c on c.id = cr.competition_id where c.season_id is not null));

do $$
declare c record; deltaker uuid; fremmed uuid; r1 uuid; r2 uuid; r3 uuid;
begin
  select * into c from public.competitions where name = 'Morrocupen';
  select coalesce(p.profile_id, m.user_id) into deltaker
    from public.competition_participants p left join public.club_members m on m.id = p.member_id
   where p.competition_id = c.id and p.status = 'active' limit 1;
  select pr.id into fremmed from public.profiles pr where pr.id <> deltaker limit 1;
  if deltaker is null then raise exception 'prøvedata mangler en påmeldt med profil'; end if;
  update public.competitions set auto_count = true, starts_on = current_date - 10, ends_on = current_date + 10 where id = c.id;

  -- r1: påmeldt spiller, i perioden → teller
  insert into public.rounds (club_id, owner_id, round_no, status, hole_count, first_hole, format, handicap_allowance,
                             external_handicap, weight, ld_enabled, kp_enabled)
  values (null, deltaker, 1, 'draft', 18, 1, 'stableford', 1, false, 1, false, false) returning id into r1;
  insert into public.round_participants (round_id, profile_id, display_name) values (r1, deltaker, 'Deltaker');
  insert into resultat values (1, 'kladd teller ikke', not exists (select 1 from public.competition_rounds where round_id = r1));
  update public.rounds set status = 'active', started_at = now() where id = r1;
  insert into resultat values (2, 'påmeldt i perioden: runden teller når den starter',
    exists (select 1 from public.competition_rounds where round_id = r1 and competition_id = c.id and source = 'manual'));
  update public.rounds set status = 'locked', locked_at = now() where id = r1;
  insert into resultat values (3, 'låsing gir ikke dobbel kobling',
    (select count(*) = 1 from public.competition_rounds where round_id = r1 and competition_id = c.id));

  -- r2: bare en som ikke er påmeldt → teller ikke
  insert into public.rounds (club_id, owner_id, round_no, status, hole_count, first_hole, format, handicap_allowance,
                             external_handicap, weight, ld_enabled, kp_enabled)
  values (null, fremmed, 1, 'draft', 18, 1, 'stableford', 1, false, 1, false, false) returning id into r2;
  insert into public.round_participants (round_id, profile_id, display_name) values (r2, fremmed, 'Fremmed');
  update public.rounds set status = 'active', started_at = now() where id = r2;
  insert into resultat values (4, 'ikke påmeldt: teller ikke', not exists (select 1 from public.competition_rounds where round_id = r2));
  -- ... men gjør det når den påmeldte legges til underveis
  insert into public.round_participants (round_id, profile_id, display_name) values (r2, deltaker, 'Deltaker');
  insert into resultat values (5, 'påmeldt lagt til i runden som går: teller',
    exists (select 1 from public.competition_rounds where round_id = r2 and competition_id = c.id));

  -- r3: utenfor perioden → teller ikke
  insert into public.rounds (club_id, owner_id, round_no, status, hole_count, first_hole, format, handicap_allowance,
                             external_handicap, weight, ld_enabled, kp_enabled, started_at)
  values (null, deltaker, 1, 'draft', 18, 1, 'stableford', 1, false, 1, false, false, now() - interval '60 days') returning id into r3;
  insert into public.round_participants (round_id, profile_id, display_name) values (r3, deltaker, 'Deltaker');
  update public.rounds set status = 'active' where id = r3;
  insert into resultat values (6, 'utenfor perioden: teller ikke', not exists (select 1 from public.competition_rounds where round_id = r3));

  -- av: uten auto_count teller ingenting av seg selv
  update public.competitions set auto_count = false where id = c.id;
  update public.rounds set status = 'locked' where id = r3;
  update public.rounds set started_at = now() where id = r3;
  insert into resultat values (7, 'uten auto_count: ingen kobling', not exists (select 1 from public.competition_rounds where round_id = r3));
end $$;
insert into resultat values (8, 'sesongenes koblinger er urørt (Golfgutu)',
  (select v::int from fakta where k = 'gg_lenker') =
  (select count(*) from public.competition_rounds cr join public.competitions c on c.id = cr.competition_id where c.season_id is not null));

-- ===== 041: TV-kode =====
do $$
declare s record; org uuid; spiller uuid; code1 text; code2 text; code3 text; liga uuid;
begin
  select * into s from public.competitions where name = 'Sesong 2026';
  select m.user_id into org from public.club_members m where m.club_id = s.club_id and m.is_organizer and m.user_id is not null limit 1;
  select m.user_id into spiller from public.club_members m where m.club_id = s.club_id and not m.is_organizer and m.user_id is not null limit 1;
  select id into liga from public.competitions where name = 'Torsdagsligaen';

  perform set_config('request.jwt.claim.sub', org::text, true);
  set local role authenticated;
  code1 := public.tv_code(s.id);
  code2 := public.tv_code(s.id);
  insert into fakta values ('kode', code1);
  insert into resultat values (9, 'arrangøren får en kode, og samme kode igjen', code1 ~ '^[A-HJ-NP-Z2-9]{10}$' and code1 = code2);
  code3 := public.tv_code(s.id, true);
  insert into resultat values (10, 'fornyet kode er ny', code3 <> code1);
  insert into fakta values ('ny', code3);
  insert into fakta values ('ligakode', public.tv_code(liga));
  reset role;

  if spiller is not null then
    perform set_config('request.jwt.claim.sub', spiller::text, true);
    set local role authenticated;
    begin
      perform public.tv_code(s.id);
      insert into resultat values (11, 'spiller kan ikke lage kode', false);
    exception when sqlstate '42501' then
      insert into resultat values (11, 'spiller kan ikke lage kode', true);
    end;
    reset role;
  else
    insert into resultat values (11, 'spiller kan ikke lage kode (ingen spiller i prøvedataene)', true);
  end if;
end $$;

-- Som anon (TV-en uten innlogging).
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
do $$
declare d jsonb; ok boolean;
begin
  d := public.tv_board_data(lower(' ' || (select v from fakta where k = 'ny') || ' '));
  insert into resultat values (12, 'anon leser tabellgrunnlaget med koden (mellomrom og små bokstaver går)',
    d -> 'competition' ->> 'name' = 'Sesong 2026' and jsonb_typeof(d -> 'scores') = 'array');
  insert into resultat values (13, 'ingen innlogging eller bilder i svaret',
    not exists (select 1 from jsonb_array_elements(d -> 'members') m where m ->> 'user_id' is not null or m ->> 'avatar_path' is not null));
  begin
    perform public.tv_board_data((select v from fakta where k = 'kode'));
    ok := false;
  exception when sqlstate 'P0002' then ok := true;
  end;
  insert into resultat values (14, 'tilbaketrukket kode: P0002', ok);
  begin
    perform public.tv_board_data('ABCDEFGHJK');
    ok := false;
  exception when sqlstate 'P0002' then ok := true;
  end;
  insert into resultat values (15, 'ukjent kode: P0002', ok);
  begin
    perform public.tv_board_data((select v from fakta where k = 'ligakode'));
    ok := false;
  exception when sqlstate 'P0002' then ok := true;
  end;
  insert into resultat values (16, 'liga (uten kvelder) er ikke med i første versjon: P0002', ok);
  begin
    perform public.tv_code((select id from public.competitions where name = 'Sesong 2026'));
    ok := false;
  exception when others then ok := true;
  end;
  insert into resultat values (17, 'anon kan ikke lage kode', ok);
end $$;
reset role;
insert into resultat values (18, 'tabellen tv_codes er stengt for anon og innloggede (ingen policy)',
  not exists (select 1 from pg_policies where tablename = 'tv_codes'));

select nr, sjekk, case when ok then 'ok' else 'FEIL' end as svar from resultat order by nr;
rollback;
