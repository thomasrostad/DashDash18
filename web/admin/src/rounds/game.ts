// Én runde for arrangøren: hele runden som tabell, avkorting, «Avslutt kvelden» og retting av en score,
// som appen (AvslutningLogic.swift, RoundSnapshot.swift `RoundGame`). Ren logikk over regelmotorens runde.

import {
  capitalized, copyRound, countingHoles, courseHoles, dayOne, dayThe, lowestCommonHole, makeRoundFromSnapshot,
  norwegianCompare, numberOfHoles, pointsForEmptyHole, pointsFromScores, holePoints, scoreName, snapshotHandicap,
  snapshotRoster, truncationRule, truncationRuleHelp, truncationRuleName, type DayTerm, type HoleScores, type PlayedHole, type Player,
  type Round, type RoundSnapshot, type Ruleset, type ScoreName, type TruncationRule,
} from "../../../golfgutu-core/src/index.ts";

/** Regelmotorens runde med det appens `RoundGame` regner. */
export class RoundGame {
  readonly snapshot: RoundSnapshot;
  readonly round: Round;
  readonly roster: Player[];
  readonly rules: Ruleset;
  readonly holes: PlayedHole[];

  constructor(snapshot: RoundSnapshot) {
    this.snapshot = snapshot;
    this.round = makeRoundFromSnapshot(snapshot);
    this.roster = snapshotRoster(snapshot);
    this.rules = snapshot.rules;
    this.holes = courseHoles(this.round);
  }

  get roundID(): string { return this.snapshot.round.id; }
  get status() { return this.snapshot.round.status; }
  get holeCount(): number { return numberOfHoles(this.round); }

  name(member: string): string { return this.snapshot.names.get(member) ?? "Ukjent"; }

  /** Spillerens handicap i runden: simulatoren 0, ellers det frosne, ellers `effectiveHandicap`. */
  handicap(member: string): number { return snapshotHandicap(this.snapshot, member, this.round, this.roster); }

  scores(member: string): HoleScores { return this.round.holeScores.get(member) ?? new Map(); }

  /** Stablefordsummen i runden for spilleren, med rundens handicap. */
  total(member: string): number { return pointsFromScores(this.scores(member), this.round, this.handicap(member), this.rules); }

  /** `hullNr`: banens hullnummer. Siste ni heter 10–18. */
  holeNumber(index: number): number { return index + 1 + (this.round.holeStart === 9 ? 9 : 0); }

  get lowestCommonHole(): number { return lowestCommonHole(this.round); }
  get cutRule(): TruncationRule | null { return truncationRule(this.round); }
}

// MARK: - Avkorting

/** Verdien i `rounds.cut_rule`. */
export function cutRuleDatabaseValue(r: TruncationRule): string {
  return r === "felles" ? "common" : r === "nettopar" ? "net_par" : "zero";
}

/** Hjelpeteksten for regelen, uten tankestrek i teksten på siden. */
export function cutRuleHelp(r: TruncationRule): string {
  return truncationRuleHelp(r).replace(/\s*—\s*/g, ", ");
}

export interface CutChoice {
  rule: TruncationRule;
  /** Antall hull runden stoppet etter (1…antall hull). */
  after: number;
}

export interface CutLine {
  memberID: string;
  name: string;
  before: number;
  after: number;
  diff: number;
}

/** «+8», «−8» (ekte minus), «0». */
export function signed(n: number): string {
  return n > 0 ? `+${n}` : n < 0 ? `−${-n}` : "0";
}

export const cutLineText = (l: CutLine) => `${l.name} ${l.before} → ${l.after} (${signed(l.diff)})`;

export interface CutPreview {
  countingHoles: number;
  holes: number;
  lines: CutLine[];
  losers: number;
}

function clampAfter(g: RoundGame, n: number): number {
  return Math.min(g.holeCount, Math.max(1, n));
}

