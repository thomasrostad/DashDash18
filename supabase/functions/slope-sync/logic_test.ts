// Tester for slope-sync. Kjøres med
//   deno test supabase/functions/slope-sync/
// Ingen nettverk, ingen database. Utdraget i fixtures/ er fem ekte baner fra
// slope.no-eksporten 08.10.2026 (data_version 5021), uten greenfee og beskrivelse.

import { deepStrictEqual as eq, ok, strictEqual as is, throws } from "node:assert/strict";
import utdrag from "./fixtures/export_utdrag.json" with { type: "json" };
import {
  chunks,
  countryCode,
  defaultTee,
  diffFeed,
  type ExistingCourse,
  existingFromRows,
  type FeedCourse,
  mapCourse,
  mapExport,
  mapTee,
  needsExport,
  sanityProblem,
  type SlopeExport,
  versionText,
} from "./logic.ts";

const EXPORT = utdrag as unknown as SlopeExport;

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
  });
  eq(mapTee({ id: "5", name: "Rød", gender: "Women", slope_rating: "120", course_rating: "66,35", par: null, sort_order: null }), {
    external_id: "5",
    name: "Rød",
    gender: "women",
    course_rating: 66.4,
    slope_rating: 120,
    par: null,
    sort_order: 0,
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
    [{ course_id: "c1", external_id: "10762", name: "Hvit", gender: "men", course_rating: "73.0", slope_rating: 132, par: 72, sort_order: 1, missing_at: null }],
  );
  is(courses.length, 1);
  is(courses[0].tees.length, 1);
  ok(!("id" in courses[0]));
  ok(!("course_id" in courses[0].tees[0]));
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
