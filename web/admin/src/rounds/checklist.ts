// Sjekklista i rundeoppsettet: hver del av oppsettet med status, regnet fra samme sjekk som «Start runden»
// (`setupIssues`), så sjekklista og knappen alltid er enige. Ren logikk, testes i test/checklist.test.ts.
import { issueMessage, type GroupTerm, type RoundSetupIssue } from "./logic.ts";

export type ChecklistKey = "bane" | "start" | "form" | "oppstilling" | "sidepremier";
export type ChecklistState = "ok" | "warn" | "bad";

export interface ChecklistItem {
  key: ChecklistKey;
  title: string;
  state: ChecklistState;
  /** Kort linje: hva som er valgt, eller hva som mangler. */
  text: string;
}

const SECTION: Record<RoundSetupIssue["kind"], ChecklistKey> = {
  noCourse: "bane", courseNotReady: "bane",
  formNotAllowed: "form", formNotSupported: "form",
  tooFewPlayers: "oppstilling", bayWithoutMarker: "oppstilling", teams: "oppstilling", matches: "oppstilling",
  sidePrizeOutsideRound: "sidepremier",
};

export const CHECKLIST_TITLES: Record<ChecklistKey, string> = {
  bane: "Bane", start: "Start", form: "Form", oppstilling: "Oppstilling", sidepremier: "Sidepremier",
};

/**
 * Sjekklista. `summary` er linjen når delen er i orden. `lineupProblems`/`lineupNotes` er tavlas egne
 * (rødt/gult i båsene), som også teller: rødt stopper, gult er verdt å se på.
 */
export function setupChecklist(issues: readonly RoundSetupIssue[], term: GroupTerm, summary: Record<ChecklistKey, string>,
  lineupProblems: readonly string[] = [], lineupNotes: readonly string[] = []): ChecklistItem[] {
  return (Object.keys(CHECKLIST_TITLES) as ChecklistKey[]).map((key) => {
    const mine = issues.filter((i) => SECTION[i.kind] === key).map((i) => issueMessage(i, term));
    if (key === "oppstilling") mine.push(...lineupProblems.filter((p) => !mine.includes(p)));
    if (mine.length > 0) return { key, title: CHECKLIST_TITLES[key], state: "bad", text: mine[0] + (mine.length > 1 ? ` (+${mine.length - 1})` : "") };
    if (key === "oppstilling" && lineupNotes.length > 0) return { key, title: CHECKLIST_TITLES[key], state: "warn", text: lineupNotes[0] };
    return { key, title: CHECKLIST_TITLES[key], state: "ok", text: summary[key] };
  });
}

/** «3 av 5 klart». */
export function checklistCount(items: readonly ChecklistItem[]): { ready: number; total: number } {
  return { ready: items.filter((i) => i.state !== "bad").length, total: items.length };
}
