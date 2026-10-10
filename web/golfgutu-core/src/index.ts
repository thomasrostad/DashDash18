// GolfgutuCore i TypeScript: regelmotoren til Atten, med samme svar som Swift-pakken
// (Packages/GolfgutuCore). Se README.md.
//
// Det en server eller nettside trenger oftest:
// - `standingsFromTavlaData(tavlaData, seasonRow, me)`: svaret fra RPC-en `tavla_data` og sesongraden
//   → tabellen som JSON, med samme tall og tekster som Tavla i appen.
// - `TavlaStandings`, `tavlaInput`, `decodeTavlaData`, `decodeSeasonRow`: de samme stegene hver for seg.
// - `CompetitionScope`, `PersonDirectory`, `LeagueStandings`, `CupStandings`: liga, morro og cup.
// - `Season`: regelmotorens sesong (jakketavla, stablefordsummen, utvalget) for egne runder.

export * from "./jsmath.ts";
export * from "./decode.ts";
export * from "./dayterm.ts";
export * from "./forms.ts";
export * from "./formsetup.ts";
export * from "./models.ts";
export * from "./ruleset.ts";
export * from "./validation.ts";
export * from "./template.ts";
export * from "./course.ts";
export * from "./handicap.ts";
export * from "./whs.ts";
export * from "./scoring.ts";
export * from "./truncation.ts";
export * from "./match.ts";
export * from "./triangle.ts";
export * from "./sideprize.ts";
export * from "./season.ts";
export * from "./competitions.ts";
export * from "./app/rows.ts";
export * from "./app/roundgame.ts";
export * from "./app/tavla.ts";
export * from "./app/competition.ts";
