// Tester for slope-sync. Kjøres med
//   deno test supabase/functions/slope-sync/
// Ingen nettverk, ingen database. Utdragene i fixtures/ er ekte baner fra slope.no-eksporten
// 08.10.2026 (data_version 5021), uten greenfee og beskrivelse: export_utdrag.json (fem baner,
// fase 20) og export_hull.json (fase 20b: Valdres med ulike par per tee, Bollnäs der hullene ikke
// stemmer med teens par, og Bornholm, en 9-hullsbane der to av fire tees har hull).
// Hele eksporten (ikke i git) kan legges i SLOPE_EXPORT for å sjekke størrelsen på delene.

import { deepStrictEqual as eq, ok, strictEqual as is, throws } from "node:assert/strict";
import utdrag from "./fixtures/export_utdrag.json" with { type: "json" };
import hull from "./fixtures/export_hull.json" with { type: "json" };
import {
  CHUNK_SIZE,
  chunks,
  countryCode,
  defaultTee,
  diffFeed,
  type ExistingCourse,
  existingFromRows,
  type FeedCourse,
  type FeedHole,
  holeTee,
  mapCourse,
  mapExport,
  mapHoles,
  mapTee,
  MAX_PART_BYTES,
  needsExport,
  needsHoles,
  partBytes,
  sameHoles,
  sanityProblem,
  type SlopeExport,
  versionText,
} from "./logic.ts";

const EXPORT = utdrag as unknown as SlopeExport;
const HULL = hull as unknown as SlopeExport;

Deno.test("versjonen: tall blir tekst, og eksporten hentes bare ved ny versjon", () => {
  is(versionText(5021), "5021");
  is(versionText(" 5021 "), "5021");
  is(versionText(null), null);
  is(needsExport({ data_version: 5021 }, "5021"), false);
  is(needsExport({ data_version: 5022 }, "5021"), true);
  is(needsExport({ data_version: 5021 }, null), true, "første kjøring henter alt");
  throws(() => needsExport({} as never, "5021"), /data_version/);
});

Deno.test("land blir ISO-kode", () => {
  is(countryCode("Norway"), "NO");
  is(countryCode("Sweden"), "SE");
  is(countryCode("Denmark"), "DK");
  is(countryCode("Finland"), "FI");
  is(countryCode("Iceland"), "IS");
  is(countryCode("Poland"), "PL");
  is(countryCode("no"), "NO");
  is(countryCode("Atlantis"), null);
  is(countryCode(null), null);
});

Deno.test("en tee vaskes: tall, kjønn, rekkefølge", () => {
  eq(mapTee({ id: 10762, name: " Gul-Blå -  Hvit ", gender: "men", slope_rating: 132, course_rating: 73, par: 72, sort_order: 1 }), {
    external_id: "10762",
    name: "Gul-Blå - Hvit",
    gender: "men",
    course_rating: 73,
    slope_rating: 132,
    par: 72,
    sort_order: 1,
    holes: [],
  });
  eq(mapTee({ id: "5", name: "Rød", gender: "Women", slope_rating: "120", course_rating: "66,35", par: null, sort_order: null }), {
    external_id: "5",
    name: "Rød",
    gender: "women",
    course_rating: 66.4,
    slope_rating: 120,
    par: null,
    sort_order: 0,
    holes: [],
  });
});

Deno.test("tees utenfor databasens grenser hoppes over med grunn", () => {
  ok("reason" in mapTee({ id: 1, name: "Svart", gender: "men", slope_rating: 161, course_rating: 83.4, par: 72 }));
  ok("reason" in mapTee({ id: 2, name: "X", gender: "men", slope_rating: 120, course_rating: 95, par: 72 }));
  ok("reason" in mapTee({ id: 3, name: "X", gender: "junior", slope_rating: 120, course_rating: 70, par: 72 }));
  ok("reason" in mapTee({ id: 4, name: "  ", gender: "men", slope_rating: 120, course_rating: 70, par: 72 }));
  ok("reason" in mapTee({ id: 5, name: "X", gender: "men", slope_rating: 120.5, course_rating: 70, par: 72 }));
  // Par utenfor 27–80 gjør ikke teen ugyldig, bare paret tomt.
  const tee = mapTee({ id: 6, name: "Kort", gender: "men", slope_rating: 90, course_rating: 25.3, par: 20 });
  ok(!("reason" in tee));
  is((tee as { par: number | null }).par, null);
});

