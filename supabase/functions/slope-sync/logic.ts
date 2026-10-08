// Ren logikk for slope-sync: tolke slope.no, vaske dataene, finne hva som er
// nytt eller endret. Ingen nettverk, ingen database (testes i logic_test.ts).
//
// Kilden: https://slope.no/wp-json/golfhs/v1/meta og …/export (åpent API,
// eieren ber bare om kreditering og lenke til slope.no i appen).

/** Kildenavnet i courses.source og course_tees.source. */
export const SOURCE = "slope";

/** Hvor mange baner som sendes til course_feed_apply i én del. */
export const CHUNK_SIZE = 200;

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

// --- Det databasen får (course_feed_apply, sql/029) --------------------------

export interface FeedTee {
  external_id: string;
  name: string;
  gender: "men" | "women";
  course_rating: number;
  slope_rating: number;
  par: number | null;
  sort_order: number;
}

export interface FeedCourse {
  external_id: string;
  name: string;
  city: string | null;
  country: string | null;
  /** Fra standard-teen (første herre-tee), eller null. */
  course_rating: number | null;
  slope_rating: number | null;
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

/** Én tee, eller grunnen til at den hoppes over. */
export function mapTee(tee: SlopeTee): FeedTee | Skipped {
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
  const par = toNumber(tee.par);
  const sort = toNumber(tee.sort_order);
  return {
    external_id: id,
    name,
    gender,
    course_rating: Math.round(rating * 10) / 10,
    slope_rating: slope,
    par: par !== null && Number.isInteger(par) && par >= PAR_MIN && par <= PAR_MAX ? par : null,
    sort_order: sort !== null && Number.isInteger(sort) ? Math.min(Math.max(sort, 0), SORT_MAX) : 0,
  };
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

/** Én bane med teene sine, eller grunnen til at den hoppes over. */
export function mapCourse(course: SlopeCourse): { course: FeedCourse | null; skippedCourse?: Skipped; skippedTees: Skipped[] } {
  const id = idText(course?.id);
  if (id === null) return { course: null, skippedCourse: { external_id: String(course?.id ?? ""), reason: "mangler id" }, skippedTees: [] };
  const name = cleanText(course.name, COURSE_NAME_MAX);
  if (name === null) return { course: null, skippedCourse: { external_id: id, reason: "mangler navn" }, skippedTees: [] };

  const skippedTees: Skipped[] = [];
  const byId = new Map<string, FeedTee>();
  for (const raw of Array.isArray(course.tees) ? course.tees : []) {
    const tee = mapTee(raw);
    if (isSkipped(tee)) skippedTees.push(tee);
    else if (byId.has(tee.external_id)) skippedTees.push({ external_id: tee.external_id, reason: "dobbel id" });
    else byId.set(tee.external_id, tee);
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
      tees,
    },
    skippedTees,
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
  const teeIDs = new Set<string>();
  for (const raw of data.courses) {
    const mapped = mapCourse(raw);
    skippedTees.push(...mapped.skippedTees);
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
    courses.push({ ...mapped.course, tees });
  }
  return {
    dataVersion: version,
    generatedAt: typeof data.generated_at === "string" ? data.generated_at : null,
    courses,
    skippedCourses,
    skippedTees,
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
}

export interface ExistingCourse {
  external_id: string;
  name: string;
  city: string | null;
  country: string | null;
  course_rating: number | string | null;
  slope_rating: number | null;
  missing_at: string | null;
  tees: ExistingTee[];
}

/** Radene fra PostgREST (courses og course_tees med course_id), satt sammen. */
export function existingFromRows(
  courses: { id: string; external_id: string; name: string; city: string | null; country: string | null; course_rating: number | string | null; slope_rating: number | null; missing_at: string | null }[],
  tees: (Omit<ExistingTee, never> & { course_id: string })[],
): ExistingCourse[] {
  const byCourse = new Map<string, ExistingTee[]>();
  for (const { course_id, ...tee } of tees) {
    const list = byCourse.get(course_id) ?? [];
    list.push(tee);
    byCourse.set(course_id, list);
  }
  return courses.map(({ id, ...course }) => ({ ...course, tees: byCourse.get(id) ?? [] }));
}

function sameNumber(a: number | string | null | undefined, b: number | string | null | undefined): boolean {
  const x = a === null || a === undefined ? null : Number(a);
  const y = b === null || b === undefined ? null : Number(b);
  return x === y;
}

function sameTee(a: ExistingTee, b: FeedTee): boolean {
  return a.missing_at === null && a.name === b.name && a.gender === b.gender &&
    sameNumber(a.course_rating, b.course_rating) && sameNumber(a.slope_rating, b.slope_rating) &&
    sameNumber(a.par, b.par) && sameNumber(a.sort_order, b.sort_order);
}

/** Er banen lik det som ligger i databasen (felt og tees som ikke er borte)? */
export function sameCourse(existing: ExistingCourse, incoming: FeedCourse): boolean {
  if (existing.missing_at !== null) return false;
  if (existing.name !== incoming.name || existing.city !== incoming.city || existing.country !== incoming.country) return false;
  if (!sameNumber(existing.course_rating, incoming.course_rating) || !sameNumber(existing.slope_rating, incoming.slope_rating)) {
    return false;
  }
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

/** Delene som sendes til course_feed_apply. Siste del har versjonen (tom liste gir én del). */
export function chunks<T>(items: T[], size = CHUNK_SIZE): T[][] {
  if (size < 1) throw new Error("størrelsen må være minst 1");
  if (items.length === 0) return [[]];
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}