/** `avkortValg`: lagret valg, ellers «felles» etter laveste felles hull (eller hele runden). */
export function defaultCutChoice(g: RoundGame): CutChoice {
  const common = g.lowestCommonHole;
  const rule = g.cutRule;
  if (rule !== null) return { rule, after: clampAfter(g, g.snapshot.round.cutAfter ?? common) };
  return { rule: "felles", after: clampAfter(g, common > 0 ? common : g.holeCount) };
}

function withCut(g: RoundGame, choice: CutChoice | null): Round {
  const draft = copyRound(g.round);
  draft.avkortRegel = choice?.rule ?? null;
  draft.avkortetEtter = choice ? choice.after : null;
  return draft;
}

/** `avkortingenKoster`: summen per spiller før og etter kuttet, med rundens frosne handicap. */
export function cutPreview(g: RoundGame, choice: CutChoice): CutPreview {
  const draft = withCut(g, choice);
  const lines: CutLine[] = [];
  for (const p of g.snapshot.players) {
    const s = g.scores(p.memberID);
    if (s.size === 0) continue;
    const hcp = g.handicap(p.memberID);
    const before = pointsFromScores(s, g.round, hcp, g.rules);
    const after = pointsFromScores(s, draft, hcp, g.rules);
    if (before === after) continue;
    lines.push({ memberID: p.memberID, name: g.name(p.memberID), before, after, diff: after - before });
  }
  lines.sort((a, b) => (a.diff !== b.diff ? a.diff - b.diff : norwegianCompare(a.name, b.name)));
  return { countingHoles: countingHoles(draft), holes: g.holeCount, lines, losers: lines.filter((l) => l.diff < 0).length };
}

/** Hjelpeteksten under «Runden stoppet etter hull». */
export function cutHint(g: RoundGame, rule: TruncationRule): string {
  const common = g.lowestCommonHole;
  if (common <= 0) return "Ingen har ført noe ennå.";
  return `Alle som har begynt har ført til og med hull ${g.holeNumber(common - 1)}. `
    + (rule === "felles" ? "Med denne regelen er det tallet du vil ha." : "Tallet er opplysning her. Regelen over fyller hullene i stedet for å kutte dem.");
}

/** «Hull 14 · laveste felles». */
export function cutOptionTitle(g: RoundGame, after: number): string {
  return `Hull ${g.holeNumber(after - 1)}` + (after === g.lowestCommonHole ? " · laveste felles" : "");
}

/** «Avkortet etter hull 14 · tell til laveste felles hull», eller null. */
export function cutSummary(g: RoundGame): string | null {
  const rule = g.cutRule;
  const after = g.snapshot.round.cutAfter;
  if (rule === null || after === null) return null;
  return `Avkortet etter hull ${g.holeNumber(after - 1)} · ${truncationRuleName(rule).toLowerCase()}`;
}

/** Antall spillere som har begynt, men ikke ført alle tellende hull. Antall førte hull, ikke sammenhengende. */
export function playersMissingHoles(g: RoundGame): number {
  const counting = countingHoles(g.round);
  return g.snapshot.players.filter((p) => {
    const thru = g.scores(p.memberID).size;
    return thru > 0 && thru < counting;
  }).length;
}

/** Endringen i `rounds` for avkortingen. Fjerning skriver eksplisitt null i alle fire. */
export function cutPatch(choice: CutChoice | null, by: string | null, at: Date): Record<string, unknown> {
  if (choice === null) return { cut_rule: null, cut_after: null, cut_by: null, cut_at: null };
  return { cut_rule: cutRuleDatabaseValue(choice.rule), cut_after: choice.after, cut_by: by, cut_at: at.toISOString() };
}

/** Står raden slik vi skrev den? (RLS kan si nei uten feilkode.) */
export function cutPatchMatches(patch: Record<string, unknown>, row: { cut_rule: string | null; cut_after: number | null }): boolean {
  return (row.cut_rule ?? null) === patch.cut_rule && (row.cut_after ?? null) === patch.cut_after;
}

