// Tester for delete-account. Kjøres med
//   deno test supabase/functions/delete-account/
// Ingen nettverk, ingen database.

import { deepStrictEqual as eq, strictEqual as is } from "node:assert/strict";
import { bearerToken, failure, isConfirmed, removalBatches, statusFor } from "./logic.ts";

Deno.test("bekreftelsen må være ordet SLETT", () => {
  is(isConfirmed({ confirm: "SLETT" }), true);
  is(isConfirmed({ confirm: " slett " }), true);
  is(isConfirmed({ confirm: "slette" }), false);
  is(isConfirmed({}), false);
  is(isConfirmed(null), false);
  is(isConfirmed("SLETT"), false);
});

Deno.test("bearer-token leses fra headeren", () => {
  is(bearerToken("Bearer abc.def.ghi"), "abc.def.ghi");
  is(bearerToken("bearer   xyz"), "xyz");
  is(bearerToken("Basic abc"), null);
  is(bearerToken(null), null);
});

Deno.test("filene grupperes per bøtte, uten duplikater og fremmede bøtter", () => {
  const batches = removalBatches([
    { bucket_id: "thread", name: "m1/a.jpg" },
    { bucket_id: "avatars", name: "m1/p.jpg" },
    { bucket_id: "avatars", name: "m1/p.jpg" },
    { bucket_id: "course-images", name: "x.jpg" },
    { bucket_id: "avatars", name: "../hemmelig" },
  ]);
  eq(batches, [
    { bucket: "avatars", paths: ["m1/p.jpg"] },
    { bucket: "thread", paths: ["m1/a.jpg"] },
  ]);
});

Deno.test("mange filer deles i flere kall", () => {
  const objects = Array.from({ length: 5 }, (_, i) => ({ bucket_id: "thread", name: `m/${i}.jpg` }));
  eq(removalBatches(objects, 2).map((b) => b.paths.length), [2, 2, 1]);
});

Deno.test("en feil sier hvilket steg som stoppet", () => {
  const result = failure("anonymize", new Error("500 noe"), 3);
  eq(result, { ok: false, removedFiles: 3, failedAt: "anonymize", error: "500 noe" });
  is(statusFor(result), 502);
  is(statusFor({ ok: true, removedFiles: 0 }), 200);
});