Deno.test("standard-teen er første herre-tee etter rekkefølgen, ellers første tee", () => {
  const { course } = mapCourse({
    id: 1,
    name: "Bane",
    tees: [
      { id: 3, name: "Rød", gender: "women", slope_rating: 120, course_rating: 70, par: 72, sort_order: 1 },
      { id: 2, name: "Gul", gender: "men", slope_rating: 130, course_rating: 71, par: 72, sort_order: 3 },
      { id: 1, name: "Hvit", gender: "men", slope_rating: 135, course_rating: 73, par: 72, sort_order: 2 },
    ],
  });
  is(course?.tees.map((t) => t.name).join(","), "Rød,Hvit,Gul");
  is(defaultTee(course!.tees)?.name, "Hvit");
  is(course?.course_rating, 73);
  is(course?.slope_rating, 135);
  const { course: women } = mapCourse({
    id: 2,
    name: "Damebane",
    tees: [{ id: 9, name: "Rød", gender: "women", slope_rating: 120, course_rating: 70, par: 72, sort_order: 1 }],
  });
  is(women?.course_rating, 70);
  const { course: none } = mapCourse({ id: 3, name: "Korthullsbane", tees: [] });
  is(none?.course_rating, null);
  eq(none?.tees, []);
});

Deno.test("utdraget fra slope.no: fem baner, den ugyldige teen på Miklagard hoppes over", () => {
  const mapped = mapExport(EXPORT);
  is(mapped.dataVersion, "5021");
  is(mapped.generatedAt, "2026-10-08T17:02:12Z");
  is(mapped.courses.length, 5);
  eq(mapped.skippedCourses, []);
  const a6 = mapped.courses.find((c) => c.external_id === "77")!;
  is(a6.name, "A6 Golfklubb");
  is(a6.city, "Jönköping");
  is(a6.country, "SE");
  is(a6.tees.length, 24);
  is(a6.course_rating, 73, "Gul-Blå - Hvit, herre, sort_order 1");
  is(a6.slope_rating, 132);
  const miklagard = mapped.courses.find((c) => c.external_id === "8")!;
  is(miklagard.country, "NO");
  is(miklagard.tees.length, 9, "én av ti har slope 157");
  eq(mapped.skippedTees.map((s) => s.reason), ["slope 157"]);
  const kort = mapped.courses.find((c) => c.external_id === "1140")!;
  eq(kort.tees, []);
  is(mapped.courses.filter((c) => c.country === "NO").length, 3);
});

Deno.test("doble id-er i eksporten: den første vinner", () => {
  const mapped = mapExport({
    data_version: 1,
    courses: [
      { id: 1, name: "En", tees: [{ id: 10, name: "Gul", gender: "men", slope_rating: 120, course_rating: 70 }] },
      { id: 1, name: "En igjen", tees: [] },
      { id: 2, name: "To", tees: [{ id: 10, name: "Gul", gender: "men", slope_rating: 120, course_rating: 70 }] },
    ],
  });
  eq(mapped.courses.map((c) => c.name), ["En", "To"]);
  eq(mapped.courses[1].tees, []);
  eq(mapped.skippedCourses, [{ external_id: "1", reason: "dobbel id" }]);
  eq(mapped.skippedTees, [{ external_id: "10", reason: "dobbel id på en annen bane" }]);
  throws(() => mapExport({ courses: [] } as never), /data_version/);
});

function asExisting(course: FeedCourse, extra: Partial<ExistingCourse> = {}): ExistingCourse {
  return {
    external_id: course.external_id,
    name: course.name,
    city: course.city,
    country: course.country,
    // PostgREST gir numeric som tall; tekst tåles også.
    course_rating: course.course_rating === null ? null : String(course.course_rating),
    slope_rating: course.slope_rating,
    missing_at: null,
    holes: course.holes,
    tees: course.tees.map((t) => ({ ...t, missing_at: null })),
    ...extra,
  };
}

