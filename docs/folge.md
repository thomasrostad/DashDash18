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
