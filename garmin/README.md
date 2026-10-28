# Atten for Garmin

Connect IQ-app (Monkey C) som fører hullet og viser «Bayen nå» for runden som går i Atten på telefonen. Plan og bakgrunn: [`docs/plan-garmin.md`](../docs/plan-garmin.md).

Telefonen regner alt. Atten sender ett hull om gangen (`DashDash18/Watch/GarminMessage.swift`), laget av den samme `WatchRound` som Apple Watch får. Klokka viser og sender slagene tilbake, og Atten legger dem i utboksen som hullkortet gjør.

## Knapper

| Knapp | Gjør |
|---|---|
| Opp / ned | Endrer slagene for spilleren som er valgt |
| Start | Neste spiller. På den siste: lagrer hullet og går til neste |
| Tilbake | Forrige spiller (på den første: lukker appen) |
| Meny (hold opp) | «Bayen nå», «Forrige hull», «Neste hull» |

## Modeller

Fenix 6, 7 og 8, Forerunner 945/955/965/970 og Epix 2 (27 produkter i `manifest.xml`). `minApiLevel` 3.3.0 er Forerunner 945, den eldste. Ikonet er 40 px, med egne størrelser for AMOLED-modellene i `resources-<modell>/`.

## Bygge

Trenger Connect IQ SDK (9.2.0), en JDK (`brew install openjdk@21`) og utviklernøkkelen (`~/Garmin klokkeskiver/developer_key`, eller `GARMIN_DEVELOPER_KEY`). Nøkkelen er ikke i repoet.

```bash
garmin/tools/build.sh           # alle modellene, streng typesjekk (-l 3) og advarsler
garmin/tools/build.sh quick     # én per skjermtype
garmin/tools/build.sh test      # testene i simulatoren (source/Tests.mc)
garmin/tools/build.sh package   # garmin/build/Atten.iq til Connect IQ Store
```

`demo.jungle` bygger en utgave med et prøvehull (`source-demo/Demo.mc`), så simulatoren viser designet uten telefon. Den skal aldri til butikken.

## Prøve på egen klokke

1. `garmin/tools/build.sh` og finn `garmin/build/Atten-<modell>.prg` for klokka din.
2. Koble klokka til Mac-en med kabel. Fenix 6 og Forerunner 945 vises som disk; nyere klokker trenger [OpenMTP](https://openmtp.ganeshrvel.com).
3. Kopier `.prg`-fila til `GARMIN/APPS/` på klokka, og koble fra.
4. I Atten (TestFlight): Deg → Garmin-klokke → «Koble til Garmin-klokke», og velg klokka i Garmin Connect.
5. Start en runde i Atten, og åpne Atten på klokka.

## Meldinger

| Retning | Melding |
|---|---|
| Klokke → telefon | `{"t":"hello"}`, `{"t":"get","r":runde,"h":hull}`, `{"t":"save","r":runde,"h":hull,"sc":[[spiller,slag],…]}` |
| Telefon → klokke | `{"t":"hole",…}` (se `GarminMessage.hole`) eller `{"t":"none"}` |

Nøklene står i `GarminMessage.swift` og `source/AttenModel.mc`, og testes på begge sider (`GarminMessageTests`, `source/Tests.mc`). Endres den ene, må den andre endres.
