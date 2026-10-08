// Ren logikk for slope-sync: tolke slope.no, vaske dataene, finne hva som er
// nytt eller endret. Ingen nettverk, ingen database (testes i logic_test.ts).
//
// Kilden: https://slope.no/wp-json/golfhs/v1/meta og …/export (åpent API,
// eieren ber bare om kreditering og lenke til slope.no i appen).

/** Kildenavnet i courses.source og course_tees.source. */
export const SOURCE = "slope";

/**
 * Hvor mange baner som sendes til course_feed_apply i én del. Med hull per tee (sql/030) blir en
 * del større; logic_test.ts sjekker at ingen del av hele eksporten passerer MAX_PART_BYTES.
 */
export const CHUNK_SIZE = 100;

/** Øvre grense for én del (JSON) som testen holder delene under. */
export const MAX_PART_BYTES = 1_000_000;

// Grensene i databasen (sql/001, sql/029). Rader utenfor hoppes over.
const COURSE_NAME_MAX = 80;
const CITY_MAX = 80;
const TEE_NAME_MAX = 60;
const RATING_MIN = 20;
const RATING_MAX = 90;
const SLOPE_MIN = 55;
const SLOPE_MAX = 155;
const PAR_MIN = 27;
const PAR_MAX = 80;
const SORT_MAX = 999;
const HOLE_PAR_MIN = 3;
const HOLE_PAR_MAX = 6;
const STROKE_INDEX_MAX = 18;
const LENGTH_MIN = 50;
const LENGTH_MAX = 700;

// --- Kildens form ------------------------------------------------------------

export interface SlopeMeta {
  api_version?: number;
  data_version: number | string;
  updated_at?: string;
}

export interface SlopeTee {
  id: number | string;
  name?: string | null;
  gender?: string | null;
  slope_rating?: number | string | null;
  course_rating?: number | string | null;
  par?: number | string | null;
  sort_order?: number | string | null;
  /** Hullene på teen: [hullnummer, par, indeks, lengde i meter]. Mangler på rundt en tredel av teene. */
  holes?: unknown;
}

export interface SlopeCourse {
  id: number | string;
  name?: string | null;
  city?: string | null;
  country?: string | null;
  tees?: SlopeTee[] | null;
  // Resten (adresse, greenfee, beskrivelse …) brukes ikke.
  [key: string]: unknown;
}

export interface SlopeExport {
  api_version?: number;
  data_version: number | string;
  generated_at?: string | null;
  courses: SlopeCourse[];
}

// --- Det databasen får (course_feed_apply, sql/029 og sql/030) ---------------

/** Ett hull, kompakt som i kilden: [hullnummer, par, indeks eller null, lengde i meter eller null]. */
export type FeedHole = [number, number, number | null, number | null];

export interface FeedTee {
  external_id: string;
  name: string;
  gender: "men" | "women";
  course_rating: number;
  slope_rating: number;
  par: number | null;
  sort_order: number;
  /** Teens hull (9 eller 18), eller tom: teen har ingen gyldige hull hos kilden. */
  holes: FeedHole[];
}

export interface FeedCourse {
  external_id: string;
  name: string;
  city: string | null;
  country: string | null;
  /** Fra standard-teen (første herre-tee), eller null. */
  course_rating: number | null;
  slope_rating: number | null;
  /**
   * Banens hull (course_holes): hullene til hull-teen (første herre-tee med hull etter
   * rekkefølgen, ellers første tee med hull). Tom når ingen tee har hull.
   */
  holes: FeedHole[];
  tees: FeedTee[];
}

export interface Skipped {
  external_id: string;
  reason: string;
}

export interface MappedExport {
  dataVersion: string;
  generatedAt: string | null;
  courses: FeedCourse[];
  skippedCourses: Skipped[];
  skippedTees: Skipped[];
  /** Tees som står, men uten hull fordi hullene hos kilden ikke var gyldige. */
  skippedHoles: Skipped[];
}

// --- Versjonen ---------------------------------------------------------------

/** Versjonen som tekst (kilden sender tall). Tom eller ugyldig gir null. */
export function versionText(value: unknown): string | null {
  if (typeof value === "number" && Number.isFinite(value)) return String(value);
  if (typeof value === "string" && value.trim() !== "") return value.trim();
  return null;
}

/**
 * Trengs eksporten? Bare når meta har en versjon og den er en annen enn den
 * lagrede. Uten lagret versjon (første kjøring) hentes alt.
 */
