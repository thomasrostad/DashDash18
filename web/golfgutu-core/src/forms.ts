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

/** `konkurranseform`: formen med denne id-en, ellers standardformen. */
export function formById(id: string | null | undefined): CompetitionForm {
  return ALL_FORMS.find((f) => f.id === id) ?? ALL_FORMS.find((f) => f.id === DEFAULT_FORM_ID)!;
}

/** `formForRunde`: formen fra `gameType`, uten hensyn til store bokstaver. Ukjent eller tom → stableford. */
export function roundForm(round: { gameType: string | null }): CompetitionForm {
  return formById((round.gameType ?? "").toLowerCase());
}

/** `erLagform`. */
export function isTeamForm(f: CompetitionForm): boolean {
  return f.teamSize > 1;
}