// MARK: - Avslutt kvelden

export interface CloseCheck {
  roundID: string;
  title: string;
  missing: number;
  countingHoles: number;
  emptyHolePoints: number;
  cutSummary: string | null;
}

export function closeCheck(g: RoundGame, title: string): CloseCheck {
  return {
    roundID: g.roundID, title, missing: playersMissingHoles(g), countingHoles: countingHoles(g.round),
    emptyHolePoints: pointsForEmptyHole(g.round, g.rules), cutSummary: cutSummary(g),
  };
}

export interface ClosePrompt {
  title: string;
  lines: string[];
  /** Runden arrangøren bør avkorte først. */
  suggestCut: string | null;
}

/** Spørsmålet før kvelden avsluttes (`handleAvsluttKvelden`). Null når ingen runde går. */
export function closePrompt(checks: readonly CloseCheck[], term: DayTerm = "evening"): ClosePrompt | null {
  if (checks.length === 0) return null;
  const lines: string[] = [];
  let suggest: string | null = null;
  for (const c of checks) {
    const prefix = checks.length > 1 ? `${c.title}: ` : "";
    if (c.missing > 0 && c.cutSummary === null) {
      lines.push(prefix + (c.missing === 1 ? "1 spiller har" : `${c.missing} spillere har`)
        + ` ikke ført alle ${c.countingHoles} hullene. Uspilte hull gir ${c.emptyHolePoints} poeng slik runden står nå, så den som rakk færrest hull taper på det.`);
      if (suggest === null) suggest = c.roundID;
    } else if (c.cutSummary !== null) {
      lines.push(prefix + c.cutSummary + ".");
    }
  }
  lines.push(checks.length === 1 ? "Runden låses og teller i turneringen." : "Rundene låses og teller i turneringen.");
  const title = checks.length === 1 ? `Avslutte ${checks[0].title}?` : `Avslutte ${dayThe(term)}?`;
  return { title, lines, suggestCut: suggest };
}

/** Meldingen etterpå: hva som ble låst, og hva som står igjen. */
export function closeSummary(locked: readonly string[], drafts: readonly string[], failed: readonly string[], term: DayTerm = "evening"): string {
  const day = capitalized(dayThe(term));
  const parts: string[] = [];
  if (locked.length > 0) parts.push(locked.length === 1 ? `${locked[0]} er låst.` : `Låst: ${locked.join(", ")}.`);
  if (failed.length > 0) parts.push(`Ble ikke låst: ${failed.join(", ")}. Prøv igjen.`);
  if (drafts.length === 0) {
    if (failed.length === 0) parts.push(`${day} er ferdig, og neste ${dayOne(term)} står øverst.`);
  } else {
    parts.push(`Kladden ${drafts.join(", ")} er ikke spilt. ${day} er ikke ferdig før den er startet og låst, eller slettet.`);
  }
  return parts.join(" ");
}

// MARK: - Hele runden som tabell

export interface TableColumn { index: number; number: number; par: number; outside: boolean }
export interface TableCell { index: number; strokes: number | null; scoreName: ScoreName | null; outside: boolean }
export interface TableRow { memberID: string; name: string; cells: TableCell[]; strokes: number | null; points: number }
export interface RoundTable { columns: TableColumn[]; parTotal: number; rows: TableRow[]; countingHoles: number; hasOutside: boolean }

