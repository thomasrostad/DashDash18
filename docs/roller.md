# Egne roller per klubb (steg 2, sql/044)

Beslutning 11.10.2026 (Thomas): klubben lager egne roller med rettigheter. Malene er Eier, Arrangør, Kasserer, Sosialkomité og Medlem.

## Rettighetene (fire grupper)

| Nøkkel | Navn i appen | Gir |
|---|---|---|
| `tournaments` | Turneringer og regler | Lage og endre turneringer og serier, regler, terminliste og spilledager, påmelding og venteliste, stab, sosialkomité |
| `rounds` | Runder og føring | Sette opp, starte, låse, avkorte og slette runder, rette score, baner og par |
| `members` | Medlemmer og invitasjon | Godkjenne og avvise, invitere, navn, handicap og seeding, arkivere, gi roller (bare roller med rettigheter du selv har) |
| `money` | Penger og moderering | Del regningen, avgjøre og gjøre opp veddemål, tippekupong, rapporter og fjerning av innhold |

**Eier** har alle rettighetene og i tillegg: lage, endre og slette roller, overføre eierskap og slette klubben. En klubb har alltid minst én eier. Siste eier kan ikke gå eller miste rollen uten å gi den til en annen.

## Malene (lages for hver klubb)

| Rolle | Rettigheter | Merknad |
|---|---|---|
| Eier | alle + eier | Gis til eldste arrangør i klubber som finnes |
| Arrangør | alle fire | Gis til alle som er arrangør i dag |
| Kasserer | `money` | Gis til alle som er kasserer i dag |
| Sosialkomité | ingen | Et merke. Hvem som er sosialkomité en bestemt kveld, settes fortsatt per kveld |
| Medlem | ingen | Alle medlemmer, ingen rad trengs |

Klubben kan endre navn og rettigheter på malene (ikke på Eier), lage nye roller og slette roller ingen har. Et medlem kan ha flere roller, og rettighetene legges sammen.

## Datamodell

- `club_roles` (`id`, `club_id`, `name`, `rights text[]`, `is_owner`, `template_key`, `sort_order`), unikt navn per klubb.
- `club_member_roles` (`club_id`, `member_id`, `role_id`), primærnøkkel (medlem, rolle).
- `private.has_club_right(club, right)` og `private.is_club_owner(club)`, `security definer`, `search_path = ''`, mengdebasert.
- Ingen skrivepolicyer: alt går gjennom RPC-er (`club_role_save`, `club_role_delete`, `club_member_set_roles`, `club_transfer_ownership`).
- Gamle bygg: `club_members.is_organizer` og `is_treasurer` speiles fra rollene (arrangør = har `tournaments`, kasserer = har Kasserer-rollen), og en endring av flaggene fra et gammelt bygg gir eller tar Arrangør- eller Kasserer-rollen.
- `is_club_organizer(club)` betyr «har minst én av rettighetene». Hver funksjon og policy som i dag spør om arrangør, spør etter riktig rettighet. Med dagens data gir det samme svar for alle (paritetsprøve).
- `clubs.org_number` (9 siffer, valgfri) for navn fra Enhetsregisteret.
