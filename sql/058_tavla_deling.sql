-- 058: Tavla i nettleseren for tilskuere («Del tavla»). IKKE KJØRT. Krever godkjenning.
--
-- (Nummeret: 056 og 057 er holdt av til regelinnstillingene og de nye spillformene, som lages samtidig.)
--
-- Arrangøren slår på deling av Tavla i appen. Da får turneringen en lenke, dashdash18.com/tavla/KODE,
-- som kan legges i WhatsApp-gruppa. Siden viser tabellen, «Alle runder» og scorekortene, oppdatert
-- live, uten app og uten konto. Arrangøren kan slå delingen av (koden trekkes tilbake, lenken slutter
-- å virke) og lage en ny lenke.
--
-- Lesingen går gjennom tv_board_data(kode) (041/043/047/048), som TV-siden: samme rådata, uten
-- innlogging, e-post, bilder, påmeldinger, tråd eller noe annet i klubben. Skjulte hull i en runde som
-- går (047), sendes ikke. Ingen nye lesetilganger og ingen endring i RLS.
--
-- Koden er en egen rad i tv_codes med purpose = 'tavla', så delingen kan slås av uten at TV-skjermen i
-- klubbhuset slutter å virke, og omvendt. tv_code og tv_code_revoke røres derfor bare av 'tv'-koder.
--
-- Nytt:
--   tv_codes.purpose                          'tv' (som før) eller 'tavla'
--   tavla_share_code(turnering, forny)       arrangøren: slår på (eller lager ny lenke), gir koden
--   tavla_share_revoke(turnering)            arrangøren: slår av
--   tavla_share_current(turnering)           den som kan lese turneringen: koden når delingen er på, ellers null
-- Endret (samme signatur og svar for TV-koden):
--   tv_code, tv_code_revoke                  bare purpose = 'tv'
--
-- Én transaksjon, idempotent. Kontroll og rullebakke nederst.

begin;

alter table public.tv_codes add column if not exists purpose text not null default 'tv';
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'tv_codes_purpose_check') then
    alter table public.tv_codes add constraint tv_codes_purpose_check check (purpose in ('tv', 'tavla'));
  end if;
end;
$$;
create index if not exists tv_codes_competition_purpose_idx on public.tv_codes (competition_id, purpose);
comment on column public.tv_codes.purpose is
  'tv: TV-skjermen (041). tavla: delt lenke til Tavla i nettleseren (058). Begge leses med tv_board_data.';

