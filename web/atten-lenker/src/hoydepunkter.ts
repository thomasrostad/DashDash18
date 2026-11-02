// Høydepunktene nederst på TV-tavla mens en runde pågår (02.11.2026): bragdene, de beste så langt, hvor
// flightene (båsene) er og jakten på ledelsen. Regnes på serveren med regelmotoren (web/golfgutu-core) fra det
// tv_board_data allerede gir, så klienten bare viser dem. Bare navn og tall som tavla allerede viser.
//
// Bragdene er brutto, som feeden og varslene i appen (`BigScore` og `QuietScore`, `grossScoreEvent`).
// Scorene har ikke tidspunkt, så «nyeste» er hull siden: hvor mange hull spilleren har ført etter bragden.

import {
  claimFromRow, claimsFor, formatMeters, grossScoreEvent, holeNumber, norwegianCompare, numberOfHoles, sidePrizeWinners,
  snapshotHasInward, snapshotScorecard, type GrossScoreEvent, type Round, type RoundsGrid, type RoundSnapshot, type Season,
  type UUID,
} from "../../golfgutu-core/src/index.ts";

/** Ett innslag: en liten linje (`label`) og det som skjedde (`text`, gull kursiv), som merket på forsiden. */
export interface Highlight {
  kind: GrossScoreEvent | "best" | "birdies" | "backNine" | "drive" | "pin" | "groups" | "chase";
  label: string;
  text: string;
}

/** Tabellen innslagene om jakten regnes fra. */
export interface HighlightTable {
  /** Radene i tabellens rekkefølge. `place` er null uten plass («–»). */
  rows: { id: UUID; name: string; place: number | null; total: number }[];
  /** Plassen før siste kveld (runde), som `moves`. null: ingen sammenligning (første kveld, playoff). */
  before: Map<UUID, number> | null;
  /**
   * Vokser totalen nøyaktig med stablefordpoengene spilleren tar i runden? Bare da sier TV-en «trenger N poeng».
   * Matchpoeng, plassering, snitt, beste N, vekt, avkorting og sidepremier som ikke er avgjort: nei.
   */
  additive: (round: Round) => boolean;
}

/** Så mange bragder TV-en holder på (de nyeste). */
const MAX_EVENTS = 6;
/** Så mange flighter (båser) per innslag, så linja får plass. */
const GROUPS_PER_ITEM = 3;

const EVENT_TEXT: Record<GrossScoreEvent, string> = { holeInOne: "hole in one!", albatross: "albatross", eagle: "eagle", birdie: "birdie" };
const EVENT_RANK: Record<GrossScoreEvent, number> = { holeInOne: 0, albatross: 1, eagle: 2, birdie: 3 };

/** «Bjørn», «Bjørn og Ola», «Bjørn, Ola og Kåre». null med flere enn tre (for langt for én linje). */
export function nameList(names: readonly string[]): string | null {
  if (names.length === 0 || names.length > 3) return null;
  return names.length === 1 ? names[0] : `${names.slice(0, -1).join(", ")} og ${names.at(-1)}`;
}

/**
 * Innslagene for runden som pågår (siste kolonne i «Alle runder», den samme som «Live»). Tom når ingen runde pågår:
 * da står resultatene i «Siste runde» ved siden av, og «i kveld» om en runde fra forrige uke ville vært feil.
 */
