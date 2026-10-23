// «Lim inn liste»: mange navn på én gang, i Troppen (#145, TroppImport i appen) og som deltakere i en
// klubbturnering (sql/060, ParticipantImport). Ett navn per linje, med handicap etter navnet eller i egen
// kolonne, og for deltakere NGF-nummer. Ren logikk; samme regler og tekster som TroppLogic.swift og
// ParticipantInvite.swift.

export type ImportProblem = { kind: "invalid"; text: string } | { kind: "exists" } | { kind: "repeated" };

export interface ImportLine {
  text: string;
  name: string;
  handicapIndex: number | null;
  ngfNumber: string | null;
  problem: ImportProblem | null;
}

/** Høyst så mange per innliming: Troppen 200, deltakere 300 (`add_competition_participants`). */
export const ROSTER_MAX_LINES = 200;
export const PARTICIPANT_MAX_LINES = 300;

/** Navn i troppen: 1–40 tegn etter trimming (som i skjemaet), ellers null. */
export function normalizedName(raw: string, maxLength = 40): string | null {
  const name = raw.trim();
  return [...name].length >= 1 && [...name].length <= maxLength ? name : null;
}

/** Handicapindeks som på scorekortet (ClubInput.handicapIndex): komma eller punktum, «+» er plusshandicap
 *  (lagres negativt), tomt er ikke oppgitt. Gyldig +10 til 54, én desimal. */
export function handicapIndex(raw: string): { value: number | null } | { error: string } {
  let text = raw.replace(/\s/g, "").replace(/,/g, ".");
  if (!text) return { value: null };
  // Minus er tvetydig (noen skriver plusshandicap som minus). Be om «+» i stedet.
  if (text.startsWith("-") || text.startsWith("−")) return { error: "Plusshandicap skrives med «+», f.eks. +2,3." };
  let sign = 1;
  if (text.startsWith("+")) { sign = -1; text = text.slice(1); }
  if (!/^([0-9]+(\.[0-9]*)?|\.[0-9]+)$/.test(text)) return { error: "Handicap må være et tall, f.eks. 18,4." };
  // Swifts rounded() runder halvveis bort fra null.
  const scaled = sign * Number(text) * 10;
  const index = (Math.sign(scaled) * Math.round(Math.abs(scaled))) / 10;
  if (index < -10 || index > 54) return { error: "Handicap må være mellom +10 og 54." };
  return { value: index === 0 ? 0 : index };
}

/** «18,4» eller «-18.4» som handicap i tabellen (TroppInput.handicapText): plusshandicap med «+». */
export function handicapText(index: number | null): string {
  if (index === null) return "";
  const text = Math.abs(index).toFixed(1).replace(".", ",");
  return index < 0 ? `+${text}` : text;
}

export function nameKey(name: string): string {
  return name.trim().toLowerCase();
}

/** «Kari Nordmann,» → «Kari Nordmann» (komma før handicapet i en e-post). */
function trimmed(name: string): string {
  return name.replace(/^[\s,]+|[\s,]+$/g, "");
}

function looksLikeHandicap(word: string): boolean {
  const digits = word.replace(/^[+-]+/, "");
  return digits.length > 0 && /^[0-9,.]+$/.test(digits);
}

/** Et NGF-nummer har bindestrek mellom sifrene eller minst fire sifre, så det ikke blir tatt for et handicap. */
function looksLikeNGF(text: string): boolean {
  const digits = text.replace(/[^0-9]/g, "").length;
  if (digits === 0 || !/^[0-9-]+$/.test(text)) return false;
  return text.slice(1).includes("-") || digits >= 4;
}

/** Navn og handicap fra én linje. Tabulator eller semikolon skiller kolonnene; ellers er det siste ordet
 *  handicapet hvis det ser ut som et tall («18,4», «+2», «54»). */
export function splitLine(line: string): { name: string; handicap: string } {
  const columns = line.split(/[\t;]/).map((c) => c.trim());
  if (columns.length > 1) return { name: trimmed(columns[0]), handicap: columns.slice(1).find((c) => c !== "") ?? "" };
  const words = line.split(" ").filter((w) => w !== "");
  const last = words[words.length - 1];
  if (words.length > 1 && looksLikeHandicap(last)) return { name: trimmed(words.slice(0, -1).join(" ")), handicap: last };
  return { name: trimmed(line), handicap: "" };
}

/** Navn, handicap og NGF-nummer. I kolonner kan én kolonne være NGF-nummeret: «Kari Nordmann;18,4;12-3456». */
export function lineColumns(line: string): { name: string; handicap: string; ngf: string } {
  const columns = line.split(/[\t;]/).map((c) => c.trim());
  if (columns.length <= 1) return { ...splitLine(line), ngf: "" };
  const rest = columns.slice(1).filter((c) => c !== "");
  return { name: trimmed(columns[0]), handicap: rest.find((c) => !looksLikeNGF(c)) ?? "", ngf: rest.find(looksLikeNGF) ?? "" };
}

