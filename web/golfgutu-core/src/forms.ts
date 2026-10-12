// Konkurranseformene (`KONKURRANSEFORMER` i db-nytt.js, CompetitionForm.swift). Bare katalogen;
// oppsettet for et antall spillere ligger i formsetup.ts.

/** Hvordan scorekortet føres. */
export type FormCard = "per spiller" | "per lag";

/** Hvor ferdig appen er med formen. */
export type FormSupport = "full" | "delvis" | "mangler";

export interface CompetitionForm {
  readonly id: string;
  readonly name: string;
  /** Spillere per lag. 1 = individuell. */
  readonly teamSize: number;
  readonly card: FormCard;
  /** Hvordan runden regnes (`regning`). */
  readonly scoring: string;
  /** Anbefalt handicaptildeling (`hcpAndel`). `null` der laget har ett handicap. */
  readonly allowance: number | null;
  readonly support: FormSupport;
  /** Tåler formen et lag med én mann mer (`taalerSkjevtLag`)? */
  readonly allowsUnevenTeams: boolean;
  readonly help: string;
}

function form(
  id: string, name: string, teamSize: number, card: FormCard, scoring: string, allowance: number | null,
  support: FormSupport, allowsUnevenTeams: boolean, help: string,
): CompetitionForm {
  return Object.freeze({ id, name, teamSize, card, scoring, allowance, support, allowsUnevenTeams, help });
}

/** `FORM_STANDARD`. */
export const DEFAULT_FORM_ID = "stableford";

/** `KONKURRANSEFORMER`, i samme rekkefølge og med samme tekster som db-nytt.js. */
export const ALL_FORMS: readonly CompetitionForm[] = Object.freeze([
  form("stableford", "Stableford (netto)", 1, "per spiller", "stableford", 0.95, "full", false,
    "Poeng per hull mot netto par. Standarden vår."),
  form("stableford-brutto", "Stableford (brutto)", 1, "per spiller", "stableford-brutto", 0, "delvis", false,
    "Som over, men uten handicap. Fordel for de laveste."),
  form("slag-netto", "Slagspill (netto)", 1, "per spiller", "slag-netto", 0.95, "delvis", false,
    "Sum slag minus handicap. Lavest vinner."),
  form("slag-brutto", "Slagspill (brutto)", 1, "per spiller", "slag-brutto", 0, "delvis", false,
    "Rene slag. Klubbmesterskapets form."),
  form("par-bogey", "Par/bogey", 1, "per spiller", "par-bogey", 0.95, "delvis", false,
    "Pluss, deling eller minus mot netto par på hvert hull."),
  form("maks-score", "Maksimumscore", 1, "per spiller", "maks-score", 0.95, "delvis", false,
    "Som slagspill, men med tak per hull. Holder tempoet oppe."),
  form("match", "Matchspill (individuelt)", 1, "per spiller", "match", 1.0, "full", false,
    "Hull mot hull, én mot én. Krever oppsett av par."),
  form("fourball", "Fourball (beste ball)", 2, "per spiller", "beste-netto", null, "full", true,
    "Begge spiller egen ball, beste netto per hull teller for laget. Laget har ett handicap: summen delt på to."),
  form("fourball-4", "Beste ball (4-mann)", 4, "per spiller", "beste-netto", 0.75, "full", true,
    "Som fourball, men fire på laget."),
  form("sammenlagt-lag", "Sammenlagt lag", 2, "per spiller", "sum-netto", null, "full", false,
    "Begge sine runder legges sammen. Laget har ett handicap: summen delt på to."),
  form("foursome", "Foursome", 2, "per lag", "stableford", 0.5, "full", false,
    "Én ball, annenhvert slag. Laghandicap: summen delt på to."),
  form("greensome", "Greensome", 2, "per lag", "stableford", null, "full", false,
    "Begge slår ut, dere velger én ball, så annenhvert slag. Laghandicap: summen delt på to."),
  form("chapman", "Chapman / Pinehurst", 2, "per lag", "stableford", null, "full", false,
    "Begge slår ut, bytt ball til andreslaget, velg én, så annenhvert slag. Laghandicap: summen delt på to."),
  form("scramble-2", "Scramble (2-mann)", 2, "per lag", "stableford", null, "full", true,
    "Alle slår, dere spiller videre fra den beste ballen. Laghandicap: summen delt på to."),
  form("scramble-4", "Scramble (4-mann)", 4, "per lag", "stableford", null, "full", true,
    "Fire på laget. Tildeling 25/20/15/10 % av banehandicapene."),
  form("skins", "Skins", 1, "per spiller", "skins", 0.95, "mangler", false,
    "Hvert hull er en pott. Deling gjør at potten vokser til neste."),
]);

