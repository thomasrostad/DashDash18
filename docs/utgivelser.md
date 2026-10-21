# Utgivelser

Regler for når og hvordan nye versjoner av Atten kommer ut. Vedtatt 21.10.2026.

**Grunnregel:** vi kan ikke vite når klubbene spiller, så vi prøver ikke å time utgivelsene rundt dem. I stedet skal hver oppdatering være trygg å få når som helst, også midt i en runde. Nyheter slås på fra serveren for seg, ikke i samme øyeblikk som appen oppdateres. Slik jobber de store appene.

## 1. Fast rytme

- Ny versjon **annenhver uke**, bare hvis noe er klart. Er ingenting klart, går det ingen versjon.
- Med i versjonen blir det som er merget til `main` og har ligget i TestFlight (gruppen Gjengen) i minst to dager uten nye krasj.
- **Mandag:** prod-bygg med workflowen «App Store (prod)» og innsending.
- **Utgivelse:** manuell, tirsdag–torsdag, aldri fredag–søndag. Da er det folk tilgjengelige hvis noe går galt.
- **Phased release er alltid på.** Apple sprer da versjonen over 7 dager (1 %, 2 %, 5 %, 10 %, 20 %, 50 %, 100 %) til dem som har automatisk oppdatering. Den kan settes på pause hvis feilrapportene øker. Den som oppdaterer selv i App Store, får versjonen med en gang.

## 2. Hasteretting

Utenom rytmen, når som helst, bare når noe av dette skjer:

- data går tapt eller blir feil (scorer, resultater, oppgjør)
- man kan ikke føre score eller logge inn
- appen krasjer for mange

Send inn med en gang og be om expedited review (developer.apple.com/contact/app-store/?topic=expedite). Phased release kan settes til 100 % straks. Det som bare kan rettes på serveren (SQL, Edge Function, worker), rettes der og trenger ingen ny versjon.

## 3. Nyheter bak brytere

- **Nødbrytere (fra 1.0.2):** utvalgte funksjoner kan slås av fra serveren uten nytt bygg, med `app_config.ios_flags` (`sql/068`): Del tavla, TV-kode, Finn turneringer, Del regningen, Sosialt og Live Activity.
- **Bare av, aldri på.** Apple forbyr funksjoner som skrus på etter gjennomgangen (App Review 2.3.1). En ny funksjon er derfor på i bygget som sendes inn, og serveren må være klar før versjonen slippes (punkt 4).
- Kjernen (føring, Tavla, spillformer, påmelding) har ingen nødbryter. Å slå av noe der midt i en runde er verre enn feilen. Der gjelder hasteretting (punkt 2).
- Andre brytere i koden (`…Feature.isEnabled`) krever nytt bygg. En ny nødbryter legges til med én linje i funksjonens `…Feature` og navnet i `sql/068`.

## 4. Server og database

Gamle versjoner av appen er i bruk i uker etter en ny versjon. Serveren må tåle dem alle.

- **Serveren først, appen etterpå.** Migreringen kjøres på prod før en appversjon som trenger den slippes.
- **Bare legg til.** Nye kolonner har standardverdi, og nye funksjoner kommer ved siden av de gamle. Ikke fjern, døp om eller endre svaret fra noe som en støttet versjon bruker. Trengs ny oppførsel, lag en ny funksjon (`…_v2`).
- **Rydd senere.** Det gamle fjernes først når minimumsversjonen (punkt 6) er hevet forbi den siste versjonen som brukte det.
- Står i `sql/README.md` per migrering: hvilken appversjon som trenger den.

## 5. Oppdatering midt i en runde

iOS oppdaterer ikke en app som er åpen på skjermen, men kan gjøre det mens den ligger i bakgrunnen. Utboksen (`DashDash18/Outbox/`) lagrer hvert hull på telefonen før det sendes, så ingenting går tapt, **så lenge den nye versjonen kan lese det som ligger der**.

- Endringer i lokale modeller (SwiftData, for eksempel `OutboxItem`) skal ha migrering, aldri bare nytt skjema.
- Prøv før utgivelse: før noen hull i flymodus med forrige versjon, oppdater til ny versjon fra TestFlight, og se at hullene sendes.

## 6. Støttevindu og tvungen oppdatering

- Alle versjoner fra de siste **90 dagene** er støttet.
- **Myk beskjed (fra 1.0.2):** bygg under `app_config.recommended_ios_build` (`sql/068`) får «Ny versjon av Atten» én gang, med «Oppdater» og «Senere». Settes når en ny versjon har nådd 100 % i phased release.
- **Tvungen oppdatering (fra 1.0):** bygg under `app_config.min_ios_build` (`sql/031`) får «Oppdater Atten» etter innlogging og kommer ikke videre. Brukes bare når en gammel versjon lager feil data eller serveren ikke lenger kan støtte den. Virker også for 1.0 og 1.0.1.
- Begge tar byggnummeret (`CFBundleVersion` fra Xcode Cloud), ikke versjonen. Kommandoene står øverst i `sql/068`.

## 7. iOS-versjon

- Atten støtter **de to siste store iOS-versjonene**. Minimum er nå iOS 26.0 (iOS 27 kom 14.09.2026). Det gir iPhone 11 og nyere.
- Vurderes hver høst når ny iOS kommer. Heves bare når det gir noe vi trenger.
- Heves minimum, får de med eldre iOS fortsatt laste ned siste versjon som virket for dem (App Store tilbyr «siste kompatible versjon»). Den versjonen må serveren fortsatt tåle (punkt 4).
- Apple krever hvert år, fra april, at nye bygg lages med nyeste Xcode. Det gjelder oss, ikke brukerne. Se `docs/xcode-cloud.md`.

## Sjekkliste per versjon

1. Migreringer som versjonen trenger, er kjørt på prod (`sql/README.md`).
2. Bygget har ligget i TestFlight i minst to dager uten nye krasj (`feilrapporter`).
3. Er en lokal modell endret: oppdatering midt i runden prøvd (punkt 5).
4. Marketing Version økt. Prod-bygg fra «App Store (prod)» lagt på versjonen.
5. What's New skrevet. Manuell utgivelse og phased release på.
6. Etter utgivelse: følg `feilrapporter` per `app_version` den første uka.

## Status 21.10.2026

- **Har:** TestFlight-gruppen Gjengen, prod-workflow i Xcode Cloud, utboks på telefonen, feilrapporter med appversjon, expedited review prøvd (1.0.1), tvungen oppdatering (1.0). Myk beskjed og nødbrytere kommer med 1.0.2.
- **Mangler:** oversikt over hvilke appversjoner som er i bruk (versjonen lagres i dag bare ved feil). 1.0.1 er satt til automatisk utgivelse; fra neste versjon gjelder punkt 1.
