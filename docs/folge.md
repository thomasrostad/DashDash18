# Følge andre spillere (steg 13)

12.10.2026, Thomas: «Vi må kanskje ha mine venner osv, kanskje man kan finne noe inspirasjon fra Strava eller andre treningsapper om hvordan man blir venner.»

## Slik gjør andre det (lest 12.10.2026)

- **Strava:** følgere. Med profilen på «Followers» må hver følger godkjennes. Navnesøk, forslag, kontakter og QR. Ikke-følgere ser bilde, bio og antall følgere ([personvern](https://support.strava.com/en-us/articles/15401776-strava-s-privacy-controls-faq), [finne venner](https://support.strava.com/en-us/articles/15401934-finding-friends-and-managing-contacts-on-strava)). Flyby som deler med alle som standard er et eksempel på hva vi ikke skal gjøre ([deceptive.design](https://www.deceptive.design/articles/strava-flyby-privacy-settings)).
- **Garmin Connect:** gikk i april 2026 fra gjensidige forbindelser til følgere, med godkjenning når profilen står på «My Followers» ([GarminNews](https://www.garminnews.com/garmin-connect-update-replacing-connections-with-followers-and-adding-advanced-training-and-privacy-logic/)). Brukere klaget på forespørsler fra fremmede via navnesøk ([forum](https://forums.garmin.com/apps-software/mobile-apps-web/f/garmin-connect-web/255611/rogue-connection-request)).
- **Komoot:** offentlig eller privat profil, og et eget valg for å skjule seg fra søk ([Komoot](https://www.komoot.com/help/privacy)).
- **TheGrint:** gikk til følging i januar 2026; følgere kan ikke laste opp score for deg ([TheGrint](https://thegrint.com/range/post/are-you-following-the-new-way-to-connect-on-thegrint)).
- **18Birdies:** navnesøk, invitasjonslenke, kontakter og QR ([18Birdies](https://help.18birdies.com/article/70-adding-and-managing-friends)).
- **Apple 1.2:** filter, rapportering, blokkering og kontaktinformasjon ([Apple](https://developer.apple.com/app-store/review/guidelines/#user-generated-content)).

## Beslutninger (Thomas, 12.10.2026)

| Tema | Beslutning |
|---|---|
| Modell | Følge, som Strava. Den du følger trenger ikke følge tilbake |
| Godkjenning | Ja som standard: nye følgere må godkjennes. Kan slås av for åpen profil |
| Finne folk | Navnesøk, QR-kode. Etter en runde: «Følg X» på resultatkortet |
| Søk | Synlig i søket som standard, kan skjules under Deg |
| QR | Skanning gir følging med en gang (å vise koden er godkjenningen) |
| Hva følging gir | Profil og runder dere har spilt sammen; den du følger sine ferdige runder i en egen «Følger»-fane i feeden, også utenfor felles klubb; like, skryte (reaksjoner og kommentarer) på dem; invitere til turneringer og runder, og de står øverst i «Ny runde» |

## Personvern og vern

- Blokkering (finnes) fjerner følging begge veier og ventende forespørsler, og skjuler i søk.
- «Rapporter profil» går til `content_reports`.
- Søk krever minst tre tegn, viser navn, bilde og klubb (ikke e-post), og er begrenset per time.
- Høyst 50 forespørsler per døgn per bruker.
- Bare ferdige (låste) runder vises i «Følger», ikke pågående, og bare fra dem som har godtatt deg. Skjulte hull (047) gjelder til runden er låst.
- `docs/personvern.md` må endres: i dag står det at andre ikke kan søke deg opp.

## Datamodell (skisse, SQL 054)

- `follows(follower_id, followee_id, status 'pending'|'accepted', source 'search'|'qr'|'round'|'link', created_at, accepted_at)`, primærnøkkel (follower, followee).
- `profiles.follow_approval boolean default true`, `profiles.searchable boolean default true`, `profiles.follow_code` (rotérbar).
- RPC-er: `follow_request`, `follow_respond`, `follow_remove`, `follow_by_code`, `search_people`, `followers_list`, `following_feed_page`.
- `can_see_profile` og `known_profiles` får en vei for godtatt følging.
- `delete_account_data` og `block_user` rydder.

## Slik ble det i SQL 054 (avvik fra skissen)

- Koden ligger i `follow_codes`, ikke `profiles.follow_code`: profilraden leses av alle som ser profilen, og koden gir følging uten godkjenning.
- `followers_list` heter `my_follows()` og gir følger, følgere og forespørsler i ett kall.
- Kilden kan også være `suggestion`.
- «Følger»-kortene er en hendelse `round_finished` per spiller (personlig linje i `activity`, `actor_profile_id`), så reaksjoner og kommentarer fra 050 virker uendret (`target_kind = 'activity'`).
- Følging gir profilen begge veier (den du følger, og dine følgere), også i «Ny runde»-velgeren. En forespørsel gir ikke profilen, men du kan blokkere og rapportere den som spør.

## Appen etter 054

Uten 054 skal alt dette være skjult (sjekk at RPC-en finnes, som før).

- **Deg → Personvern:** «Godkjenn nye følgere» (`follow_approval`) og «Synlig i søk» (`searchable`), lagret med `follow_settings(godkjenning, søkbar)` (null = uendret) eller vanlig update av egen profil.
- **Deg → Følger og følgere:** `my_follows()` (`direction` following/follower, `status` pending/accepted). Forespørsler øverst med «Godta» / «Avslå» (`follow_respond`), «Slutt å følge» (`follow_remove`), «Fjern følger» (`follower_remove`), «Blokker» og «Rapporter» (`block_user`, `report_content('profile', …)`). Lytte på `follows` (Realtime) for merket.
- **Søk:** felt med minst tre tegn og venting (debounce) før kall, `search_people(tekst)`; vise navn, bilde, `club_name`, og knappen etter `my_status` (none: «Følg», pending: «Venter», accepted: «Følger») og `follows_me` («Følger deg»). Feilkode 54000 = «Prøv igjen om litt».
- **Følg:** `follow_request(profil, kilde)` med `search`, `round` («Følg X» på resultatkortet etter runden), `link` eller `suggestion`. Svaret er `pending` eller `accepted`. 54000 = grensen på 50 i døgnet. P0002 = «Fant ikke personen».
- **QR:** «Min kode» viser `follow_code()` som QR (for eksempel `dashdash://folg/<kode>` og `https://dashdash18.com/folg/<kode>`), «Ny kode» = `follow_code(true)`. Skanning: `follow_by_code(kode, 'qr')` (lenke: `'link'`); svaret `{status: not_found}` = «Fant ikke koden», ellers profilen og `already`. 54000 = for mange forsøk.
- **Feed → «Følger»-fane:** `following_feed_page(før tid, før id, antall)` (bla med siste `created_at` og `id`). Kortet: navn, bilde, dato (`played_on`), bane, slag, `to_par`, hull spilt, og `holes` (hull, par, indeks, slag) for detaljer; `is_mine` for egne runder. Reagere med `react('activity', id, emoji)`, kommentere med `comment_add('activity', id, …)`, lese `comments` som i 050. Eieren av kortet kan slette kommentarer (`comment_delete`). Følgeren kan ikke åpne selve runden.
- **Varsler (bjella og Varsler):** les også personlige linjer (`club_id` og `competition_id` tomme, `actor_profile_id`, `recipients` med profil-id-er): tekst for `follow_requested` («X vil følge deg», med Godta/Avslå), `follow_accepted` («X godtok forespørselen din»), `followed` («X følger deg nå»), og `comment_added`/`mentioned` på et kort («X kommenterte runden din»). `round_finished` vises bare i «Følger», ikke i Varsler. Spørringene som i dag filtrerer på klubb eller turnering, må ta med disse.
- **Profil:** knappen Følg/Venter/Følger, og «Runder dere har spilt sammen» fra rundene du alt kan lese.
- **«Ny runde» og turneringer:** `known_profiles()` gir også dem du følger og dine følgere; sortere dem du følger øverst.
- **push-send:** `audience = 'person'` (id-ene i `members` er profil-id-er, blokkering fra `user_blocks` mot `activity.actor_profile_id`, threadId for eksempel `follow`), tekst for de tre nye kindene og kommentarer på kort uten klubb. Gruppene for brukere uten klubb kan ikke slås av ennå (`push_set_groups` skriver per medlemskap), som for turneringer uten klubb.
- **Personvern:** publisere teksten merket «Etter 054» i `docs/personvern.md` når 054 er kjørt.