/** `rundeSpillere` + `renderHeleRunden`: de som har ført noe, flest poeng først. Har ingen ført noe, står alle. */
export function roundTable(g: RoundGame): RoundTable {
  const counting = countingHoles(g.round);
  const columns = g.holes.map((h, i) => ({ index: i, number: g.holeNumber(i), par: h.par, outside: i >= counting }));
  let members = g.snapshot.players.map((p) => p.memberID).filter((m) => g.scores(m).size > 0);
  if (members.length === 0) members = g.snapshot.players.map((p) => p.memberID);
  const rows = members.map((member) => {
    const s = g.scores(member);
    const hcp = g.handicap(member);
    const cells = g.holes.map((h, i) => {
      const strokes = s.get(i) ?? null;
      return {
        index: i, strokes,
        scoreName: strokes === null ? null : scoreName(h.par, strokes, hcp, h.strokeIndex, g.holeCount),
        outside: i >= counting,
      };
    });
    let gross = 0;
    for (const [k, v] of s) if (k >= 0 && k < g.holes.length) gross += v;
    return { memberID: member, name: g.name(member), cells, strokes: s.size === 0 ? null : gross, points: g.total(member) };
  }).sort((a, b) => (a.points !== b.points ? b.points - a.points : norwegianCompare(a.name, b.name)));
  return {
    columns, parTotal: columns.reduce((s, c) => s + c.par, 0), rows, countingHoles: counting,
    hasOutside: columns.some((c) => c.outside),
  };
}

// MARK: - Rett en score

/** Gyldige slag i føringen (`StrokeInput`). */
export const STROKE_MIN = 1;
export const STROKE_MAX = 12;
export const clampStrokes = (n: number) => Math.min(STROKE_MAX, Math.max(STROKE_MIN, n));

export interface ScoreCorrection {
  memberID: string;
  holeIndex: number;
  /** Det som står lagret nå, eller null. */
  original: number | null;
  strokes: number;
}

/** `velgRundeRute`: åpner med tallet som står, ellers par. */
export function newCorrection(g: RoundGame, member: string, hole: number): ScoreCorrection {
  const original = g.scores(member).get(hole) ?? null;
  return { memberID: member, holeIndex: hole, original, strokes: clampStrokes(original ?? g.holes[hole].par) };
}

export const correctionChanged = (c: ScoreCorrection) => c.strokes !== c.original;

export function stepCorrection(c: ScoreCorrection, delta: number): ScoreCorrection {
  return { ...c, strokes: clampStrokes(c.strokes + delta) };
}

export function correctionButtonTitle(g: RoundGame, c: ScoreCorrection): string {
  return correctionChanged(c) ? `Lagre ${c.strokes} på hull ${g.holeNumber(c.holeIndex)}` : "Lagre rettingen";
}

export function correctionCurrentText(c: ScoreCorrection): string {
  return c.original !== null ? `Står nå: ${c.original} slag.` : "Ikke lagret.";
}

/** Poeng og scorenavn for det nye tallet. */
export function correctionOutcome(g: RoundGame, c: ScoreCorrection): { name: ScoreName; points: number } {
  const h = g.holes[c.holeIndex];
  const hcp = g.handicap(c.memberID);
  return {
    name: scoreName(h.par, c.strokes, hcp, h.strokeIndex, g.holeCount),
    points: holePoints(h.par, c.strokes, hcp, h.strokeIndex, g.holeCount, g.rules),
  };
}

/** Parameterne til `save_hole` for denne ene spilleren. Null når ingenting er endret. */
export function correctionParams(g: RoundGame, c: ScoreCorrection, recordedAt: Date): Record<string, unknown> | null {
  if (!correctionChanged(c)) return null;
  return {
    p_round_id: g.roundID, p_hole_index: c.holeIndex,
    p_scores: [{ member_id: c.memberID, strokes: c.strokes }], p_recorded_at: recordedAt.toISOString(),
  };
}

/** «Hull 2 for Bjørn er rettet fra 6 til 5.» */
export function correctionDoneText(g: RoundGame, c: ScoreCorrection): string {
  return `Hull ${g.holeNumber(c.holeIndex)} for ${g.name(c.memberID)} er rettet ` + (c.original !== null ? `fra ${c.original} ` : "") + `til ${c.strokes}.`;
}

/** Teksten i en låst runde. */
export function correctionNotice(status: string): string | null {
  return status === "locked" ? "Runden er låst. Rettingen regner poengene om, og tavla og matchene følger med." : null;
}
