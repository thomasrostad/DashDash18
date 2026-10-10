// Startlista for en spilledag (TournamentCore.swift `StartList`, sql/032 `save_start_list`). Ren logikk.

export interface StartGroupRow {
  round_id: string;
  group_no: number;
  /** «18:10:00». */
  starts_at: string | null;
  start_hole: number | null;
  resource_label: string | null;
  scorer_id: string | null;
}

export interface StartGroupDraft {
  groupNo: number;
  /** «18:10», eller null. */
  startsAt: string | null;
  startHole: number | null;
  resourceLabel: string;
  scorerID: string | null;
  memberIDs: string[];
}

/** «18:10:00» → «18:10». */
export const timeText = (t: string) => t.slice(0, 5);

/** «Bås 3» i simulatoren, tom på ekte bane. */
export function defaultLabel(groupNo: number, venue: string | null): string {
  return venue === "course" ? "" : `Bås ${groupNo}`;
}

/**
 * Gruppene fra båsfordelingen, med det som er lagret. Grupper som er lagret, men ikke har spillere lenger,
 * står med tom spillerliste. En runde uten båser eller flighter har ingen grupper.
 */
export function startGroups(players: readonly { memberID: string; bayNo: number | null }[], saved: readonly StartGroupRow[], venue: string | null): StartGroupDraft[] {
  const byGroup = new Map<number, string[]>();
  for (const p of players) {
    if (p.bayNo === null) continue;
    byGroup.set(p.bayNo, [...(byGroup.get(p.bayNo) ?? []), p.memberID]);
  }
  const savedByNo = new Map<number, StartGroupRow>();
  for (const s of saved) if (!savedByNo.has(s.group_no)) savedByNo.set(s.group_no, s);
  const numbers = [...new Set([...byGroup.keys(), ...savedByNo.keys()])].sort((a, b) => a - b);
  return numbers.map((no) => {
    const s = savedByNo.get(no);
    return {
      groupNo: no,
      startsAt: s?.starts_at ? timeText(s.starts_at) : null,
      startHole: s?.start_hole ?? null,
      resourceLabel: s?.resource_label ?? defaultLabel(no, venue),
      scorerID: s?.scorer_id ?? null,
      memberIDs: byGroup.get(no) ?? [],
    };
  });
}

/** «18:10» → 1090 minutter, eller null. */
export function minutes(text: string): number | null {
  const parts = text.split(":");
  if (parts.length < 2) return null;
  if (!/^\d+$/.test(parts[0]) || !/^\d+$/.test(parts[1])) return null;
  const h = Number(parts[0]), m = Number(parts[1]);
  if (h < 0 || h >= 24 || m < 0 || m >= 60) return null;
  return h * 60 + m;
}

/** 1090 → «18:10» (rundt midnatt). */
export function clock(total: number): string {
  const m = ((total % 1440) + 1440) % 1440;
  return `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;
}

/** Tee-tider med fast mellomrom fra første gruppe. */
export function fillTimes(groups: readonly StartGroupDraft[], first: string, intervalMinutes: number): StartGroupDraft[] {
  const start = minutes(first);
  if (start === null) return [...groups];
  return groups.map((g, i) => ({ ...g, startsAt: clock(start + i * Math.max(intervalMinutes, 0)) }));
}

/** Kanonstart: gruppe nr. i på hull i (rundt). Tiden fra første gruppe brukes for alle. */
export function shotgun(groups: readonly StartGroupDraft[], holeCount: number): StartGroupDraft[] {
  if (holeCount <= 0) return [...groups];
  const time = groups[0]?.startsAt ?? null;
  return groups.map((g, i) => ({ ...g, startHole: (i % holeCount) + 1, startsAt: time !== null ? time : g.startsAt }));
}

/** Samme sjekker som `save_start_list`, med norsk tekst. */
export function startListIssues(groups: readonly StartGroupDraft[], wave: number, holeCount: number, staffIDs: ReadonlySet<string>): string[] {
  const out: string[] = [];
  if (!(wave >= 1 && wave <= 20)) out.push("Puljen må være mellom 1 og 20.");
  if (groups.length > 99) out.push("Høyst 99 grupper.");
  const numbers = groups.map((g) => g.groupNo);
  if (new Set(numbers).size !== numbers.length) out.push("To grupper har samme nummer.");
  if (numbers.some((n) => n < 1 || n > 99)) out.push("Gruppenummeret må være mellom 1 og 99.");
  const max = Math.max(holeCount, 1);
  if (groups.some((g) => g.startHole !== null && (g.startHole < 1 || g.startHole > max))) out.push(`Starthullet må være mellom 1 og ${holeCount}.`);
  if (groups.some((g) => g.startsAt !== null && minutes(g.startsAt) === null)) out.push("Starttiden må være på formen TT:MM.");
  if (groups.some((g) => g.scorerID !== null && !staffIDs.has(g.scorerID))) out.push("En funksjonær er ikke lenger i staben.");
  if (groups.some((g) => g.resourceLabel.trim().length > 40)) out.push("Bås eller tee kan ha høyst 40 tegn.");
  return out;
}

/** Parameterne til `save_start_list`. Tom bås/tee sendes som null. */
export function startListParams(roundID: string, wave: number, groups: readonly StartGroupDraft[]) {
  return {
    p_round_id: roundID,
    p_wave_no: wave,
    p_groups: groups.map((g) => {
      const label = g.resourceLabel.trim();
      return { group_no: g.groupNo, starts_at: g.startsAt, start_hole: g.startHole, resource_label: label === "" ? null : label, scorer_id: g.scorerID };
    }),
  };
}

/** «Anders, Bjørn» for gruppa i startlista. */
export function namesText(names: readonly string[]): string {
  return names.length === 0 ? "Ingen spillere" : names.join(", ");
}