export function needsExport(meta: SlopeMeta | null | undefined, stored: string | null | undefined): boolean {
  const version = versionText(meta?.data_version);
  if (version === null) throw new Error("meta mangler data_version");
  return version !== (stored ?? null);
}

// --- Vasking -----------------------------------------------------------------

const COUNTRIES: Record<string, string> = {
  norway: "NO",
  norge: "NO",
  sweden: "SE",
  sverige: "SE",
  denmark: "DK",
  danmark: "DK",
  finland: "FI",
  suomi: "FI",
  iceland: "IS",
  island: "IS",
  ísland: "IS",
  poland: "PL",
  polen: "PL",
  germany: "DE",
  tyskland: "DE",
};

/** «Norway» → «NO». En kode på to bokstaver beholdes. Ukjent gir null. */
export function countryCode(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const text = value.trim();
  if (/^[A-Za-z]{2}$/.test(text)) return text.toUpperCase();
  return COUNTRIES[text.toLowerCase()] ?? null;
}

function cleanText(value: unknown, max: number): string | null {
  if (typeof value !== "string") return null;
  const text = value.replace(/\s+/g, " ").trim();
  if (text === "") return null;
  return text.length > max ? text.slice(0, max).trimEnd() : text;
}

function toNumber(value: unknown): number | null {
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  if (typeof value === "string" && value.trim() !== "") {
    const n = Number(value.trim().replace(",", "."));
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

function idText(value: unknown): string | null {
  if (typeof value === "number" && Number.isInteger(value)) return String(value);
  if (typeof value === "string" && value.trim() !== "" && value.trim().length <= 100) return value.trim();
  return null;
}

/**
 * Hullene på en tee, vasket. Gyldig: 9 eller 18 hull nummerert 1…n, par 3–6, indeks 1–18 og unik
 * på teen (eller tom på alle hullene), og summen av parene lik teens par når den er oppgitt. En
 * lengde utenfor 50–700 m blir tom (databasens grense), resten av hullet står. Gir hullene sortert
 * på nummer, en tom liste når kilden ikke har hull, eller grunnen til at de ikke kan brukes.
 */
export function mapHoles(raw: unknown, teePar: number | null): FeedHole[] | { reason: string } {
  if (raw === undefined || raw === null) return [];
  if (!Array.isArray(raw)) return { reason: "hullene er ikke en liste" };
  if (raw.length === 0) return [];
  if (raw.length !== 9 && raw.length !== 18) return { reason: `${raw.length} hull` };
  const holes: FeedHole[] = [];
  for (const entry of raw) {
    if (!Array.isArray(entry) || entry.length < 2) return { reason: "et hull har feil form" };
    const number = toNumber(entry[0]);
    const par = toNumber(entry[1]);
    const index = toNumber(entry[2]);
    const length = toNumber(entry[3]);
    if (number === null || !Number.isInteger(number)) return { reason: `hullnummer ${entry[0]}` };
    if (par === null || !Number.isInteger(par) || par < HOLE_PAR_MIN || par > HOLE_PAR_MAX) {
      return { reason: `par ${entry[1]} på hull ${number}` };
    }
    if (index !== null && (!Number.isInteger(index) || index < 1 || index > STROKE_INDEX_MAX)) {
      return { reason: `indeks ${entry[2]} på hull ${number}` };
    }
    const meters = length !== null && Number.isInteger(length) && length >= LENGTH_MIN && length <= LENGTH_MAX
      ? length
      : null;
    holes.push([number, par, index, meters]);
  }
  holes.sort((a, b) => a[0] - b[0]);
  if (holes.some((h, i) => h[0] !== i + 1)) return { reason: `hullene er ikke nummerert 1–${holes.length}` };
  const known = holes.map((h) => h[2]).filter((i): i is number => i !== null);
  if (known.length !== 0 && known.length !== holes.length) return { reason: "indeks mangler på noen hull" };
  if (new Set(known).size !== known.length) return { reason: "to hull har samme indeks" };
  const sum = holes.reduce((total, h) => total + h[1], 0);
  if (teePar !== null && sum !== teePar) {
    return { reason: `par per hull (${sum}) stemmer ikke med teens par (${teePar})` };
  }
  return holes;
}

/**
 * Én tee, eller grunnen til at den hoppes over. Ugyldige hull gjør ikke teen ugyldig: den får
 * ingen hull, og grunnen står i `holesSkipped`.
 */
export function mapTee(tee: SlopeTee): (FeedTee & { holesSkipped?: string }) | Skipped {
  const id = idText(tee?.id);
  if (id === null) return { external_id: String(tee?.id ?? ""), reason: "mangler id" };
  const name = cleanText(tee.name, TEE_NAME_MAX);
  if (name === null) return { external_id: id, reason: "mangler navn" };
  const gender = typeof tee.gender === "string" ? tee.gender.trim().toLowerCase() : "";
  if (gender !== "men" && gender !== "women") return { external_id: id, reason: `ukjent kjønn ${gender}` };
  const rating = toNumber(tee.course_rating);
  if (rating === null || rating < RATING_MIN || rating > RATING_MAX) {
    return { external_id: id, reason: `course rating ${tee.course_rating}` };
  }
  const slope = toNumber(tee.slope_rating);
  if (slope === null || !Number.isInteger(slope) || slope < SLOPE_MIN || slope > SLOPE_MAX) {
    return { external_id: id, reason: `slope ${tee.slope_rating}` };
  }
  const rawPar = toNumber(tee.par);
  const par = rawPar !== null && Number.isInteger(rawPar) && rawPar >= PAR_MIN && rawPar <= PAR_MAX ? rawPar : null;
  const sort = toNumber(tee.sort_order);
  const holes = mapHoles(tee.holes, par);
  const mapped: FeedTee & { holesSkipped?: string } = {
    external_id: id,
    name,
    gender,
    course_rating: Math.round(rating * 10) / 10,
    slope_rating: slope,
    par,
    sort_order: sort !== null && Number.isInteger(sort) ? Math.min(Math.max(sort, 0), SORT_MAX) : 0,
    holes: Array.isArray(holes) ? holes : [],
  };
  if (!Array.isArray(holes)) mapped.holesSkipped = holes.reason;
  return mapped;
}

function isSkipped(value: FeedTee | Skipped): value is Skipped {
  return "reason" in value;
}

/** Rekkefølgen i appen: sort_order, så id. */
export function sortTees(tees: FeedTee[]): FeedTee[] {
  return [...tees].sort((a, b) =>
    a.sort_order - b.sort_order || a.external_id.localeCompare(b.external_id, "en", { numeric: true })
  );
}

/** Standard-teen: første herre-tee etter sort_order, ellers første tee. */
export function defaultTee(tees: FeedTee[]): FeedTee | null {
  const sorted = sortTees(tees);
  return sorted.find((t) => t.gender === "men") ?? sorted[0] ?? null;
}

/** Hull-teen (banens hull i course_holes): første herre-tee med hull, ellers første tee med hull. */
export function holeTee(tees: FeedTee[]): FeedTee | null {
  return defaultTee(tees.filter((t) => t.holes.length > 0));
}

/** Én bane med teene sine, eller grunnen til at den hoppes over. */
export function mapCourse(
  course: SlopeCourse,
): { course: FeedCourse | null; skippedCourse?: Skipped; skippedTees: Skipped[]; skippedHoles: Skipped[] } {
  const id = idText(course?.id);
  if (id === null) {
    return {
      course: null,
      skippedCourse: { external_id: String(course?.id ?? ""), reason: "mangler id" },
      skippedTees: [],
      skippedHoles: [],
    };
  }
  const name = cleanText(course.name, COURSE_NAME_MAX);
  if (name === null) {
    return { course: null, skippedCourse: { external_id: id, reason: "mangler navn" }, skippedTees: [], skippedHoles: [] };
  }

  const skippedTees: Skipped[] = [];
  const skippedHoles: Skipped[] = [];
  const byId = new Map<string, FeedTee>();
  for (const raw of Array.isArray(course.tees) ? course.tees : []) {
    const mapped = mapTee(raw);
    if (isSkipped(mapped)) {
      skippedTees.push(mapped);
      continue;
    }
    const { holesSkipped, ...tee } = mapped;
    if (byId.has(tee.external_id)) {
      skippedTees.push({ external_id: tee.external_id, reason: "dobbel id" });
      continue;
    }
    if (holesSkipped) skippedHoles.push({ external_id: tee.external_id, reason: holesSkipped });
    byId.set(tee.external_id, tee);
  }
  const tees = sortTees([...byId.values()]);
  const standard = defaultTee(tees);
  return {
    course: {
      external_id: id,
      name,
      city: cleanText(course.city, CITY_MAX),
      country: countryCode(course.country),
      course_rating: standard?.course_rating ?? null,
      slope_rating: standard?.slope_rating ?? null,
      holes: holeTee(tees)?.holes ?? [],
      tees,
    },
    skippedTees,
    skippedHoles,
  };
}

/** Hele eksporten, vasket. Doble bane-id-er: den første vinner. */
export function mapExport(data: SlopeExport): MappedExport {
  const version = versionText(data?.data_version);
  if (version === null) throw new Error("eksporten mangler data_version");
  if (!Array.isArray(data.courses)) throw new Error("eksporten mangler courses");
  const courses: FeedCourse[] = [];
  const seen = new Set<string>();
  const skippedCourses: Skipped[] = [];
  const skippedTees: Skipped[] = [];
  const skippedHoles: Skipped[] = [];
  const teeIDs = new Set<string>();
  for (const raw of data.courses) {
    const mapped = mapCourse(raw);
    skippedTees.push(...mapped.skippedTees);
    skippedHoles.push(...mapped.skippedHoles);
    if (!mapped.course) {
      if (mapped.skippedCourse) skippedCourses.push(mapped.skippedCourse);
      continue;
    }
    if (seen.has(mapped.course.external_id)) {
      skippedCourses.push({ external_id: mapped.course.external_id, reason: "dobbel id" });
      continue;
    }
    seen.add(mapped.course.external_id);
    // En tee-id er unik i hele kilden (course_tees_external_key).
    const tees = mapped.course.tees.filter((t) => {
      if (teeIDs.has(t.external_id)) {
        skippedTees.push({ external_id: t.external_id, reason: "dobbel id på en annen bane" });
        return false;
      }
      teeIDs.add(t.external_id);
      return true;
    });
    // Falt hull-teen bort som dobbel, velges den på nytt blant teene som står.
    courses.push({ ...mapped.course, holes: holeTee(tees)?.holes ?? [], tees });
  }
  return {
    dataVersion: version,
    generatedAt: typeof data.generated_at === "string" ? data.generated_at : null,
    courses,
    skippedCourses,
    skippedTees,
    skippedHoles,
  };
}

// --- Det som ligger i databasen, og hva som er endret --------------------------

export interface ExistingTee {
  external_id: string;
  name: string;
  gender: string;
  course_rating: number | string;
  slope_rating: number;
  par: number | null;
  sort_order: number;
  missing_at: string | null;
  /** Hullene i course_tee_holes (sql/030), sortert på nummer. */
  holes: FeedHole[];
}

export interface ExistingCourse {
  external_id: string;
  name: string;
  city: string | null;
  country: string | null;
  course_rating: number | string | null;
  slope_rating: number | null;
  missing_at: string | null;
  /** Banens hull i course_holes, sortert på nummer. */
  holes: FeedHole[];
  tees: ExistingTee[];
}

/** En hullrad fra databasen (course_holes eller course_tee_holes). */
export interface HoleRow {
  hole_number: number;
  par: number;
  stroke_index: number | null;
  length_m: number | null;
}

function holesFromRows(rows: HoleRow[] | undefined): FeedHole[] {
  return (rows ?? [])
    .map((h): FeedHole => [h.hole_number, h.par, h.stroke_index, h.length_m])
    .sort((a, b) => a[0] - b[0]);
}

function groupBy<T, K>(rows: T[], key: (row: T) => K): Map<K, T[]> {
  const map = new Map<K, T[]>();
  for (const row of rows) {
    const k = key(row);
    const list = map.get(k) ?? [];
    list.push(row);
    map.set(k, list);
  }
  return map;
}

/**
 * Radene fra PostgREST satt sammen per bane: courses, course_tees (med id og course_id) og hullene
 * (course_holes med course_id, course_tee_holes med tee_id). Hullrader til andre baner overses.
 */
export function existingFromRows(
  courses: { id: string; external_id: string; name: string; city: string | null; country: string | null; course_rating: number | string | null; slope_rating: number | null; missing_at: string | null }[],
  tees: (Omit<ExistingTee, "holes"> & { id: string; course_id: string })[],
  courseHoles: (HoleRow & { course_id: string })[] = [],
  teeHoles: (HoleRow & { tee_id: string })[] = [],
): ExistingCourse[] {
  const holesByCourse = groupBy(courseHoles, (h) => h.course_id);
  const holesByTee = groupBy(teeHoles, (h) => h.tee_id);
  const byCourse = new Map<string, ExistingTee[]>();
  for (const { course_id, id, ...tee } of tees) {
    const list = byCourse.get(course_id) ?? [];
    list.push({ ...tee, holes: holesFromRows(holesByTee.get(id)) });
    byCourse.set(course_id, list);
  }
  return courses.map(({ id, ...course }) => ({
    ...course,
    holes: holesFromRows(holesByCourse.get(id)),
    tees: byCourse.get(id) ?? [],
  }));
}

function sameNumber(a: number | string | null | undefined, b: number | string | null | undefined): boolean {
  const x = a === null || a === undefined ? null : Number(a);
  const y = b === null || b === undefined ? null : Number(b);
  return x === y;
}

/** Like hull: samme antall, og samme nummer, par, indeks og lengde på hvert. */
export function sameHoles(a: FeedHole[] | undefined, b: FeedHole[]): boolean {
  const x = a ?? [];
  return x.length === b.length && x.every((h, i) => h.every((v, j) => sameNumber(v, b[i][j])));
}

function sameTee(a: ExistingTee, b: FeedTee): boolean {
  return a.missing_at === null && a.name === b.name && a.gender === b.gender &&
    sameNumber(a.course_rating, b.course_rating) && sameNumber(a.slope_rating, b.slope_rating) &&
    sameNumber(a.par, b.par) && sameNumber(a.sort_order, b.sort_order) && sameHoles(a.holes, b.holes);
}

/** Er banen lik det som ligger i databasen (felt og tees som ikke er borte)? */
export function sameCourse(existing: ExistingCourse, incoming: FeedCourse): boolean {
  if (existing.missing_at !== null) return false;
  if (existing.name !== incoming.name || existing.city !== incoming.city || existing.country !== incoming.country) return false;
  if (!sameNumber(existing.course_rating, incoming.course_rating) || !sameNumber(existing.slope_rating, incoming.slope_rating)) {
    return false;
  }
  if (!sameHoles(existing.holes, incoming.holes)) return false;
  const live = existing.tees.filter((t) => t.missing_at === null);
  if (live.length !== incoming.tees.length) return false;
  const byID = new Map(existing.tees.map((t) => [t.external_id, t]));
  return incoming.tees.every((t) => {
    const old = byID.get(t.external_id);
    return old !== undefined && sameTee(old, t);
  });
}

export interface FeedDiff {
  /** Nye eller endrede baner: sendes til course_feed_apply. */
  changed: FeedCourse[];
  added: number;
  updated: number;
  unchanged: number;
  /** Baner i databasen som ikke står i eksporten (markeres borte, slettes ikke). */
  gone: string[];
  /** Id-ene til alle banene i eksporten. */
  present: string[];
}

export function diffFeed(existing: ExistingCourse[], incoming: FeedCourse[]): FeedDiff {
  const byID = new Map(existing.map((c) => [c.external_id, c]));
  const changed: FeedCourse[] = [];
  let added = 0;
  let updated = 0;
  let unchanged = 0;
  for (const course of incoming) {
    const old = byID.get(course.external_id);
    if (!old) {
      added++;
      changed.push(course);
    } else if (!sameCourse(old, course)) {
      updated++;
      changed.push(course);
    } else {
      unchanged++;
    }
  }
  const present = incoming.map((c) => c.external_id);
  const presentSet = new Set(present);
  const gone = existing.filter((c) => c.missing_at === null && !presentSet.has(c.external_id)).map((c) => c.external_id);
  return { changed, added, updated, unchanged, gone, present };
}

/**
 * Sikring mot en halv eksport: er den tom, eller har den under halvparten av
 * banene vi har fra før (og vi har minst 50), skrives ingenting. Da ville for
 * mange baner blitt markert borte. Gir feilmeldingen, eller null.
 */
export function sanityProblem(existingActive: number, incoming: number): string | null {
  if (incoming === 0) return "eksporten har ingen baner";
  if (existingActive >= 50 && incoming < existingActive / 2) {
    return `eksporten har ${incoming} baner, men vi har ${existingActive}. Hoppet over for sikkerhets skyld`;
  }
  return null;
}

/**
 * Skal eksporten hentes selv om versjonen er lik? Ja når databasen ikke har ett eneste hull per
 * tee: sql/030 er nettopp kjørt, eller en eldre synk (uten hull) har lagret versjonen etter 030.
 * Da hentes alt én gang, og diffen sender banene med hull.
 */
export function needsHoles(teeHoleRows: number): boolean {
  return teeHoleRows === 0;
}

/** Størrelsen på en del slik den sendes (JSON, byte). */
export function partBytes(part: FeedCourse[]): number {
  return new TextEncoder().encode(JSON.stringify(part)).length;
}

/** Delene som sendes til course_feed_apply. Siste del har versjonen (tom liste gir én del). */
export function chunks<T>(items: T[], size = CHUNK_SIZE): T[][] {
  if (size < 1) throw new Error("størrelsen må være minst 1");
  if (items.length === 0) return [[]];
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}
