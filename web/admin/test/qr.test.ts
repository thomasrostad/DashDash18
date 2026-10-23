// QR-koden til TV-koden og turneringslenken (pakke 2, punkt 5 og 7).
import { test } from "node:test";
import assert from "node:assert/strict";
import { qrMatrix, qrPath } from "../src/qr.ts";

test("lenken blir en kvadratisk QR-kode med finnermønster i hjørnene", () => {
  const m = qrMatrix("https://dashdash18.com/tv/ABCDEFGHJK");
  const n = m.length;
  assert.ok(n >= 21 && (n - 17) % 4 === 0, `ugyldig størrelse ${n}`);
  assert.ok(m.every((row) => row.length === n));
  // Finnermønsteret: 7 × 7 med mørk ramme, lys ring og mørk kjerne, øverst til venstre, øverst til høyre og nederst til venstre.
  for (const [r0, c0] of [[0, 0], [0, n - 7], [n - 7, 0]]) {
    for (let i = 0; i < 7; i++) {
      assert.ok(m[r0][c0 + i] && m[r0 + 6][c0 + i] && m[r0 + i][c0] && m[r0 + i][c0 + 6]);
    }
    assert.equal(m[r0 + 1][c0 + 1], false);
    assert.ok(m[r0 + 3][c0 + 3]);
  }
});

test("samme lenke gir samme kode, og stien har én bit per mørk prikk", () => {
  const a = qrMatrix("https://dashdash18.com/konkurranse/ABCDEFGHJK");
  assert.deepEqual(a, qrMatrix("https://dashdash18.com/konkurranse/ABCDEFGHJK"));
  const dark = a.flat().filter(Boolean).length;
  assert.equal(qrPath(a).split("M").length - 1, dark);
  assert.equal(qrPath([[true, false], [false, true]]), "M0 0h1v1h-1zM1 1h1v1h-1z");
});
