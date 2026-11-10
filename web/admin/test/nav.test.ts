// Menyen i arrangørsiden (src/nav.ts).
import { test } from "node:test";
import assert from "node:assert/strict";
import { NAV_GROUPS, TAB_INFO, navGroups, tabFromHash } from "../src/nav.ts";

test("alle fanene står i én gruppe, med tittel og forklaring", () => {
  const all = NAV_GROUPS.flatMap((g) => g.tabs);
  assert.equal(new Set(all).size, all.length);
  assert.deepEqual([...all].sort(), Object.keys(TAB_INFO).sort());
  for (const t of all) assert.ok(TAB_INFO[t].title && TAB_INFO[t].lead && TAB_INFO[t].icon);
});

test("bare fanene du har, og tomme grupper faller bort", () => {
  assert.deepEqual(navGroups(["terminliste", "tabeller", "klubb"]), [
    { title: "Spill", tabs: ["terminliste", "tabeller"] },
    { title: "Klubb", tabs: ["klubb"] },
  ]);
});

test("fanen fra adressen, bare når du har den", () => {
  assert.equal(tabFromHash("#terminliste", ["kvelden", "terminliste"]), "terminliste");
  assert.equal(tabFromHash("#roller", ["kvelden"]), null);
  assert.equal(tabFromHash("", ["kvelden"]), null);
  assert.equal(tabFromHash("#tropp/noe", ["tropp"]), "tropp");
});