/** Formene som er kommet til etter PWA-en (steg 7). Ikke med i `ALL_FORMS` eller Golfgutu-oppsettet. */
export const ADDED_FORMS: readonly CompetitionForm[] = Object.freeze([
  form("amerikaner", "Amerikaner", 1, "per spiller", "amerikaner", 1.0, "delvis", false,
    "Fire spiller slagspill og deler 12 poeng på hvert hull: 8, 4, 0, 0 (NGF)."),
  form("kobenhavner", "Københavner", 1, "per spiller", "kobenhavner", 1.0, "delvis", false,
    "Tre spiller slagspill og deler 6 poeng på hvert hull: 4, 2, 0 (NGF)."),
]);

/** Alle formene motoren kjenner: PWA-katalogen og de nye. */
export const FORM_CATALOG: readonly CompetitionForm[] = Object.freeze([...ALL_FORMS, ...ADDED_FORMS]);

/** `konkurranseform`: formen med denne id-en, ellers standardformen. Slår opp i hele katalogen. */
export function formById(id: string | null | undefined): CompetitionForm {
  return FORM_CATALOG.find((f) => f.id === id) ?? ALL_FORMS.find((f) => f.id === DEFAULT_FORM_ID)!;
}

/** `formForRunde`: formen fra `gameType`, uten hensyn til store bokstaver. Ukjent eller tom → stableford. */
export function roundForm(round: { gameType: string | null }): CompetitionForm {
  return formById((round.gameType ?? "").toLowerCase());
}

/** `erLagform`. */
export function isTeamForm(f: CompetitionForm): boolean {
  return f.teamSize > 1;
}

// MARK: To akser (FormAxes.swift)

/** Former for to spillere på en side. */
export type PairForm = "fourball" | "foursome" | "greensome" | "chapman" | "aggregate";
export const PAIR_FORMS: readonly PairForm[] = ["fourball", "foursome", "greensome", "chapman", "aggregate"];

/** Lagformen: hvem som spiller sammen. Samme JSON som Swift. */
export type TeamForm =
  | { type: "individual" }
  | { type: "pairs"; pairs: PairForm }
  | { type: "team"; size: number }
  | { type: "scramble"; size: number };

/** Poengspill i gruppe. */
export type PointsGameKind = "amerikaner" | "kobenhavner";
export const POINTS_GAME_KINDS: readonly PointsGameKind[] = ["amerikaner", "kobenhavner"];

/** Poengtellingen. Samme JSON som Swift. */
export type ScoringMethod =
  | { type: "strokePlay"; net: boolean }
  | { type: "stableford"; net: boolean }
  | { type: "parBogey" }
  | { type: "maximumScore" }
  | { type: "matchPlay" }
  | { type: "pointsGame"; game: PointsGameKind }
  | { type: "skins" };

export interface FormAxes {
  teamForm: TeamForm;
  scoring: ScoringMethod;
}

/** Spillere per side. */
export function teamFormSize(t: TeamForm): number {
  switch (t.type) {
    case "individual":
      return 1;
    case "pairs":
      return 2;
    default:
      return t.size;
  }
}

/** Laget fører ett kort (én ball). */
export function playsOneBall(t: TeamForm): boolean {
  if (t.type === "scramble") return true;
  if (t.type === "pairs") return t.pairs === "foursome" || t.pairs === "greensome" || t.pairs === "chapman";
  return false;
}

/** Høyest score er best (stableford, poeng, skins). Ellers lavest (slag). */
export function higherIsBetter(s: ScoringMethod): boolean {
  return s.type !== "strokePlay" && s.type !== "maximumScore";
}

const IND: TeamForm = { type: "individual" };
const NET_STABLEFORD: ScoringMethod = { type: "stableford", net: true };
const NET_STROKE: ScoringMethod = { type: "strokePlay", net: true };