function lines(text: string, max: number): string[] {
  return text.split(/\r\n|\r|\n/).map((l) => l.trim()).filter((l) => l !== "").slice(0, max);
}

/** Navnet og handicapet, eller linja med feilen. */
function parseLine(line: string, rawName: string, rawHandicap: string, ngf: string | null): ImportLine | { name: string; handicapIndex: number | null } {
  const name = normalizedName(rawName);
  if (!name) return { text: line, name: rawName, handicapIndex: null, ngfNumber: ngf, problem: { kind: "invalid", text: "Mangler navn, eller navnet er over 40 tegn" } };
  const hcp = handicapIndex(rawHandicap);
  if ("error" in hcp) return { text: line, name, handicapIndex: null, ngfNumber: ngf, problem: { kind: "invalid", text: hcp.error } };
  return { name, handicapIndex: hcp.value };
}

/** Troppen: navn som finnes blant medlemmene (ikke arkiverte, ikke deltakere) hoppes over, og dobbelt i lista. */
export function parseRosterList(text: string, takenNames: readonly string[]): ImportLine[] {
  const taken = new Set(takenNames.map(nameKey));
  const seen = new Set<string>();
  return lines(text, ROSTER_MAX_LINES).map((line) => {
    const { name: rawName, handicap } = splitLine(line);
    const parsed = parseLine(line, rawName, handicap, null);
    if ("problem" in parsed) return parsed;
    const key = nameKey(parsed.name);
    const problem: ImportProblem | null = taken.has(key) ? { kind: "exists" } : seen.has(key) ? { kind: "repeated" } : null;
    seen.add(key);
    return { text: line, ...parsed, ngfNumber: null, problem };
  });
}

/** Deltakere: navn som er påmeldt fra før hoppes over. Samme navn to ganger er samme person, med mindre
 *  NGF-numrene er ulike. */
export function parseParticipantList(text: string, enteredNames: readonly string[]): ImportLine[] {
  const entered = new Set(enteredNames.map(nameKey));
  const accepted: { key: string; ngf: string | null }[] = [];
  return lines(text, PARTICIPANT_MAX_LINES).map((line) => {
    const cols = lineColumns(line);
    const ngf = cols.ngf ? cols.ngf.slice(0, 20) : null;
    const parsed = parseLine(line, cols.name, cols.handicap, ngf);
    if ("problem" in parsed) return parsed;
    const key = nameKey(parsed.name);
    let problem: ImportProblem | null = null;
    if (entered.has(key)) problem = { kind: "exists" };
    else if (accepted.some((a) => a.key === key && (a.ngf === null || ngf === null || a.ngf === ngf))) problem = { kind: "repeated" };
    else accepted.push({ key, ngf });
    return { text: line, ...parsed, ngfNumber: ngf, problem };
  });
}

export function validLines(lines: readonly ImportLine[]): ImportLine[] {
  return lines.filter((l) => l.problem === null);
}

/** Teksten under navnet: hvorfor linja ikke legges til. */
export function problemText(line: ImportLine, participants = false): string | null {
  const p = line.problem;
  if (!p) return null;
  if (p.kind === "invalid") return p.text;
  if (p.kind === "exists") return participants ? "Er påmeldt fra før" : "Finnes i troppen fra før";
  return "Står allerede i lista";
}

/** «3 av 5 legges til». */
export function countText(lines: readonly ImportLine[]): string {
  return `${validLines(lines).length} av ${lines.length} legges til`;
}

/** Radene til club_members (Troppen): ledige navn i klubben. */
export function rosterRows(clubID: string, lines: readonly ImportLine[]) {
  return validLines(lines).map((l) => ({ club_id: clubID, display_name: l.name, handicap_index: l.handicapIndex }));
}

/** `p_entries` til `add_competition_participants`. Tomme verdier sendes ikke. */
export function participantEntries(lines: readonly ImportLine[]) {
  return validLines(lines).map((l) => ({
    display_name: l.name,
    ...(l.handicapIndex !== null ? { handicap_index: l.handicapIndex } : {}),
    ...(l.ngfNumber !== null ? { ngf_number: l.ngfNumber } : {}),
  }));
}

/** «12 lagt til». Null: alle var der fra før. */
export function participantsAddedText(count: number): string {
  return count === 0 ? "Ingen nye. Alle var påmeldt fra før." : `${count} lagt til`;
}

export const ROSTER_IMPORT_HELP =
  `Handicap kan stå etter navnet, f.eks. «Kari Nordmann 18,4». Fra et regneark kan du lime inn to kolonner. Høyst ${ROSTER_MAX_LINES} navn om gangen.`;
export const PARTICIPANT_IMPORT_HELP =
  "Handicap kan stå etter navnet, f.eks. «Kari Nordmann 18,4». Fra et regneark (GolfBox, påmeldingslista) kan du lime inn "
  + `kolonnene navn, handicap og NGF-nummer. Deltakerne blir ikke medlemmer i klubben. Høyst ${PARTICIPANT_MAX_LINES} om gangen.`;
