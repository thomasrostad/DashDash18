// Hva et antall spillere gir i en form (FormSetup.swift): `lagdeling`, `oppsettForAntall` og
// `formerSomPasser`. Største lag per bås kommer fra regelsettet.

import { ALL_FORMS, formById, type CompetitionForm } from "./forms.ts";
import { allowedForms, GOLFGUTU, type Ruleset } from "./ruleset.ts";

/** Hvordan et antall spillere deles i sider. */
export interface TeamSplit {
  /** Antall lag. Alltid et partall. */
  sides: number;
  /** Lagstørrelsene. De som blir til overs fordeles én per lag fra første. */
  sizes: number[];
  matches: number;
}

export type FormSetup =
  | { kind: "individual"; duels: number; triangle: boolean; text: string }
  | { kind: "teams"; split: TeamSplit; uneven: boolean; text: string }
  | { kind: "impossible"; reason: string };

export function setupIsOK(s: FormSetup): boolean {
  return s.kind !== "impossible";
}

/** Teksten som beskriver kvelden, f.eks. «4 dueller og én trekant». */
export function setupText(s: FormSetup): string | null {
  return s.kind === "impossible" ? null : s.text;
}

/** Hvorfor det ikke går opp. */
export function setupReason(s: FormSetup): string | null {
  return s.kind === "impossible" ? s.reason : null;
}

export function setupIsTriangle(s: FormSetup): boolean {
  return s.kind === "individual" && s.triangle;
}

export function setupIsUneven(s: FormSetup): boolean {
  return s.kind === "teams" && s.uneven;
}

/** En form som går opp med antallet. */
export interface FormSuggestion {
  id: string;
  name: string;
  text: string;
  uneven: boolean;
  triangle: boolean;
}

/** `SPILLERE_PER_BAAS` i Golfgutu-oppsettet. */
export function golfgutuMaxPerBay(): number {
  return GOLFGUTU.formats.maxPerBay;
}

/**
 * `lagdeling`: et partall lag på `k` (eller `k + 1` der formen tåler skjeve lag), aldri større enn en
 * bås. Flest mulig lag. `null` når det ikke går opp.
 */
export function teamSplit(players: number, k: number, allowsUneven: boolean, maxPerBay: number = golfgutuMaxPerBay()): TeamSplit | null {
  const maxSize = Math.min(allowsUneven ? k + 1 : k, maxPerBay);
  if (maxSize < k) return null;
  let best: number | null = null;
  let sides = 2;
  while (sides * k <= players) {
    if (players <= sides * maxSize) best = sides;
    sides += 2;
  }
  if (best === null) return null;
  const extra = players - best * k;
  const sizes = Array.from({ length: best }, (_, i) => k + (i < extra ? 1 : 0));
  return { sides: best, sizes, matches: Math.trunc(best / 2) };
}

/** `oppsettForAntall` for denne formen. */
export function formSetup(f: CompetitionForm, players: number, maxPerBay: number = golfgutuMaxPerBay()): FormSetup {
  if (players < 2) return { kind: "impossible", reason: "Det må være minst to for å få en duell." };

  if (f.teamSize === 1) {
    const triangle = players % 2 === 1;
    const duels = Math.trunc((players - (triangle ? 3 : 0)) / 2);
    const parts: string[] = [];
    if (duels !== 0) parts.push(`${duels}` + (duels === 1 ? " duell" : " dueller"));
    if (triangle) parts.push("én trekant");
    return { kind: "individual", duels, triangle, text: parts.join(" og ") };
  }

  const split = teamSplit(players, f.teamSize, f.allowsUnevenTeams, maxPerBay);
  if (split === null) {
    return {
      kind: "impossible",
      reason: `${players} mann går ikke opp i et likt antall lag på ${f.teamSize}`
        + (f.allowsUnevenTeams ? "" : ", og denne formen tåler ikke skjeve lag") + ".",
    };
  }
  const uneven = split.sizes.some((s) => s !== f.teamSize);
  const text = `${split.sides} lag (` + split.sizes.map(String).join("+") + ") · "
    + `${split.matches}` + (split.matches === 1 ? " match" : " matcher");
  return { kind: "teams", split, uneven, text };
}

/** `oppsettForAntall` for en form-id. */
export function setupFor(formID: string | null, players: number, maxPerBay: number = golfgutuMaxPerBay()): FormSetup {
  return formSetup(formById(formID), players, maxPerBay);
}

/** `formerSomPasser`: de ferdige formene som går opp med antallet, i registerets rekkefølge. */
export function formSuggestions(players: number, forms: readonly CompetitionForm[] = ALL_FORMS, maxPerBay: number = golfgutuMaxPerBay()): FormSuggestion[] {
  const out: FormSuggestion[] = [];
  for (const f of forms) {
    if (f.support !== "full") continue;
    const s = formSetup(f, players, maxPerBay);
    const text = setupText(s);
    if (text === null) continue;
    out.push({ id: f.id, name: f.name, text, uneven: setupIsUneven(s), triangle: setupIsTriangle(s) });
  }
  return out;
}

/** `oppsettForAntall` med regelsettets bås-størrelse. */
export function rulesetSetup(r: Ruleset, formID: string | null, players: number): FormSetup {
  return setupFor(formID, players, r.formats.maxPerBay);
}

/** `formerSomPasser` blant de tillatte formene, med regelsettets bås-størrelse. */
export function rulesetSuggestions(r: Ruleset, players: number): FormSuggestion[] {
  return formSuggestions(players, allowedForms(r), r.formats.maxPerBay);
}
