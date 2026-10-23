// TV-kode og «Del tavla» (pakke 2, punkt 7). Samme lenker og tekster som TVCode.swift og TavlaShare.swift
// (DashDash18Tests/TVCodeTests.swift, TavlaShareTests.swift).
import { test } from "node:test";
import assert from "node:assert/strict";
import { SHARE_TEXT, TV_TEXT, displayURL, sharingErrorText, spacedCode, tavlaMessage, tavlaURL, tvURL } from "../src/sharing.ts";

test("lenkene", () => {
  assert.equal(tvURL("ABCDEFGHJK"), "https://dashdash18.com/tv/ABCDEFGHJK");
  assert.equal(tavlaURL("ABCDEFGHJK"), "https://dashdash18.com/tavla/ABCDEFGHJK");
  assert.equal(displayURL(tavlaURL("ABCDEFGHJK")), "dashdash18.com/tavla/ABCDEFGHJK");
});

test("koden i to grupper på fem, ellers som den er", () => {
  assert.equal(spacedCode("ABCDEFGHJK"), "ABCDE FGHJK");
  assert.equal(spacedCode("ABC"), "ABC");
});

test("tekstene som i appen", () => {
  assert.equal(tavlaMessage("Høstmorro"), "Følg Høstmorro live – tabellen og scorekortene, uten app:");
  assert.match(TV_TEXT.footer("Høstmorro"), /^Skjermen viser tabellen og siste runde for Høstmorro,/);
  assert.equal(TV_TEXT.howTo, "Åpn dashdash18.com/tv på skjermen og skriv koden, eller skann QR-koden.");
  assert.equal(SHARE_TEXT.toggleFooter, "Slår du av, slutter lenken å virke med en gang. TV-koden påvirkes ikke.");
});

test("feilene", () => {
  assert.equal(sharingErrorText({ code: "42501", message: "Bare arrangøren kan lage TV-kode" }), "Bare arrangøren kan lage TV-kode");
  assert.equal(sharingErrorText({ code: "PGRST202", message: "Could not find the function" }), "Dette kan ikke brukes før databasen er oppdatert.");
});