/** Aksene per form-id. Én til én. */
const AXES_BY_ID: Readonly<Record<string, FormAxes>> = Object.freeze({
  "stableford": { teamForm: IND, scoring: NET_STABLEFORD },
  "stableford-brutto": { teamForm: IND, scoring: { type: "stableford", net: false } },
  "slag-netto": { teamForm: IND, scoring: NET_STROKE },
  "slag-brutto": { teamForm: IND, scoring: { type: "strokePlay", net: false } },
  "par-bogey": { teamForm: IND, scoring: { type: "parBogey" } },
  "maks-score": { teamForm: IND, scoring: { type: "maximumScore" } },
  "match": { teamForm: IND, scoring: { type: "matchPlay" } },
  "fourball": { teamForm: { type: "pairs", pairs: "fourball" }, scoring: NET_STROKE },
  "fourball-4": { teamForm: { type: "team", size: 4 }, scoring: NET_STROKE },
  "sammenlagt-lag": { teamForm: { type: "pairs", pairs: "aggregate" }, scoring: NET_STROKE },
  "foursome": { teamForm: { type: "pairs", pairs: "foursome" }, scoring: NET_STABLEFORD },
  "greensome": { teamForm: { type: "pairs", pairs: "greensome" }, scoring: NET_STABLEFORD },
  "chapman": { teamForm: { type: "pairs", pairs: "chapman" }, scoring: NET_STABLEFORD },
  "scramble-2": { teamForm: { type: "scramble", size: 2 }, scoring: NET_STABLEFORD },
  "scramble-4": { teamForm: { type: "scramble", size: 4 }, scoring: NET_STABLEFORD },
  "skins": { teamForm: IND, scoring: { type: "skins" } },
  "amerikaner": { teamForm: IND, scoring: { type: "pointsGame", game: "amerikaner" } },
  "kobenhavner": { teamForm: IND, scoring: { type: "pointsGame", game: "kobenhavner" } },
});

/** Formen som to akser. */
export function formAxes(f: CompetitionForm): FormAxes {
  const a = AXES_BY_ID[f.id] ?? { teamForm: IND, scoring: NET_STABLEFORD };
  return { teamForm: { ...a.teamForm }, scoring: { ...a.scoring } } as FormAxes;
}

function sameAxes(a: FormAxes, b: FormAxes): boolean {
  return JSON.stringify(a.teamForm) === JSON.stringify(b.teamForm) && sameScoring(a.scoring, b.scoring);
}

function sameScoring(a: ScoringMethod, b: ScoringMethod): boolean {
  return JSON.stringify(a) === JSON.stringify(b);
}

/** Formen med disse aksene, eller `null`. */
export function formByAxes(axes: FormAxes): CompetitionForm | null {
  return FORM_CATALOG.find((f) => sameAxes(formAxes(f), axes)) ?? null;
}

/** Lagform fra JSON (`{ type, pairs?, size? }`). */
export function decodeTeamForm(x: unknown, path = "$"): TeamForm {
  const o = x as Record<string, unknown>;
  if (o === null || typeof o !== "object") throw new Error(`${path}: ventet et objekt`);
  switch (o.type) {
    case "individual":
      return { type: "individual" };
    case "pairs":
      if (!PAIR_FORMS.includes(o.pairs as PairForm)) throw new Error(`${path}.pairs: ukjent`);
      return { type: "pairs", pairs: o.pairs as PairForm };
    case "team":
    case "scramble":
      if (typeof o.size !== "number") throw new Error(`${path}.size: mangler`);
      return { type: o.type, size: o.size };
    default:
      throw new Error(`${path}.type: ukjent lagform`);
  }
}

/** Poengtelling fra JSON (`{ type, net?, game? }`). `net` mangler: netto. */
export function decodeScoringMethod(x: unknown, path = "$"): ScoringMethod {
  const o = x as Record<string, unknown>;
  if (o === null || typeof o !== "object") throw new Error(`${path}: ventet et objekt`);
  switch (o.type) {
    case "strokePlay":
    case "stableford":
      return { type: o.type, net: typeof o.net === "boolean" ? o.net : true };
    case "parBogey":
    case "maximumScore":
    case "matchPlay":
    case "skins":
      return { type: o.type };
    case "pointsGame":
      if (!POINTS_GAME_KINDS.includes(o.game as PointsGameKind)) throw new Error(`${path}.game: ukjent`);
      return { type: "pointsGame", game: o.game as PointsGameKind };
    default:
      throw new Error(`${path}.type: ukjent poengtelling`);
  }
}
