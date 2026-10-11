// Gjennomføringsplanen steg 1 (sql/034): flere aktive runder og serier i en klubb. Samme saker som
// appens DashDash18Tests/FlereAktiveTests.swift.
import { test } from "node:test";
import assert from "node:assert/strict";
import { blockingRound, mainActiveSeason, mainSeasonIDs, MAX_BAYS, startErrorText } from "../src/rounds/logic.ts";

const id = (n: number) => `00000000-0000-0000-0000-${String(n).padStart(12, "0")}`;
const season = (n: number, status: string) => ({ id: id(n), status });

test("hovedturneringen vinner, aldri en vilkårlig aktiv", () => {
  const siden = season(2, "active"), hoved = season(1, "active"), ferdig = season(3, "finished");
  assert.equal(mainActiveSeason([siden, hoved, ferdig], [hoved.id]), hoved);
  // To aktive, ingen merket: ingen.
  assert.equal(mainActiveSeason([siden, hoved], []), null);
  // Én aktiv uten kjente hovedturneringer (som før 034): den.
  assert.equal(mainActiveSeason([siden, ferdig], []), siden);
  // En serie ved siden av blir ikke hovedturnering når hovedturneringene er kjent.
  assert.equal(mainActiveSeason([siden], [hoved.id]), null);
  assert.deepEqual(mainSeasonIDs([
    { is_main: true, season_id: hoved.id }, { is_main: false, season_id: siden.id }, { is_main: true, season_id: null },
  ]), [hoved.id]);
});

test("bare puljen på samme spilledag er i veien", () => {
  const annenDag = { id: id(1), eventID: id(20), waveNo: 1 };
  const sammeDag = { id: id(2), eventID: id(10), waveNo: 1 };
  assert.equal(blockingRound([annenDag], id(3), id(10), 1), null);
  assert.equal(blockingRound([annenDag, sammeDag], id(3), id(10), 1), sammeDag);
  assert.equal(blockingRound([sammeDag], id(3), id(10), 2), null);
  assert.equal(blockingRound([sammeDag], sammeDag.id, id(10), 1), null);
});

test("feilmeldingen navngir puljen", () => {
  const ny = { code: "23505", message: "duplicate key value violates unique constraint \"rounds_one_active_per_event_wave\"" };
  const gammel = { code: "23505", message: "duplicate key value violates unique constraint \"rounds_one_active_per_club\"" };
  assert.equal(startErrorText(ny), "En runde går allerede i denne puljen. Lås den før du starter en ny.");
  assert.equal(startErrorText(gammel), "En runde går allerede. Lås den før du starter en ny.");
});

test("båsgrensen er databasens", () => {
  assert.equal(MAX_BAYS, 99);
});
