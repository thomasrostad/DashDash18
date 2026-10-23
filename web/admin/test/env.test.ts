// Miljøet for bygget (pakke 1). Samme regler som AppConfig i appen (DashDash18Tests/AppConfigTests.swift).
import { test } from "node:test";
import assert from "node:assert/strict";
import { betsVisible, envFromMode, isSecretKey, projectRef, readConfig } from "../src/env.ts";

const TEST_URL = "https://tsekialrxuhrugscosgi.supabase.co";
const PROD_URL = "https://wxabhadvuzyrmndxpuza.supabase.co";
const KEY = "sb_publishable_abc123";

function jwt(role: string): string {
  const b64 = (o: object) => btoa(JSON.stringify(o)).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
  return `${b64({ alg: "HS256", typ: "JWT" })}.${b64({ iss: "supabase", role })}.sig`;
}

test("bare test og prod er miljøer", () => {
  assert.equal(envFromMode("test"), "test");
  assert.equal(envFromMode("prod"), "prod");
  assert.equal(envFromMode("production"), null);
  assert.equal(envFromMode("development"), null);
  const r = readConfig("production", { VITE_SUPABASE_URL: PROD_URL, VITE_SUPABASE_KEY: KEY });
  assert.ok("error" in r && /--mode test eller --mode prod/.test(r.error));
});

test("manglende verdier stopper bygget (slik live-siden ble bygget uten dem)", () => {
  const r = readConfig("prod", {});
  assert.ok("error" in r && /Mangler VITE_SUPABASE_URL/.test(r.error) && r.error.includes("env/prod/.env"));
  const r2 = readConfig("test", { VITE_SUPABASE_URL: "http://localhost", VITE_SUPABASE_KEY: KEY });
  assert.ok("error" in r2 && /https/.test(r2.error));
});

test("prod-adressen bare i prod, og test-adressen ikke i prod", () => {
  assert.equal(projectRef(PROD_URL), "wxabhadvuzyrmndxpuza");
  const prod = readConfig("prod", { VITE_SUPABASE_URL: PROD_URL, VITE_SUPABASE_KEY: KEY });
  assert.deepEqual(prod, { env: "prod", url: PROD_URL, key: KEY, turnstileSiteKey: null });
  const test1 = readConfig("test", { VITE_SUPABASE_URL: TEST_URL, VITE_SUPABASE_KEY: KEY });
  assert.ok(!("error" in test1) && test1.env === "test");
  const wrong1 = readConfig("prod", { VITE_SUPABASE_URL: TEST_URL, VITE_SUPABASE_KEY: KEY });
  assert.ok("error" in wrong1 && /peker ikke på prod/.test(wrong1.error));
  const wrong2 = readConfig("test", { VITE_SUPABASE_URL: PROD_URL, VITE_SUPABASE_KEY: KEY });
  assert.ok("error" in wrong2 && /peker på prod/.test(wrong2.error));
});

test("den hemmelige nøkkelen avvises", () => {
  assert.equal(isSecretKey("sb_secret_abc"), true);
  assert.equal(isSecretKey(jwt("service_role")), true);
  assert.equal(isSecretKey(jwt("anon")), false);
  assert.equal(isSecretKey(KEY), false);
  assert.equal(isSecretKey("eyJ.ikke-json.x"), false);
  const r = readConfig("prod", { VITE_SUPABASE_URL: PROD_URL, VITE_SUPABASE_KEY: "sb_secret_abc" });
  assert.ok("error" in r && /hemmelige nøkkelen/.test(r.error));
});

test("site key for Turnstile: tom er av, feilskrevet stopper", () => {
  const on = readConfig("prod", { VITE_SUPABASE_URL: PROD_URL, VITE_SUPABASE_KEY: KEY, VITE_TURNSTILE_SITE_KEY: " 0x4AAAAAAABkMYinukE8nzYS " });
  assert.ok(!("error" in on) && on.turnstileSiteKey === "0x4AAAAAAABkMYinukE8nzYS");
  const off = readConfig("prod", { VITE_SUPABASE_URL: PROD_URL, VITE_SUPABASE_KEY: KEY, VITE_TURNSTILE_SITE_KEY: "  " });
  assert.ok(!("error" in off) && off.turnstileSiteKey === null);
  const bad = readConfig("prod", { VITE_SUPABASE_URL: PROD_URL, VITE_SUPABASE_KEY: KEY, VITE_TURNSTILE_SITE_KEY: "kort" });
  assert.ok("error" in bad && /site key/.test(bad.error));
});

test("veddemål vises bare i test (BetsFeature)", () => {
  assert.equal(betsVisible("test"), true);
  assert.equal(betsVisible("prod"), false);
});
