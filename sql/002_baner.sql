-- ===========================================================================
-- 002 – Banebiblioteket: lagre bane og hull i én transaksjon (FORSLAG)
-- ===========================================================================
-- IKKE KJØRT. Til godkjenning. Kjøres først mot test.
--
-- Hvorfor: RLS i 001 lar arrangøren gjøre alt banebiblioteket trenger, så
-- ingenting er sperret. Men å lagre en bane er flere skrivinger (courses, så
-- slette hull som er borte ved 18 → 9, så upsert av course_holes). I dag gjør
-- appen det som tre forespørsler (`CourseLibraryModel.save`). Feiler en av de
-- to siste, står banen med nytt navn og gamle hull. CLAUDE.md sier RPC når en
-- handling skriver flere rader. Når denne er kjørt, bytter appen til
-- `save_course` og `confirm_course`.
--
-- `confirm_course` setter i tillegg `confirmed_at = now()` på serveren, i
-- stedet for telefonens klokke, og `confirmed_by` til mitt eget medlems-id i
-- klubben (ikke et id klienten sender inn).
--
-- SECURITY INVOKER: RLS i 001 gjør tilgangskontrollen, som for direkte
-- skriving. Feilkoder som før: 42501, 23505 (navn eller indeks), 23514, 23503.
-- ===========================================================================

begin;

-- --- save_course: ny eller endret bane med alle hullene ---------------------
-- p_course_id null = ny bane. p_holes er en jsonb-liste med
-- {hole_number, par, stroke_index, length_m}; tom liste = ikke satt opp.
-- Hullene som ikke står i lista, slettes.
create or replace function public.save_course(
  p_club_id        uuid,
  p_course_id      uuid,
  p_name           text,
  p_external_name  text,
  p_course_rating  numeric,
  p_slope_rating   smallint,
  p_in_use         boolean,
  p_holes          jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not public.is_club_organizer(p_club_id) then
    raise exception 'Bare arrangøren kan endre banene' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_holes, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_holes, '[]'::jsonb)) not in (0, 9, 18) then
    raise exception 'En bane har 9 eller 18 hull' using errcode = '22023';
  end if;

  if p_course_id is null then
    insert into public.courses (club_id, name, external_name, course_rating, slope_rating, in_use)
    values (p_club_id, btrim(p_name), nullif(btrim(p_external_name), ''),
            p_course_rating, p_slope_rating, coalesce(p_in_use, true))
    returning id into v_id;
  else
    update public.courses
       set name = btrim(p_name),
           external_name = nullif(btrim(p_external_name), ''),
           course_rating = p_course_rating,
           slope_rating = p_slope_rating,
           in_use = coalesce(p_in_use, true)
     where id = p_course_id and club_id = p_club_id
    returning id into v_id;
    if v_id is null then
      raise exception 'Fant ikke banen' using errcode = 'P0002';
    end if;
  end if;

  delete from public.course_holes h
   where h.course_id = v_id
     and h.hole_number not in (
       select (e->>'hole_number')::smallint from jsonb_array_elements(coalesce(p_holes, '[]'::jsonb)) e);

  insert into public.course_holes (course_id, hole_number, par, stroke_index, length_m)
  select v_id,
         (e->>'hole_number')::smallint,
         (e->>'par')::smallint,
         (e->>'stroke_index')::smallint,
         (e->>'length_m')::smallint
    from jsonb_array_elements(coalesce(p_holes, '[]'::jsonb)) e
  on conflict (course_id, hole_number) do update
     set par = excluded.par,
         stroke_index = excluded.stroke_index,
         length_m = excluded.length_m;

  return v_id;
end;
$$;
revoke all on function public.save_course(uuid, uuid, text, text, numeric, smallint, boolean, jsonb) from public, anon;
grant execute on function public.save_course(uuid, uuid, text, text, numeric, smallint, boolean, jsonb) to authenticated;


-- --- confirm_course: «Bekreft mot skjermen» ---------------------------------
create or replace function public.confirm_course(p_course_id uuid)
returns timestamptz
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_at timestamptz;
begin
  update public.courses c
     set confirmed_by = public.my_member_id(c.club_id),
         confirmed_at = now()
   where c.id = p_course_id
     and public.is_club_organizer(c.club_id)
  returning c.confirmed_at into v_at;
  if v_at is null then
    raise exception 'Fant ikke banen, eller du er ikke arrangør' using errcode = '42501';
  end if;
  return v_at;
end;
$$;
revoke all on function public.confirm_course(uuid) from public, anon;
grant execute on function public.confirm_course(uuid) to authenticated;

commit;

-- Kontroll (som arrangør i appen eller med satt JWT i SQL Editor):
-- select public.save_course('<klubb>', null, 'Prøvebane', null, null, null, true,
--   '[{"hole_number":1,"par":4,"stroke_index":1,"length_m":350}, … 9 hull …]');
-- select count(*) from public.course_holes where course_id = '<ny id>';  -- 9