-- Felles: lager en ny kode for formålet. Bare for funksjonene under (ingen grant).
create or replace function public.tv_code_new(p_competition_id uuid, p_purpose text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
  loop
    select string_agg(substr(v_alphabet, 1 + floor(random() * 32)::int, 1), '') into v_code
      from generate_series(1, 10);
    begin
      insert into public.tv_codes (code, competition_id, created_by, purpose)
      values (v_code, p_competition_id, auth.uid(), p_purpose);
      return v_code;
    exception when unique_violation then
      -- Svært usannsynlig: prøv en ny.
    end;
  end loop;
end;
$$;
revoke all on function public.tv_code_new(uuid, text) from public, anon, authenticated;

-- TV-koden (041), nå bare blant 'tv'-kodene.
create or replace function public.tv_code(p_competition_id uuid, p_renew boolean default false)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if not public.is_competition_admin(p_competition_id) then
    raise exception 'Bare arrangøren kan lage TV-kode' using errcode = '42501';
  end if;
  if p_renew then
    update public.tv_codes set revoked_at = now()
     where competition_id = p_competition_id and purpose = 'tv' and revoked_at is null;
  else
    select t.code into v_code from public.tv_codes t
     where t.competition_id = p_competition_id and t.purpose = 'tv'
       and t.revoked_at is null and t.expires_at > now()
     order by t.created_at desc limit 1;
    if v_code is not null then return v_code; end if;
  end if;
  return public.tv_code_new(p_competition_id, 'tv');
end;
$$;
revoke all on function public.tv_code(uuid, boolean) from public, anon;
grant execute on function public.tv_code(uuid, boolean) to authenticated;

create or replace function public.tv_code_revoke(p_competition_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_competition_admin(p_competition_id) then
    raise exception 'Bare arrangøren kan trekke tilbake TV-koden' using errcode = '42501';
  end if;
  update public.tv_codes set revoked_at = now()
   where competition_id = p_competition_id and purpose = 'tv' and revoked_at is null;
end;
$$;
revoke all on function public.tv_code_revoke(uuid) from public, anon;
grant execute on function public.tv_code_revoke(uuid) to authenticated;

-- «Del tavla» på: koden som gjelder, eller en ny (p_renew trekker den gamle tilbake: «Ny lenke»).
create or replace function public.tavla_share_code(p_competition_id uuid, p_renew boolean default false)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if not public.is_competition_admin(p_competition_id) then
    raise exception 'Bare arrangøren kan dele Tavla' using errcode = '42501';
  end if;
  if p_renew then
    update public.tv_codes set revoked_at = now()
     where competition_id = p_competition_id and purpose = 'tavla' and revoked_at is null;
  else
    select t.code into v_code from public.tv_codes t
     where t.competition_id = p_competition_id and t.purpose = 'tavla'
       and t.revoked_at is null and t.expires_at > now()
     order by t.created_at desc limit 1;
    if v_code is not null then return v_code; end if;
  end if;
  return public.tv_code_new(p_competition_id, 'tavla');
end;
$$;
revoke all on function public.tavla_share_code(uuid, boolean) from public, anon;
grant execute on function public.tavla_share_code(uuid, boolean) to authenticated;

-- «Del tavla» av: lenken slutter å virke med en gang (siden sier «Lenken virker ikke lenger»).
create or replace function public.tavla_share_revoke(p_competition_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_competition_admin(p_competition_id) then
    raise exception 'Bare arrangøren kan slå av delingen' using errcode = '42501';
  end if;
  update public.tv_codes set revoked_at = now()
   where competition_id = p_competition_id and purpose = 'tavla' and revoked_at is null;
end;
$$;
revoke all on function public.tavla_share_revoke(uuid) from public, anon;
grant execute on function public.tavla_share_revoke(uuid) to authenticated;

-- Er delingen på? Koden for den som kan se turneringen (spillerne deler lenken videre fra Tavla),
-- null når delingen er av. Lager aldri en kode.
create or replace function public.tavla_share_current(p_competition_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select t.code from public.tv_codes t
   where t.competition_id = p_competition_id and t.purpose = 'tavla'
     and t.revoked_at is null and t.expires_at > now()
     and (public.is_competition_admin(p_competition_id) or public.can_read_competition(p_competition_id))
   order by t.created_at desc limit 1;
$$;
revoke all on function public.tavla_share_current(uuid) from public, anon;
grant execute on function public.tavla_share_current(uuid) to authenticated;

commit;

-- Kontroll (les):
-- select count(*) from pg_proc where proname in ('tavla_share_code', 'tavla_share_revoke', 'tavla_share_current', 'tv_code_new');  -- 4
-- select purpose, count(*) from public.tv_codes group by 1;                                       -- bare 'tv' før første deling
-- select has_function_privilege('anon', 'public.tavla_share_current(uuid)', 'execute');          -- false
-- select has_function_privilege('authenticated', 'public.tv_code_new(uuid,text)', 'execute');    -- false
-- Prøv i en transaksjon som arrangør (set local role authenticated; set local request.jwt.claims …):
--   tavla_share_code(t) gir en kode, tv_code(t) gir en annen; tavla_share_revoke(t) lar TV-koden stå;
--   tv_board_data(<delekoden>) gir P0002 etter revoke.
--
-- Rull tilbake:
-- begin;
-- update public.tv_codes set revoked_at = coalesce(revoked_at, now()) where purpose = 'tavla';
-- drop function if exists public.tavla_share_current(uuid);
-- drop function if exists public.tavla_share_revoke(uuid);
-- drop function if exists public.tavla_share_code(uuid, boolean);
-- (tv_code og tv_code_revoke fra 041 legges inn igjen, så dropp tv_code_new og kolonnen:)
-- drop function if exists public.tv_code_new(uuid, text);
-- alter table public.tv_codes drop column if exists purpose;
-- commit;
