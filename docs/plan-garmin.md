# Garmin: plan

28.10.2026. Grunnlag: Thomas, 28.10.2026: «mange» i gjengen bruker Garmin. Bygger på klokkeappen for Apple Watch ([`plan-apple-watch.md`](plan-apple-watch.md), #235) og formatet `WatchRound` (`DashDash18/Watch/WatchRound.swift`).

**Status 29.10.2026:** steg 1 (prøven) er bygget, venter på test på ekte klokke. Garmin-appen ligger i [`garmin/`](../garmin/README.md) og bygger for 27 modeller (Fenix 6/7/8, Forerunner 945–970, Epix 2). Atten har Connect IQ Mobile SDK 1.8.0 (godkjent av Thomas 28.10.2026), `GarminLink` og «Garmin-klokke» under Deg, bare i test-bygg til appen er i Connect IQ Store. Bakgrunn: med bakgrunnsmodusen for Bluetooth kan iOS vekke Atten når klokka sender (Garmins SDK-dokumentasjon). Garmin-simulatoren viser bare hvitt på macOS 27.2 (også GolfFace), så designet er vist som skisser.

## Mål

Spillere og markører med Garmin-klokke skal kunne føre slag fra klokka og se «Bayen nå», med de samme tallene og tekstene som telefonen viser. Som på Apple Watch er det telefonen som regner og lagrer.

## Hvordan det skiller seg fra Apple Watch

| | Apple Watch (#235) | Garmin |
|---|---|---|
| Språk og butikk | Swift, følger med Atten i App Store | Monkey C (Connect IQ), egen app i Connect IQ Store |
| Forbindelse | WatchConnectivity, direkte | Bluetooth via Garmin Connect-appen og Garmins SDK for iPhone (Connect IQ Mobile SDK) inne i Atten |
| Fart | Rask | Treg, særlig mot iPhone (sekunder per melding ifølge Garmins forum) |
| Minne på klokka | Rikelig | Lite og ulikt per modell (eldre modeller noen titalls kB for en app) |
| Modeller | Én familie | Mange: Fenix, Forerunner, Venu, Approach, Epix, Instinct med ulike skjermer og knapper |

**Konsekvens:** telefonen sender bare hullet som vises (rader, tekst for hvert slagantall) og «Bayen nå», ikke hele runden. Klokka spør etter neste hull når du går videre.

## Arkitektur

- **Én mekanisme på telefonen:** Garmin får en utgave av den samme `WatchRound` som Apple Watch får (`RoundGame.watchRound(for:)`), kuttet ned til gjeldende hull. Ingen ny utregning, så Garmin kan ikke regne annerledes enn telefonen eller Apple Watch.
- **Samme vei inn:** et hull fra Garmin blir en `HoleSubmission` og går i utboksen, som hull fra Apple Watch og hullkortet.
- **`GarminRoundController`** på telefonen, ved siden av `WatchRoundController`: kalles fra samme sted i `RundeModel`, sender bare når en Garmin med appen er koblet til.
- **Garmin-appen** (Monkey C, egen mappe `garmin/` i repoet): skjermene «Hullet» og «Bayen nå», en liten kø for hull som ikke er bekreftet (`Application.Storage`), og knappestyring (opp/ned endrer slag, start lagrer) med berøring der klokka har det.

## Steg

### Steg 1 – Prøve på ekte klokke (1–2 økter)
- Minimal Garmin-app og Connect IQ Mobile SDK i en testutgave av Atten.
- Sende ett hull fra telefonen til klokka og ett tilbake, på Thomas sin Garmin.
- Måle: tid per melding, om Atten tar imot når den ligger i bakgrunnen, og hvor stor melding klokka tåler.
- **Ferdig når:** et hull ført på Garmin står i Supabase test. Er det for tregt eller upålitelig i bakgrunnen, sier jeg fra med tallene før noe mer bygges.

### Steg 2 – Telefonen (2–3 økter)
- Connect IQ Mobile SDK i Atten (ny avhengighet, krever godkjenning). Valg av klokke går via Garmin Connect-appen.
- `GarminRoundController`: gjeldende hull og «Bayen nå» fra `WatchRound`, hull inn i utboksen.
- Tester for nedkuttingen og innsendingen, som `WatchRoundTests`.

### Steg 3 – Garmin-appen (3–4 økter)
- «Hullet»: navn, slag mottatt, tallet og teksten («2 p · netto par»), valgt rad markert.
- Knapper: opp/ned endrer slag, start lagrer og går videre, tilbake bytter rad. Berøring der klokka har det.
- «Bayen nå» som egen side.
- Kø for hull som ikke er bekreftet, og «venter på telefonen».
- Tester i Connect IQ-simulatoren for modellene gjengen bruker.

### Steg 4 – Ut (1–2 økter)
- Connect IQ Store: beskrivelse, skjermbilder, ikon og personvern. Garmin går gjennom appen før den blir synlig. Beta kan sideloades til gjengen før det.
- Ny versjon av Atten med SDK-en i App Store.
- Én kveld med gjengen før appen blir offentlig.

**Totalt: 7–11 økter**, pluss Garmins gjennomgang.

## Det du må avgjøre eller gjøre

1. **Hvilke Garmin-modeller gjengen har.** Det avgjør hvilke klokker appen bygges og testes for.
2. **Godkjenne Connect IQ Mobile SDK** som ny avhengighet i Atten (CLAUDE.md: nye avhengigheter krever godkjenning).
3. **Garmin-utviklerkonto** (Garmin-konto registrert som Connect IQ-utvikler) til butikken.
4. **Teste på din egen Garmin** i steg 1. Simulatoren viser ikke farten over Bluetooth.

## Risiko

- **Treg forbindelse mot iPhone.** Garmins eget forum sier meldinger kan ta flere sekunder. Føringen må tåle det: klokka viser tallet med en gang og sender i bakgrunnen.
- **Atten i bakgrunnen på iPhone.** Det er usikkert om Atten tar imot meldinger fra Garmin når appen ikke er åpen. Testes i steg 1. Er svaret nei, må Atten være åpen under runden (som i dag når du fører på telefonen), og klokka sier fra når den ikke får svar.
- **Mange modeller.** Appen må tilpasses skjermformer (runde og firkantede) og knapper. Vi begynner med modellene gjengen har.
- **Garmins egen golf.** Approach-klokkene har eget scorekort. Connect IQ-apper kan ikke lese det, så Atten kan ikke hente slag derfra.

## Rekkefølge

1. Apple Watch testes i TestFlight (bygg 236).
2. Garmin steg 1 (prøven) på din klokke.
3. Garmin steg 2–4.
4. Android når det kommer Android-brukere ([`plan-android.md`](plan-android.md)).

Kilder: [Connect IQ: publisere en app](https://developer.garmin.com/connect-iq/submit-an-app/), Garmins utviklerforum om [størrelse og fart på meldinger](https://forums.garmin.com/developer/connect-iq/f/discussion/2524/ble-data-transmission), [minne per modell](https://forums.garmin.com/developer/connect-iq/f/discussion/418612/device-memory-limits) og [feil i iOS-SDK-en](https://forums.garmin.com/developer/connect-iq/i/bug-reports/bug-ios-companion-sdk).