Deno.test("diff: uendret, endret, ny, borte og tilbake", () => {
  const mapped = mapExport(EXPORT).courses;
  const [a6, aas, alesund, kort, miklagard] = mapped;
  const existing = [
    asExisting(a6),
    asExisting(aas, { name: "Aas Gaard" }), // navnet er endret hos kilden
    asExisting(kort, { missing_at: "2026-10-01T00:00:00Z" }), // var borte, er tilbake
    asExisting(miklagard),
    { ...asExisting(alesund), external_id: "999", name: "Nedlagt" }, // finnes ikke lenger
  ];
  // Re-rating av én tee på Miklagard.
  existing[3].tees[0] = { ...existing[3].tees[0], course_rating: 70.1 };
  const diff = diffFeed(existing, mapped);
  is(diff.unchanged, 1);
  is(diff.updated, 3);
  is(diff.added, 1);
  eq(diff.changed.map((c) => c.external_id).sort(), ["1140", "163", "8", "94"]);
  eq(diff.gone, ["999"]);
  eq(diff.present, ["77", "94", "163", "1140", "8"]);
});

Deno.test("diff: en tee som er borte i databasen, eller en ny tee, gjør banen endret", () => {
  const [a6] = mapExport(EXPORT).courses;
  const gone = asExisting(a6);
  gone.tees[2] = { ...gone.tees[2], missing_at: "2026-10-01T00:00:00Z" };
  is(diffFeed([gone], [a6]).updated, 1);
  const fewer = asExisting(a6);
  fewer.tees.pop();
  is(diffFeed([fewer], [a6]).updated, 1);
  const extraTee = asExisting(a6);
  extraTee.tees.push({ ...extraTee.tees[0], external_id: "x" });
  is(diffFeed([extraTee], [a6]).updated, 1);
});

Deno.test("radene fra databasen settes sammen per bane", () => {
  const courses = existingFromRows(
    [{ id: "c1", external_id: "77", name: "A6", city: null, country: "SE", course_rating: "73.0", slope_rating: 132, missing_at: null }],
    [{ id: "t1", course_id: "c1", external_id: "10762", name: "Hvit", gender: "men", course_rating: "73.0", slope_rating: 132, par: 72, sort_order: 1, missing_at: null }],
    [
      { course_id: "c1", hole_number: 2, par: 3, stroke_index: 17, length_m: 126 },
      { course_id: "c1", hole_number: 1, par: 5, stroke_index: 11, length_m: 457 },
      { course_id: "klubbens", hole_number: 1, par: 4, stroke_index: null, length_m: null },
    ],
    [{ tee_id: "t1", hole_number: 1, par: 5, stroke_index: 11, length_m: null }],
  );
  is(courses.length, 1);
  is(courses[0].tees.length, 1);
  ok(!("id" in courses[0]));
  ok(!("course_id" in courses[0].tees[0]));
  ok(!("id" in courses[0].tees[0]));
  eq(courses[0].holes, [[1, 5, 11, 457], [2, 3, 17, 126]], "sortert på nummer, andre baners hull overses");
  eq(courses[0].tees[0].holes, [[1, 5, 11, null]]);
});

// --- Hull per tee (fase 20b, sql/030) ------------------------------------------

const LOSBY_64: FeedHole[] = [
  [1, 5, 3, 478], [2, 5, 7, 483], [3, 3, 17, 110], [4, 4, 9, 378], [5, 4, 1, 403], [6, 3, 11, 175],
  [7, 4, 13, 390], [8, 3, 15, 162], [9, 5, 5, 510], [10, 5, 4, 478], [11, 5, 8, 483], [12, 3, 18, 110],
  [13, 4, 10, 378], [14, 4, 2, 403], [15, 3, 12, 175], [16, 4, 14, 390], [17, 3, 16, 162], [18, 5, 6, 510],
];

Deno.test("hullene vaskes: 18 hull fra Losby Østmork (tee 64) står som de er", () => {
  eq(mapHoles(LOSBY_64, 72), LOSBY_64);
  eq(mapHoles([...LOSBY_64].reverse(), 72), LOSBY_64, "sortert på hullnummer");
  eq(mapHoles(undefined, 72), [], "ingen hull hos kilden");
  eq(mapHoles([], 72), []);
  eq(mapHoles(LOSBY_64, null), LOSBY_64, "uten teens par sjekkes ikke summen");
});

