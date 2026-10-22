-- 070: svarene på de nye tippespørsmålene (trinn 2 av «Utvide tippekupongen»). IKKE KJØRT.
--
-- Hva: én ny kolonne public.tips.answers (jsonb, standard {}). Nøkkelen er spørsmålets id fra
-- regelsettet (Ruleset.TipsRules.questions), verdien er svaret: true/false (ja/nei, over/under) eller
-- id-en til et medlem (spillerspørsmål). Eksempel: {"mostBirdies": "<member-id>", "winnerPoints": true}.
-- Spørsmålene som kommer senere, trenger da ingen ny migrering.
--
-- De fem gamle kolonnene (winner, front_nine, most_pars, birdie, over_line) står og brukes som før for
-- de fem gamle spørsmålene. Appen 1.0.1 leser og skriver bare dem: upsert-en derfra nevner ikke
-- answers, så den rører ikke svarene i den kolonnen.
--
-- Fasit og poeng lagres fortsatt ikke; de regnes i appen fra hullscorene.
--
-- Sjekkene:
--   * tips_answers_check: answers er et JSON-objekt og høyst 2000 byte som tekst.
--   * tips_before_write (fra 008) får en sjekk til: høyst 20 svar; nøkkelen er et id-navn (bokstav først,
--     så bokstaver og tall, høyst 40 tegn); verdien er true/false eller id-en til et medlem i samme klubb.
--     Ellers 22023. Resten av funksjonen er som i 008.
-- RLS, policyer og rettigheter er uendret: kolonnen følger raden (andres kuponger skjult til låst,
-- skrive bare mens tips_open). tips_submitted gir fortsatt ikke svarene.
--
-- Krever 008. Rullebakke nederst.

begin;

alter table public.tips
  add column if not exists answers jsonb not null default '{}'::jsonb;

alter table public.tips drop constraint if exists tips_answers_check;
alter table public.tips add constraint tips_answers_check
  check (jsonb_typeof(answers) = 'object' and octet_length(answers::text) <= 2000);

comment on column public.tips.answers is
  'Svar på spørsmål utenom de fem gamle (070). Nøkkel = spørsmålets id i regelsettet, verdi = '
  'true/false eller et medlems id. De fem gamle står i egne kolonner (appen 1.0.1 leser bare dem).';

-- --- tips: tidene settes av serveren, nøklene står fast, svarene sjekkes ----
create or replace function public.tips_before_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text;
  v_value jsonb;