export function roundHighlights(snapshots: readonly RoundSnapshot[], season: Season, grid: RoundsGrid, table: HighlightTable): Highlight[] {
  const column = grid.columns.at(-1);
  if (!column?.isOngoing) return [];
  const index = snapshots.findIndex((s) => s.round.id === column.roundID);
  if (index < 0) return [];
  const snapshot = snapshots[index];
  const round = season.rounds[index];
  const holeCount = numberOfHoles(round);
  const names = new Map(grid.rows.map((r) => [r.playerID.toLowerCase(), r.name]));
  const nameOf = (id: UUID) => names.get(id.toLowerCase()) ?? null;

  // Hullene hver spiller har ført i runden (scorekortet, Ut og Inn), med slag, par og poeng.
  const cards = new Map<UUID, { index: number; number: number; par: number; strokes: number; points: number }[]>();
  for (const p of snapshot.players) {
    const id = p.memberID.toLowerCase();
    if (cards.has(id) || nameOf(id) === null) continue;
    const lines = [false, ...(snapshotHasInward(snapshot) ? [true] : [])].flatMap((inward) => snapshotScorecard(snapshot, p.memberID, inward).lines);
    cards.set(id, lines.flatMap((l) => (l.strokes === null ? [] : [{ index: l.index, number: l.number, par: l.par, strokes: l.strokes, points: l.points ?? 0 }])));
  }
  const lastHole = (id: UUID) => Math.max(-1, ...(cards.get(id) ?? []).map((l) => l.index));
  const done = (id: UUID) => (cards.get(id)?.length ?? 0) >= holeCount;

  const out: Highlight[] = [];

  // Bragdene, nyeste først (færrest hull siden), så den største.
  const events = [...cards].flatMap(([id, lines]) => lines.flatMap((l) => {
    const e = grossScoreEvent(l.strokes, l.par);
    return e === null ? [] : [{ id, e, number: l.number, age: lastHole(id) - l.index }];
  }));
  events.sort((a, b) => a.age - b.age || EVENT_RANK[a.e] - EVENT_RANK[b.e] || norwegianCompare(nameOf(a.id)!, nameOf(b.id)!) || a.number - b.number);
  for (const x of events.slice(0, MAX_EVENTS)) out.push({ kind: x.e, label: `${nameOf(x.id)} · hull ${x.number}`, text: EVENT_TEXT[x.e] });

  out.push(...chase(table, snapshot, round, cards, done));

  // De beste så langt: flest poeng i runden, flest birdier (brutto, som bragdene) og de ni siste hullene.
  const best = (label: string, values: [UUID, number][], unit: (n: number) => string, kind: Highlight["kind"]) => {
    const top = Math.max(0, ...values.map(([, v]) => v));
    if (top <= 0) return;
    const who = nameList(values.filter(([, v]) => v === top).map(([id]) => nameOf(id)!).sort(norwegianCompare));
    if (who !== null) out.push({ kind, label, text: `${who} · ${unit(top)}` });
  };
  const points = season.roundPoints(index);
  best("Best så langt", [...cards.keys()].filter((id) => cards.get(id)!.length > 0).map((id) => [id, points.get(id) ?? 0]),
    (n) => `${n} poeng`, "best");
  best("Flest birdier så langt", [...cards].map(([id, lines]) => [id, lines.filter((l) => grossScoreEvent(l.strokes, l.par) !== null).length]),
    (n) => (n === 1 ? "1 birdie" : `${n} birdier`), "birdies");
  if (holeCount === 18) {
    best("Best på de ni siste", [...cards].flatMap(([id, lines]) => {
      const back = lines.filter((l) => l.index >= 9);
      return back.length === 9 ? [[id, back.reduce((s, l) => s + l.points, 0)] as [UUID, number]] : [];
    }), (n) => `${n} poeng`, "backNine");
  }

  // Sidepremiene i runden, med regelmotorens rekkefølge (lengst / nærmest først, så den som meldte først).
  const claims = snapshot.sideClaims.map(claimFromRow);
  for (const [kind, label] of [["drive", "Lengste drive så langt"], ["pin", "Nærmest pinnen så langt"]] as const) {
    const sorted = claimsFor(kind === "drive" ? "drive" : "kp", round, claims);
    const who = nameList(sidePrizeWinners(sorted).flatMap((id) => nameOf(id) ?? []));
    if (who !== null) out.push({ kind, label, text: `${who} · ${formatMeters(sorted[0].meters)}` });
  }

  out.push(...groups(snapshot, round, cards, done));
  return out;
}

/**
 * Jakten: hvem som har gått forbi hvem siden forrige kveld (samme sammenligning som `moves`), og hva den nærmeste
 * trenger for å gå forbi lederen. «Trenger» bare når lederen er ferdig (eller ikke spiller), jageren har hull igjen,
 * ingen hull er skjult og totalen vokser nøyaktig med stablefordpoengene (`additive`). N er det som gir flere poeng
 * enn lederen: likt avgjøres av tiebreak eller delt plass, og det er ikke sikkert.
 */