Deno.test("ugyldige hull gir grunnen, ikke hull", () => {
  const med = (i: number, hole: unknown[]) => LOSBY_64.map((h, n) => (n === i ? hole : h));
  ok("reason" in mapHoles(LOSBY_64.slice(0, 17), 72), "17 hull");
  ok("reason" in mapHoles(med(3, [4, 7, 9, 378]), 72), "par 7");
  ok("reason" in mapHoles(med(3, [4, 2, 9, 378]), 72), "par 2");
  ok("reason" in mapHoles(med(3, [4, 4, 19, 378]), 72), "indeks 19");
  ok("reason" in mapHoles(med(3, [4, 4, 1, 378]), 72), "indeks 1 to ganger");
  ok("reason" in mapHoles(med(3, [19, 4, 9, 378]), 72), "hull 19");
  ok("reason" in mapHoles(med(3, [3, 4, 9, 378]), 72), "hull 3 to ganger");
  ok("reason" in mapHoles(med(3, [4, 4, null, 378]), 72), "indeks mangler på ett hull");
  ok("reason" in mapHoles(med(3, "4,4,9"), 72), "feil form");
  ok("reason" in mapHoles("hull", 72));
  const sum = mapHoles(LOSBY_64, 71);
  ok("reason" in sum);
  is((sum as { reason: string }).reason, "par per hull (72) stemmer ikke med teens par (71)");
});

Deno.test("lengde utenfor 50–700 m blir tom, hullet står; indeks kan mangle på alle", () => {
  const holes = mapHoles(LOSBY_64.map(([n, p, i, m]) => [n, p, i, n === 3 ? 45 : n === 4 ? null : n === 5 ? 701 : m]), 72);
  ok(Array.isArray(holes));
  eq((holes as FeedHole[]).slice(2, 5), [[3, 3, 17, null], [4, 4, 9, null], [5, 4, 1, null]]);
  const noIndex = mapHoles(LOSBY_64.map(([n, p, , m]) => [n, p, null, m]), 72) as FeedHole[];
  is(noIndex.length, 18);
  ok(noIndex.every((h) => h[2] === null));
});

Deno.test("Valdres: hver tee har sine hull, og banen får hullene fra første herre-tee", () => {
  const { courses } = mapExport(HULL);
  const valdres = courses.find((c) => c.external_id === "154")!;
  is(valdres.tees.length, 6);
  ok(valdres.tees.every((t) => t.holes.length === 18), "alle seks tees har 18 hull");
  const svart = valdres.tees.find((t) => t.name === "Svart 73" && t.gender === "men")!;
  const gronn = valdres.tees.find((t) => t.name === "Grønn 66" && t.gender === "men")!;
  is(svart.holes.reduce((s, h) => s + h[1], 0), 73);
  is(gronn.holes.reduce((s, h) => s + h[1], 0), 66, "Grønn er en annen bane enn Svart: par 66");
  ok(!sameHoles(svart.holes, gronn.holes));
  is(holeTee(valdres.tees)?.name, defaultTee(valdres.tees)?.name, "første herre-tee har hull");
  eq(valdres.holes, holeTee(valdres.tees)!.holes);
});

Deno.test("Bollnäs: hullene stemmer ikke med teens par, så teene står uten hull", () => {
  const { courses, skippedHoles, skippedTees } = mapExport(HULL);
  const bollnas = courses.find((c) => c.external_id === "261")!;
  is(bollnas.tees.length, 8);
  ok(bollnas.tees.every((t) => t.holes.length === 0), "seks har feil hull, to har ingen hos kilden");
  const ids = new Set(bollnas.tees.map((t) => t.external_id));
  const mine = skippedHoles.filter((s) => ids.has(s.external_id));
  is(mine.length, 6, "seks tees med par 72 og hull som summerer til 71");
  ok(mine.every((s) => s.reason === "par per hull (71) stemmer ikke med teens par (72)"));
  eq(bollnas.holes, [], "uten hull på noen tee får banen ingen hull: kopi og scorekort som før");
  eq(skippedTees, [], "teene selv er gyldige");
});

