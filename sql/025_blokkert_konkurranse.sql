-- ===========================================================================
-- 025 – BLOKKERT KAN IKKE BLI MED I KONKURRANSEN MED KODE – KJØRT PÅ TEST 08.10.2026
-- ===========================================================================
-- Status: godkjent og kjørt på test 08.10.2026 (kontrollen 7 av 7). Ikke prod. Prøvd mot en lokal, midlertidig Postgres
-- (sql/lokal/025_prove.sql). Krever 019 (user_blocks, blocked_between) og
-- 022 (competition_invites, competition_invite_preview,
-- claim_competition_invite). Kjøres etter 022 (og etter 023 og 024 om de er
-- kjørt; den rører ingen av dem).
--
-- Hvorfor (besluttet 08.10.2026): den som eieren av en privat konkurranse har
-- blokkert, skal ikke kunne bli med med invitasjonskoden. I dag kan eieren
-- ikke legge den blokkerte til selv (vakta på competition_participants fra
-- 017 spør can_see_profile, som har «ikke blokkert» fra 019), men koden
-- slipper hvem som helst inn, fordi den som melder seg på, melder på seg
-- selv, og deg selv ser du alltid.
--
-- Hvem er «eieren»: koden finnes bare for private konkurranser (club_id tom,
-- se competition_invite i 022), og der er eieren competitions.owner_id, den
-- eneste som styrer konkurransen (is_competition_admin). Klubbens
-- konkurranser har ingen kode og ingen enkelt eier (arrangørene styrer, og
-- medlemskapet i klubben avgjør hvem som kan melde seg på).
--
-- Retning: blokkering i BEGGE retninger (blocked_between fra 019), ikke bare
-- «eieren har blokkert deg». Det følger 019: én retning (i_blocked,
-- i_blocked_member) brukes bare til hva DU ser (tråden og reaksjonene), mens
-- alt som fører to personer sammen (runder og konkurranser, via
-- can_see_profile i vaktene) bruker begge retninger. Å bli med i noens
-- konkurranse er å bli ført sammen med eieren. Begge retninger betyr også at
-- koden ikke blir en bakdør eieren selv ikke har: eieren kan ikke melde på
-- noen det er en blokkering mot, uansett retning. Og den som blir avvist,
-- kan ikke vite sikkert om det er eieren som har blokkert (019: «Den
-- blokkerte får ikke vite det»).
--
-- Bare eieren teller. En blokkering mellom deg og en annen påmeldt stopper
-- deg ikke: da kunne en hvilken som helst påmeldt stenge folk ute, og
-- avvisningen ville røpet hvem som er med.
--
-- Hva fila gjør (create or replace, samme signatur, samme rettigheter):
--   * competition_invite_preview(kode): finnes det en blokkering mellom deg
--     og eieren, og du ikke er påmeldt fra før, svarer den som for en ukjent
--     kode (P0002, «Fant ingen konkurranse med den koden …»). Navnet på
--     konkurransen og eieren vises ikke.
--   * claim_competition_invite(kode): finnes det en blokkering mellom deg og
--     eieren, og du ikke er aktivt påmeldt, avvises du med egen SQLSTATE
--     DDB01 («Du kan ikke bli med i denne konkurransen»). Det gjelder også
--     den som har meldt seg av og vil på igjen. Er du allerede påmeldt, svarer
--     den «already» som før (blokkeringen tar ingen ut; det gjør eieren).
--   * join_competition endres ikke: en privat konkurranse kan bare leses av
--     eieren og de påmeldte (can_read_competition), så «Meld meg på» er ingen
--     vei inn for andre enn dem som er med fra før. Klubbens konkurranser har
--     ingen eier å blokkere.
--
-- Mønsteret fra 001–024 følges: én transaksjon, idempotent, `set search_path
-- = ''`, `revoke … from public, anon` ETTER hver create or replace.
-- ===========================================================================

