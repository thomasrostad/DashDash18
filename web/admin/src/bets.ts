// Veddemål på og av per turnering (steg 11, sql/052). Samme bryter som «Veddemål» i appen
// (BetsSwitchRow). Ren logikk her; kallene står i betsApi.ts.

import { isMissing } from "./signups.ts";

/** Under bryteren. Samme tekst som appen (BetTexts.toggleFooter). */
export const BETS_TOGGLE_HELP =
  "Av som standard. Slått av kan ingen lage nye veddemål, men de som finnes, gjøres opp som før.";

/** Argumentene til bets_set_enabled for en turnering (runden er tom). */
export function setEnabledParams(competitionID: string, on: boolean) {
  return { p_competition_id: competitionID, p_round_id: null, p_enabled: on };
}

/** Svaret fra lesingen av competitions.bets_enabled: null når 052 ikke er kjørt (da skjules bryteren). */
export function enabledFromRow(row: { bets_enabled?: boolean | null } | null, error: { code?: string } | null): boolean | null {
  if (error) {
    if (isMissing(error.code)) return null;
    throw error;
  }
  return row?.bets_enabled === true;
}

/** Meldingen etter at bryteren er flyttet. */
export function toggledText(on: boolean): string {
  return on ? "Veddemål er slått på." : "Veddemål er slått av. De som finnes, gjøres opp som før.";
}

/** Feilene fra bets_set_enabled på norsk. */
export function betsErrorText(error: { code?: string; message?: string }): string {
  if (error.code === "42501") return "Bare arrangøren slår veddemål av og på.";
  if (isMissing(error.code)) return "Veddemål kan ikke slås på før databasen er oppdatert.";
  return error.message ?? "Noe gikk galt.";
}
