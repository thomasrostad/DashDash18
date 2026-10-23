// CAPTCHA ved innlogging (pakke 1). Samme feilkoder og tekster som appens CaptchaError (DashDash18Tests/CaptchaTests.swift).
import { test } from "node:test";
import assert from "node:assert/strict";
import { CAPTCHA_TEXT, TURNSTILE_SCRIPT, canSendCode, captchaErrorText, otpOptions } from "../src/captcha.ts";

test("feilkodene fra Turnstile", () => {
  assert.equal(captchaErrorText("load"), CAPTCHA_TEXT.pageUnavailable);
  assert.equal(captchaErrorText("200500"), CAPTCHA_TEXT.pageUnavailable);
  assert.equal(captchaErrorText("110200"), CAPTCHA_TEXT.misconfigured);
  assert.equal(captchaErrorText("400020"), CAPTCHA_TEXT.misconfigured);
  assert.equal(captchaErrorText("300030"), CAPTCHA_TEXT.failed);
  assert.equal(captchaErrorText(""), CAPTCHA_TEXT.failed);
  for (const t of Object.values(CAPTCHA_TEXT)) assert.ok(!t.includes("Apple") && !t.includes("—"));
});

test("tokenet følger med koden, og ingen nye brukere fra web", () => {
  assert.deepEqual(otpOptions(null), { shouldCreateUser: false });
  assert.deepEqual(otpOptions("tok"), { shouldCreateUser: false, captchaToken: "tok" });
});

test("«Send kode» venter på sjekken når CAPTCHA er på", () => {
  assert.equal(canSendCode("a@b.no", false, null), true);
  assert.equal(canSendCode("a@b.no", true, null), false);
  assert.equal(canSendCode("a@b.no", true, "tok"), true);
  assert.equal(canSendCode("ab.no", true, "tok"), false);
});

test("samme skript som appens /captcha-side", () => {
  assert.match(TURNSTILE_SCRIPT, /^https:\/\/challenges\.cloudflare\.com\/turnstile\/v0\/api\.js\?render=explicit&onload=attenTurnstile$/);
});