begin;


-- --- competition_invite_preview: hva du blir med i -------------------------------
-- Som i 022, pluss: en blokkering mellom deg og eieren (begge retninger) gir
-- samme svar som en ukjent kode, så en blokkert ikke ser navnet på
-- konkurransen eller eieren. Er du påmeldt fra før, ser du den som før (du
-- ser den uansett i appen).
create or replace function public.competition_invite_preview(p_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_c       public.competitions;
  v_code    text := public.round_invite_normalize(p_code);
  v_entered boolean;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  select c.* into v_c
  from public.competition_invites i
  join public.competitions c on c.id = i.competition_id
  where i.code = v_code and i.expires_at > now() and c.club_id is null;
  if not found then
    raise exception 'Fant ingen konkurranse med den koden. Den kan ha gått ut.' using errcode = 'P0002';
  end if;

  v_entered := exists (select 1 from public.competition_participants cp
                       where cp.competition_id = v_c.id and cp.status = 'active'
                         and cp.profile_id = auth.uid());
  -- Blokkert (025): som en ukjent kode. Sjekkes før «ferdig», så svaret ikke
  -- røper at koden finnes.
  if not v_entered and v_c.owner_id is not null and public.blocked_between(v_c.owner_id) then
    raise exception 'Fant ingen konkurranse med den koden. Den kan ha gått ut.' using errcode = 'P0002';
  end if;
  if v_c.status = 'finished' then
    raise exception 'Konkurransen er ferdig' using errcode = '55000';
  end if;

  return jsonb_build_object(
    'competition_id', v_c.id,
    'name',           v_c.name,
    'kind',           v_c.kind,
    'owner_name',     (select p.display_name from public.profiles p where p.id = v_c.owner_id),
    'entrants',       (select count(*) from public.competition_participants cp
                       where cp.competition_id = v_c.id and cp.status = 'active'),
    'entered',        v_entered
  );
end;
$$;
revoke all on function public.competition_invite_preview(text) from public, anon;
grant execute on function public.competition_invite_preview(text) to authenticated;


-- --- claim_competition_invite: «Bli med» ------------------------------------------
-- Som i 022, pluss: en blokkering mellom deg og eieren (begge retninger)
-- avviser deg med DDB01 før noe skrives, også når du har meldt deg av og vil
-- på igjen. Er du allerede påmeldt, svarer den «already» som før.
create or replace function public.claim_competition_invite(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me    public.profiles;
  v_c     public.competitions;
  v_code  text := public.round_invite_normalize(p_code);
  v_row   public.competition_participants;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  select c.* into v_c
  from public.competition_invites i
  join public.competitions c on c.id = i.competition_id
  where i.code = v_code and i.expires_at > now() and c.club_id is null;
  if not found then
    raise exception 'Fant ingen konkurranse med den koden. Den kan ha gått ut.' using errcode = 'P0002';
  end if;
  -- Lås konkurransen, så trekningen og påmeldingen ikke krysser hverandre.
  select * into v_c from public.competitions c where c.id = v_c.id for update;

  v_me := public.ensure_profile();
  select * into v_row from public.competition_participants cp
  where cp.competition_id = v_c.id and cp.profile_id = v_me.id;
  if v_row.id is not null and v_row.status = 'active' then
    return jsonb_build_object('competition_id', v_c.id, 'participant_id', v_row.id, 'joined', 'already');
  end if;

  -- Blokkert (025): før «ferdig» og «trukket», så svaret ikke sier mer.
  if v_c.owner_id is not null and public.blocked_between(v_c.owner_id) then
    raise exception 'Du kan ikke bli med i denne konkurransen' using errcode = 'DDB01';
  end if;
  if v_c.status = 'finished' then
    raise exception 'Konkurransen er ferdig' using errcode = '55000';
  end if;
  if v_c.kind = 'cup' and exists (select 1 from public.competition_matches where competition_id = v_c.id) then
    raise exception 'Cupen er trukket. Spør eieren.' using errcode = '55000';
  end if;

  if v_row.id is not null then
    update public.competition_participants set status = 'active' where id = v_row.id returning * into v_row;
    return jsonb_build_object('competition_id', v_c.id, 'participant_id', v_row.id, 'joined', 'rejoined');
  end if;

  insert into public.competition_participants (competition_id, profile_id)
  values (v_c.id, v_me.id) returning * into v_row;
  return jsonb_build_object('competition_id', v_c.id, 'participant_id', v_row.id, 'joined', 'new');
end;
$$;
revoke all on function public.claim_competition_invite(text) from public, anon;
grant execute on function public.claim_competition_invite(text) to authenticated;

commit;


-- ===========================================================================
-- KONTROLL (kjør i SQL Editor etter fila, som én kjøring). Én rad per sjekk,
-- alle skal ha ok = true. Sjekker skjemaet; selve oppførselen (hvem som
-- avvises) prøves i sql/lokal/025_prove.sql, som er KUN for lokal Postgres.
-- ===========================================================================
-- with f as (
--   select p.proname, p.prosrc, p.provolatile, p.prosecdef,
--          pg_get_function_identity_arguments(p.oid) as args,
--          has_function_privilege('anon', p.oid, 'execute') as anon_kan,
--          has_function_privilege('authenticated', p.oid, 'execute') as auth_kan,
--          (select count(*) from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
--            where a.grantee = 0) as public_kan
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public'
--     and p.proname in ('competition_invite_preview', 'claim_competition_invite')
-- )
-- select 1 as nr, 'Begge funksjonene finnes, bare med (p_code text)' as sjekk,
--        (select count(*) = 2 and bool_and(args = 'p_code text') from f) as ok
-- union all
-- select 2, 'anon og PUBLIC kan ikke kjøre dem, authenticated kan',
--        (select bool_and(not anon_kan and public_kan = 0 and auth_kan) from f)
-- union all
-- select 3, 'Fortsatt security definer med tom search_path',
--        (select bool_and(f.prosecdef) from f)
--        and (select bool_and(exists (select 1 from pg_proc p where p.proname = f.proname
--                                       and 'search_path=""' = any(p.proconfig))) from f)
-- union all
-- select 4, 'Forhåndsvisningen er fortsatt stable, «Bli med» ikke',
--        (select provolatile = 's' from f where proname = 'competition_invite_preview')
--        and (select provolatile = 'v' from f where proname = 'claim_competition_invite')
-- union all
-- select 5, 'Forhåndsvisningen sjekker blokkering mot eieren (blocked_between)',
--        (select prosrc like '%blocked_between(v_c.owner_id)%' from f where proname = 'competition_invite_preview')
-- union all
-- select 6, '«Bli med» avviser blokkerte med DDB01',
--        (select prosrc like '%blocked_between(v_c.owner_id)%' and prosrc like '%DDB01%'
--         from f where proname = 'claim_competition_invite')
-- union all
-- select 7, 'blocked_between (019) finnes og kan kjøres av authenticated, ikke anon',
--        exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--                where n.nspname = 'public' and p.proname = 'blocked_between'
--                  and has_function_privilege('authenticated', p.oid, 'execute')
--                  and not has_function_privilege('anon', p.oid, 'execute'))
-- order by nr;
--
-- Data endres ikke av 025: den som alt er påmeldt, står (blokkeringen tar
-- ingen ut). Oppførselen prøves i sql/lokal/025_prove.sql (KUN lokalt).


-- ===========================================================================
-- RULLEBAKKE (bare test). Setter funksjonene tilbake til 022: kjør avsnittene
-- «competition_invite_preview» og «claim_competition_invite» fra
-- 022_konkurranser.sql på nytt (create or replace, samme signatur). Ingen
-- tabeller eller data endres av 025.
-- ===========================================================================