begin
  if tg_op = 'INSERT' then
    new.created_at := now();
  else
    if new.event_id is distinct from old.event_id
       or new.member_id is distinct from old.member_id
       or new.club_id is distinct from old.club_id then
      raise exception 'Et tips kan ikke flyttes til en annen kveld eller spiller'
        using errcode = '22023';
    end if;
    new.created_at := old.created_at;
  end if;

  -- 070: svarene på de nye spørsmålene.
  if (select count(*) from jsonb_object_keys(new.answers)) > 20 then
    raise exception 'For mange svar på kupongen' using errcode = '22023';
  end if;
  for v_key, v_value in select e.key, e.value from jsonb_each(new.answers) e loop
    if v_key !~ '^[A-Za-z][A-Za-z0-9]{0,39}$' then
      raise exception 'Ukjent spørsmål på kupongen' using errcode = '22023';
    end if;
    continue when jsonb_typeof(v_value) = 'boolean';
    if jsonb_typeof(v_value) <> 'string'
       or (v_value #>> '{}') !~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$' then
      raise exception 'Et svar må være ja/nei eller en spiller' using errcode = '22023';
    end if;
    if not exists (select 1 from public.club_members m
                   where m.id = (v_value #>> '{}')::uuid and m.club_id = new.club_id) then
      raise exception 'Spilleren på kupongen finnes ikke i klubben' using errcode = '22023';
    end if;
  end loop;

  new.updated_at := now();
  return new;
end;
$$;
revoke all on function public.tips_before_write() from public, anon, authenticated;
-- Triggeren fra 008 (before insert or update on public.tips) peker på funksjonen og står som den er.

-- --- Kontroll ---------------------------------------------------------------
do $$
declare
  v_ok int := 0;
begin
  -- 1. Kolonnen finnes, er jsonb og aldri null.
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'tips' and column_name = 'answers'
               and data_type = 'jsonb' and is_nullable = 'NO') then
    v_ok := v_ok + 1;
  end if;
  -- 2. Sjekken på objekt og størrelse finnes.
  if exists (select 1 from pg_constraint
             where conname = 'tips_answers_check' and conrelid = 'public.tips'::regclass) then
    v_ok := v_ok + 1;
  end if;
  -- 3. Triggerfunksjonen er 070-utgaven, og triggeren peker på den.
  if position('070: svarene' in pg_get_functiondef('public.tips_before_write()'::regprocedure)) > 0
     and exists (select 1 from pg_trigger
                 where tgname = 'tips_before_write' and tgrelid = 'public.tips'::regclass) then
    v_ok := v_ok + 1;
  end if;
  -- 4. Kupongene fra før har tomme svar (ingenting endret for dem).
  if not exists (select 1 from public.tips where answers <> '{}'::jsonb) then
    v_ok := v_ok + 1;
  end if;
  -- 5. Ingen kan kalle triggerfunksjonen direkte.
  if not has_function_privilege('anon', 'public.tips_before_write()', 'execute')
     and not has_function_privilege('authenticated', 'public.tips_before_write()', 'execute') then
    v_ok := v_ok + 1;
  end if;
  if v_ok <> 5 then
    raise exception '070: kontroll % av 5', v_ok;
  end if;
  raise notice '070 kontroll: 5 av 5';
end $$;

commit;

-- PRØVE PÅ TEST ETTERPÅ (rulles tilbake; bytt inn en ekte kupong og to medlemmer fra test):
-- begin;
--   -- ok: ja/nei og et medlem i klubben
--   update public.tips set answers = '{"birdieCount": true, "mostBirdies": "<medlem i klubben>"}'
--     where event_id = '<kveld>' and member_id = '<medlem>';
--   -- 22023: feil type, ukjent nøkkel, medlem i en annen klubb, ikke et objekt (23514)
--   update public.tips set answers = '{"birdieCount": 3}' where event_id = '<kveld>' and member_id = '<medlem>';
--   update public.tips set answers = '{"ikke lov!": true}' where event_id = '<kveld>' and member_id = '<medlem>';
--   update public.tips set answers = '{"mostBirdies": "<medlem i en annen klubb>"}' where event_id = '<kveld>' and member_id = '<medlem>';
--   update public.tips set answers = '[]' where event_id = '<kveld>' and member_id = '<medlem>';
-- rollback;
-- (Kjør hver linje for seg; en feil avbryter transaksjonen.)

-- RULLEBAKKE (sletter svarene på de nye spørsmålene; de fem gamle står):
-- begin;
-- create or replace function public.tips_before_write()
-- returns trigger
-- language plpgsql
-- security definer
-- set search_path = ''
-- as $$
-- begin
--   if tg_op = 'INSERT' then
--     new.created_at := now();
--   else
--     if new.event_id is distinct from old.event_id
--        or new.member_id is distinct from old.member_id
--        or new.club_id is distinct from old.club_id then
--       raise exception 'Et tips kan ikke flyttes til en annen kveld eller spiller'
--         using errcode = '22023';
--     end if;
--     new.created_at := old.created_at;
--   end if;
--   new.updated_at := now();
--   return new;
-- end;
-- $$;
-- revoke all on function public.tips_before_write() from public, anon, authenticated;
-- alter table public.tips drop constraint if exists tips_answers_check;
-- alter table public.tips drop column if exists answers;
-- commit;