Deno.test("Bornholm: 9 hull på to av fire tees, banen får hullene fra herre-teen med hull", () => {
  const bornholm = mapExport(HULL).courses.find((c) => c.external_id === "700")!;
  is(bornholm.tees.length, 4);
  eq(bornholm.tees.map((t) => t.holes.length).sort(), [0, 0, 9, 9]);
  is(bornholm.holes.length, 9);
  is(holeTee(bornholm.tees)?.gender, "men");
  is(holeTee(bornholm.tees)?.name, "Gul");
});

Deno.test("standard-tee uten hull: banen tar hullene fra første tee som har dem", () => {
  const { course } = mapCourse({
    id: 1,
    name: "Bane",
    tees: [
      { id: 1, name: "Hvit", gender: "men", slope_rating: 135, course_rating: 73, par: 72, sort_order: 1 },
      { id: 2, name: "Rød", gender: "women", slope_rating: 120, course_rating: 70, par: 72, sort_order: 2, holes: LOSBY_64 },
    ],
  });
  is(course?.course_rating, 73, "CR og slope fra standard-teen som før");
  eq(course?.holes, LOSBY_64);
});

Deno.test("diff: nye eller endrede hull gjør banen endret, like hull gjør det ikke", () => {
  const valdres = mapExport(HULL).courses.find((c) => c.external_id === "154")!;
  is(diffFeed([asExisting(valdres)], [valdres]).unchanged, 1);
  // Første synk etter 030: ingenting i databasen har hull.
  const before = asExisting(valdres, { holes: [] });
  before.tees = before.tees.map((t) => ({ ...t, holes: [] }));
  is(diffFeed([before], [valdres]).updated, 1);
  // Ny indeks på ett hull på én tee.
  const reindexed = asExisting(valdres);
  reindexed.tees[2] = { ...reindexed.tees[2], holes: reindexed.tees[2].holes.map((h) => (h[0] === 1 ? [1, h[1], 99, h[3]] : h)) };
  is(diffFeed([reindexed], [valdres]).updated, 1);
  // Ny lengde på banens hull.
  const longer = asExisting(valdres, { holes: valdres.holes.map(([n, p, i, m]) => [n, p, i, (m ?? 0) + 1]) });
  is(diffFeed([longer], [valdres]).updated, 1);
  // PostgREST gir tall; samme verdier som tekst regnes like.
  ok(sameHoles([[1, "5", 3, null] as unknown as FeedHole], [[1, 5, 3, null]]));
});

Deno.test("hullene hentes én gang selv om versjonen er lik, når databasen ikke har noen", () => {
  is(needsHoles(0), true);
  is(needsHoles(1), false);
});

Deno.test("delene holder seg under grensen med hull", () => {
  const all = [...mapExport(EXPORT).courses, ...mapExport(HULL).courses];
  for (const part of chunks(all)) ok(partBytes(part) < MAX_PART_BYTES);
  is(CHUNK_SIZE, 100);
});

Deno.test("hele eksporten (SLOPE_EXPORT, hvis satt): delene, hullene og det som hoppes over", () => {
  const path = Deno.env.get("SLOPE_EXPORT");
  if (!path) return;
  const mapped = mapExport(JSON.parse(Deno.readTextFileSync(path)) as SlopeExport);
  const sizes = chunks(mapped.courses).map(partBytes);
  const teesWithHoles = mapped.courses.reduce((n, c) => n + c.tees.filter((t) => t.holes.length > 0).length, 0);
  const coursesWithHoles = mapped.courses.filter((c) => c.holes.length > 0).length;
  console.log(JSON.stringify({
    courses: mapped.courses.length,
    coursesWithHoles,
    teesWithHoles,
    skippedHoles: mapped.skippedHoles.length,
    parts: sizes.length,
    largestPart: Math.max(...sizes),
    totalBytes: sizes.reduce((a, b) => a + b, 0),
  }));
  ok(Math.max(...sizes) < MAX_PART_BYTES);
});

Deno.test("sikring mot en halv eksport", () => {
  is(sanityProblem(0, 1306), null, "første kjøring");
  is(sanityProblem(1306, 1300), null);
  ok(sanityProblem(1306, 0));
  ok(sanityProblem(1306, 600));
  is(sanityProblem(40, 10), null, "under 50 baner stoler vi på kilden");
});

Deno.test("delene: siste del har resten, og tom liste gir én tom del", () => {
  eq(chunks([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]]);
  eq(chunks([], 2), [[]]);
  throws(() => chunks([1], 0));
});
