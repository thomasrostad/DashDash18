# App Store-metadata

Teksten til App Store Connect, én fil per felt, slik at den kan limes rett inn (se `docs/aso-plan.md`, A4 og T3).

- `metadata/nb/`: norsk (bokmål). `name.txt`, `subtitle.txt`, `keywords.txt`, `promotional_text.txt` og `description.txt`.
- `metadata/en-GB/`: English (U.K.). Samme felt, uten beskrivelse.

## Sjekk

```
node docs/app-store/sjekk.mjs
```

Krever bare Node. Avslutter med kode 1 og lister bruddene hvis

- navn eller undertittel er over 30 tegn, nøkkelord over 100, reklametekst over 170 eller beskrivelse over 4000 (Unicode-tegn, avsluttende linjeskift telles ikke)
- nøkkelordene har mellomrom ved komma, eller samme nøkkelord står to ganger
- et nøkkelord også står som helt ord i navn eller undertittel for samme språk
- et nøkkelord står både i nb og en-GB
- en fil inneholder tipping, veddemål, betting, wager eller bet (helt ord)

Kjør sjekken etter hver endring i tekstene.
