import { test } from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

// Gjennomføringsplanen steg 3: web-admin leser ikke `seasons` (blir et view i sql/035). Sesongene
// hentes fra `competitions` med `season_id` (src/seasons.ts). Bare «ny sesong» skriver `seasons`,
// uten å lese svaret derfra.

const src = fileURLToPath(new URL("../src/", import.meta.url));

function files(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    return statSync(path).isDirectory() ? files(path) : /\.(ts|tsx)$/.test(name) ? [path] : [];
  });
}

test("sesong: ingen lesing fra seasons, bare insert i createSeason", () => {
  const uses: string[] = [];
  for (const path of files(src)) {
    const text = readFileSync(path, "utf8");
    for (const m of text.matchAll(/from\("seasons"\)([\s\S]{0,40})/g)) {
      uses.push(`${path.slice(src.length)}:${m[1].trim().split("(")[0]}`);
    }
  }
  assert.deepEqual(uses, ["data.ts:.insert"]);
  const data = readFileSync(join(src, "data.ts"), "utf8");
  const create = data.slice(data.indexOf("export async function createSeason"), data.indexOf("export async function createCompetition"));
  assert.ok(!create.includes(".select("), "createSeason leser ikke svaret fra seasons");
  assert.ok(create.includes("crypto.randomUUID()"), "id-en lages i klienten");
});

test("sesong: kolonnene og filteret mot competitions", () => {
  const text = readFileSync(join(src, "seasons.ts"), "utf8");
  assert.ok(text.includes(`export const SEASON_COLUMNS = "id:season_id, club_id, name, status, rules";`));
  assert.ok(text.includes(`supabase.from("competitions").select(columns).not("season_id", "is", null)`));
  // Filtrene på sesongen går på season_id, ikke id (turneringsradens egen id).
  const standings = readFileSync(join(src, "standings/queries.ts"), "utf8");
  assert.ok(standings.includes(`seasonRows().eq("season_id", c.season_id)`));
  assert.ok(standings.includes(`seasonRows().in("season_id", seasonIDs)`));
  const rounds = readFileSync(join(src, "rounds/api.ts"), "utf8");
  assert.ok(rounds.includes(`seasonRows("id:season_id, status, rules").eq("club_id", clubID)`));
});

test("sesong: regler lagres i turneringsraden, også for en sesong", () => {
  const data = readFileSync(join(src, "data.ts"), "utf8");
  const save = data.slice(data.indexOf("export async function saveRules"), data.indexOf("export function activateSeasonParams"));
  assert.ok(save.includes(`supabase.from("competitions").update({ rules }).eq("id", c.id)`));
  assert.ok(!save.includes("seasons"));
});
