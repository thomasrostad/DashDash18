# Backup av Atten Prod

Atten Prod (`wxabhadvuzyrmndxpuza`) står på Supabase sin gratisplan, som ikke har backup. Til vi går over til Pro, tar GitHub Actions en backup hver natt (`.github/workflows/backup-prod.yml`, besluttet 20.10.2026).

## Hva som tas med

- `supabase db dump` i tre deler, slik Supabase anbefaler: `roles.sql` (roller), `schema.sql` (skjema, funksjoner, policyer, triggere) og `data.sql` (alle data, med `COPY`), pluss `SHA256SUMS`.
- Filene pakkes, krypteres med AES-256 (`gpg --symmetric`) og lastes opp til den private R2-bøtta `atten-backup` i Cloudflare, under `daglig/atten-prod-<tid>.tar.gz.gpg`.
- Bøtta sletter filer eldre enn 7 dager selv. Det er det personvernerklæringen lover («Sikkerhetskopier … slettes automatisk etter høyst 7 dager»).

**Ikke med:** filene i Storage (portretter og bilder i tråden, bøttene `avatars` og `thread`), Vault-hemmelighetene, Edge Function-secrets og Auth-innstillingene. Vault og secrets kan lages på nytt (`sql/062`, `sql/063` og skriptene i økten 20.10), Auth-innstillingene står i `docs/prod-sjekkliste.md` avsnitt 2.

## Oppsett (én gang, Thomas)

1. **R2:** Cloudflare → R2 → slå på R2. Claude lager bøtta `atten-backup` med regelen «slett etter 7 dager».
2. **R2-token:** R2 → Manage API tokens → Create API token → *Object Read & Write*, bare bøtta `atten-backup`. Noter Access Key ID og Secret Access Key.
3. **Passord for krypteringen:** lag et langt, tilfeldig passord og legg det i passordhvelvet som «Atten backup». Uten det kan backupene ikke åpnes.
4. **GitHub-secrets:** i Terminal (ikke i Claude), i repoet:
   ```
   gh secret set PROD_DB_URL          # lim inn Session pooler-strengen fra Supabase (Connect), med passordet
   gh secret set BACKUP_PASSPHRASE    # lim inn passordet fra punkt 3
   gh secret set R2_ACCESS_KEY_ID
   gh secret set R2_SECRET_ACCESS_KEY
   ```
   `gh secret set` spør etter verdien uten å vise den.
5. Kjør workflowen for hånd én gang: Actions → «Backup av Atten Prod» → Run workflow. Den skal bli grønn og vise tre filstørrelser.

## Gjenoppretting

Til et nytt, tomt Supabase-prosjekt (eller en lokal Postgres med Supabase-skjemaene):

```sh
# 1. Hent og pakk ut (passordet fra passordhvelvet)
aws s3 cp s3://atten-backup/daglig/<fil>.tar.gz.gpg . --endpoint-url https://749a71cc47cf4aee087ba73caeb8d2ef.r2.cloudflarestorage.com
gpg -d <fil>.tar.gz.gpg | tar -xzf -
shasum -a 256 -c SHA256SUMS

# 2. Kjør inn i målbasen (tilkoblingsstrengen til det nye prosjektet)
psql "$MAAL_DB_URL" -v ON_ERROR_STOP=1 -f roles.sql
psql "$MAAL_DB_URL" -v ON_ERROR_STOP=1 -f schema.sql
psql "$MAAL_DB_URL" -v ON_ERROR_STOP=1 -c 'set session_replication_role = replica' -f data.sql
```

Etterpå: Vault-hemmelighetene og Edge Function-secrets for det nye prosjektet, deploy av funksjonene, Auth-innstillingene og `project_url` (se `docs/prod-sjekkliste.md`). Skal det gamle prosjektet erstattes, må appen, workeren og web-admin peke på det nye.

Gjenopprett aldri rett inn i Atten Prod uten å ha tatt en ny backup først.

## Sjekk

- Én gang i måneden: last ned siste fil, pakk den ut og sjekk `SHA256SUMS`. Workflowen feiler (og GitHub sender e-post) hvis en dump er tom eller en secret mangler.
- Når vi går over til Pro, får prosjektet daglig backup i Supabase. Da kan denne workflowen slås av, eller beholdes som en ekstra kopi utenfor Supabase.