function chase(table: HighlightTable, snapshot: RoundSnapshot, round: Round,
  cards: Map<UUID, unknown[]>, done: (id: UUID) => boolean): Highlight[] {
  const out: Highlight[] = [];
  const rows = table.rows.filter((r) => r.place !== null);
  const id = (r: { id: UUID }) => r.id.toLowerCase();
  const leaders = rows.filter((r) => r.place === 1);

  if (table.before !== null) {
    const before = table.before;
    const movers = rows.filter((r) => before.has(id(r)) && before.get(id(r))! > r.place!).sort((a, b) => a.place! - b.place!);
    for (const x of movers.slice(0, 3)) {
      if (x.place === 1 && leaders.length === 1) { out.push({ kind: "chase", label: "Jakten", text: `${x.name} har tatt ledelsen` }); continue; }
      const passed = rows.filter((y) => before.has(id(y)) && before.get(id(y))! < before.get(id(x))! && y.place! > x.place!);
      const who = nameList(passed.map((y) => y.name));
      if (who !== null) out.push({ kind: "chase", label: "Jakten", text: `${x.name} har gått forbi ${who}` });
    }
  }

  const playing = (r: { id: UUID }) => cards.has(id(r));
  if (snapshot.round.hideLastHoles > 0 || !table.additive(round) || leaders.length === 0) return out;
  if (!leaders.every((l) => !playing(l) || done(id(l)))) return out;
  const leaderNames = nameList(leaders.map((l) => l.name));
  if (leaderNames === null) return out;
  const top = leaders[0].total;
  const chasers = rows.filter((r) => r.place! > 1 && playing(r) && !done(id(r)))
    .map((r) => ({ r, need: Math.floor(top - r.total + 1e-9) + 1 }))
    .sort((a, b) => a.need - b.need || a.r.place! - b.r.place!);
  for (const { r, need } of chasers.slice(0, 2)) {
    out.push({ kind: "chase", label: "Jakten", text: `${r.name} trenger ${need} poeng for å gå forbi ${leaderNames}` });
  }
  return out;
}

/**
 * Hvor flightene (båsene i simulatoren) er: hullet etter det siste noen i gruppen har ført. Ferdig når alle har
 * ført alle hullene. Med skjulte hull står det «på de siste hullene» når gruppen har kommet dit.
 */
function groups(snapshot: RoundSnapshot, round: Round, cards: Map<UUID, { index: number }[]>, done: (id: UUID) => boolean): Highlight[] {
  const course = snapshot.round.venue === "course";
  const [title, lower] = course ? ["Flight", "flight"] : ["Bås", "bås"];
  const holeCount = numberOfHoles(round);
  const visible = holeCount - Math.min(snapshot.round.hideLastHoles, holeCount);
  const bays = new Map<number, UUID[]>();
  for (const p of snapshot.players) {
    if (p.bayNo === null || !cards.has(p.memberID.toLowerCase())) continue;
    bays.set(p.bayNo, [...(bays.get(p.bayNo) ?? []), p.memberID.toLowerCase()]);
  }
  const parts: string[] = [];
  for (const [no, ids] of [...bays].sort((a, b) => a[0] - b[0])) {
    const last = Math.max(-1, ...ids.flatMap((id) => cards.get(id)!.map((l) => l.index)));
    if (last < 0) continue;
    const where = ids.every(done) ? "er ferdig"
      : visible < holeCount && last >= visible - 1 ? "er på de siste hullene"
      : `på hull ${holeNumber(round, Math.min(last + 1, holeCount - 1))}`;
    parts.push(`${parts.length % GROUPS_PER_ITEM === 0 ? title : lower} ${no} ${where}`);
  }
  const out: Highlight[] = [];
  for (let i = 0; i < parts.length; i += GROUPS_PER_ITEM) {
    out.push({ kind: "groups", label: course ? "Ute på banen" : "I båsene", text: parts.slice(i, i + GROUPS_PER_ITEM).join(" · ") });
  }
  return out;
}
