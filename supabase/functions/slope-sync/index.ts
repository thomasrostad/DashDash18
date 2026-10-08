// slope-sync: henter baner og tees fra slope.no inn i det felles banebiblioteket (fase 20).
// FORSLAG. Ikke deployet. Krever sql/029_slope_baner.sql.
//
// Kilden er åpen (eieren: «bare bruk det … Kreditering og lenke til slope.no i appen er alt
// jeg ber om»). Vi er snille mot API-et: én meta-sjekk per kjøring, eksporten (~4 MB) bare når
// data_version er ny, og User-Agent «Atten (dashdash18.com)».
//
// Flyt per kjøring:
//   1. GET …/meta. Feiler den: course_feed_note(feil) og 502.
//   2. Les lagret data_version (course_feeds). Lik: course_feed_note() og ferdig.
//   3. GET …/export, vask den (logic.ts: mapExport), les det vi har (courses og course_tees med
//      source = slope), finn nye og endrede baner (diffFeed) og sjekk at eksporten er hel.
//   4. course_feed_apply i deler på 200 baner. Siste del har versjonen: den markerer baner som
//      er borte fra kilden (slettes aldri) og skriver statusen. Feiler noe underveis, er
//      versjonen ikke lagret, og neste kjøring prøver på nytt.
// Funksjonen rører aldri course_holes, course_corrections (brukernes rettelser), baner uten
// kilde eller klubbenes baner.
//
// Kalles av pg_cron én gang i døgnet (se «Etter migreringen» i sql/029_slope_baner.sql).
// Secrets (Supabase → Edge Functions → Secrets), aldri i repoet:
//   SLOPE_SYNC_SECRET   delt hemmelighet; cron sender den som x-sync-secret (fra Vault)
// Satt av Supabase selv: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
//
// Deploy (når godkjent): supabase functions deploy slope-sync --no-verify-jwt
// (cron sender ingen innlogging; hemmeligheten er nøkkelen).

import {
  chunks,
  diffFeed,
  type ExistingTee,
  existingFromRows,
  mapExport,
  needsExport,
  sanityProblem,
  type SlopeExport,
  type SlopeMeta,
  SOURCE,
} from "./logic.ts";

const META_URL = "https://slope.no/wp-json/golfhs/v1/meta";
const EXPORT_URL = "https://slope.no/wp-json/golfhs/v1/export";
const USER_AGENT = "Atten (dashdash18.com)";
const PAGE = 1000;

const REQUIRED = ["SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY", "SLOPE_SYNC_SECRET"] as const;

const JSON_HEADERS = { "content-type": "application/json; charset=utf-8" };

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

/** Sammenlikner uten å lekke lengden av felles prefiks via tid. */
function safeEqual(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

async function fetchJSON<T>(url: string): Promise<T> {
  const response = await fetch(url, { headers: { "user-agent": USER_AGENT, accept: "application/json" } });
  if (!response.ok) throw new Error(`${url}: ${response.status}`);
  return await response.json() as T;
}

/** RPC og lesing mot PostgREST med service_role. Bare på serveren. */
class Db {
  constructor(private readonly url: string, private readonly key: string) {}

  private headers(extra: Record<string, string> = {}): Record<string, string> {
    return { apikey: this.key, authorization: `Bearer ${this.key}`, ...extra };
  }

  async rpc<T>(name: string, params: Record<string, unknown>): Promise<T> {
    const response = await fetch(`${this.url}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: this.headers({ "content-type": "application/json" }),
      body: JSON.stringify(params),
    });
    const text = await response.text();
    if (!response.ok) throw new Error(`${name}: ${response.status} ${text.slice(0, 200)}`);
    return (text ? JSON.parse(text) : null) as T;
  }

  /** Alle radene, side for side (PostgREST gir høyst 1000 om gangen). */
  async selectAll<T>(table: string, query: string, order: string): Promise<T[]> {
    const rows: T[] = [];
    for (let offset = 0; ; offset += PAGE) {
      const response = await fetch(`${this.url}/rest/v1/${table}?${query}&order=${order}&limit=${PAGE}&offset=${offset}`, {
        headers: this.headers(),
      });
      const text = await response.text();
      if (!response.ok) throw new Error(`${table}: ${response.status} ${text.slice(0, 200)}`);
      const page = (text ? JSON.parse(text) : []) as T[];
      rows.push(...page);
      if (page.length < PAGE) return rows;
    }
  }
}

interface CourseRow {
  id: string;
  external_id: string;
  name: string;
  city: string | null;
  country: string | null;
  course_rating: number | string | null;
  slope_rating: number | null;
  missing_at: string | null;
}

async function sync(db: Db): Promise<Record<string, unknown>> {
  const meta = await fetchJSON<SlopeMeta>(META_URL);
  const feeds = await db.selectAll<{ data_version: string | null }>(
    "course_feeds",
    `select=data_version&source=eq.${SOURCE}`,
    "source",
  );
  const stored = feeds[0]?.data_version ?? null;
  if (!needsExport(meta, stored)) {
    await db.rpc("course_feed_note", { p_source: SOURCE });
    return { unchanged: true, data_version: stored };
  }

  const mapped = mapExport(await fetchJSON<SlopeExport>(EXPORT_URL));
  const courses = await db.selectAll<CourseRow>(
    "courses",
    `select=id,external_id,name,city,country,course_rating,slope_rating,missing_at&source=eq.${SOURCE}`,
    "external_id",
  );
  const tees = await db.selectAll<ExistingTee & { course_id: string }>(
    "course_tees",
    `select=course_id,external_id,name,gender,course_rating,slope_rating,par,sort_order,missing_at&source=eq.${SOURCE}`,
    "external_id",
  );
  const existing = existingFromRows(courses, tees);
  const problem = sanityProblem(existing.filter((c) => c.missing_at === null).length, mapped.courses.length);
  if (problem) throw new Error(problem);

  const diff = diffFeed(existing, mapped.courses);
  const parts = chunks(diff.changed);
  let result: unknown = null;
  for (const [i, part] of parts.entries()) {
    const last = i === parts.length - 1;
    result = await db.rpc("course_feed_apply", {
      p_source: SOURCE,
      p_data_version: last ? mapped.dataVersion : null,
      p_generated_at: last ? mapped.generatedAt : null,
      p_courses: part,
      p_present: last ? diff.present : null,
    });
  }
  return {
    data_version: mapped.dataVersion,
    previous: stored,
    added: diff.added,
    updated: diff.updated,
    unchanged: diff.unchanged,
    gone: diff.gone.length,
    skipped_courses: mapped.skippedCourses,
    skipped_tees: mapped.skippedTees,
    result,
  };
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "POST forventet" }, 405);

  const env = Object.fromEntries(REQUIRED.map((k) => [k, Deno.env.get(k) ?? ""])) as Record<
    typeof REQUIRED[number],
    string
  >;
  const missing = REQUIRED.filter((k) => !env[k]);
  if (missing.length) return json({ error: `Mangler konfigurasjon: ${missing.join(", ")}` }, 500);

  if (!safeEqual(request.headers.get("x-sync-secret") ?? "", env.SLOPE_SYNC_SECRET)) {
    return json({ error: "Ikke autorisert" }, 401);
  }
  await request.body?.cancel();

  const db = new Db(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY);
  try {
    return json(await sync(db));
  } catch (error) {
    const message = String((error as Error)?.message ?? error).slice(0, 500);
    try {
      await db.rpc("course_feed_note", { p_source: SOURCE, p_error: message });
    } catch {
      // Statusen er bare til hjelp. Feilen står i svaret og i loggen.
    }
    return json({ error: message }, 502);
  }
});
