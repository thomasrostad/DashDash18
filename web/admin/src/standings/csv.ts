// Eksport til CSV for norsk Excel og Numbers: semikolon mellom feltene, desimalkomma, UTF-8 med BOM
// (så «æøå» blir riktig), og CRLF mellom linjene.

import { toParText, type RoundsGrid, type RoundsGridRow } from "../../../golfgutu-core/src/index.ts";
import type { TableView } from "./model.ts";

export type Cell = string | number | null | undefined;

/** «Alle runder» viser poeng, slag eller slag mot par. */
export type GridMode = "points" | "strokes" | "toPar";

export const BOM = "﻿";

/** Tall med desimalkomma («5,5»), tekst som den er. Tomt for `null`. */
export function cellText(x: Cell): string {
  if (x === null || x === undefined) return "";
  if (typeof x === "number") return Number.isFinite(x) ? String(x).replace(".", ",") : "";
  return x;
}

/** Ett felt: i anførselstegn når det inneholder skilletegn, anførselstegn eller linjeskift. */
export function csvField(x: Cell): string {
  const t = cellText(x);
  return /[;"\r\n]/.test(t) ? `"${t.replace(/"/g, '""')}"` : t;
}

/** Hele fila med BOM først. */
export function buildCsv(rows: readonly (readonly Cell[])[]): string {
  return BOM + rows.map((r) => r.map(csvField).join(";")).join("\r\n") + "\r\n";
}

/** Tabellen: plass, navn, poeng, tallene bak og linja under, som i appen. */
export function tableCsv(view: TableView): string {
  const head: Cell[] = ["Plass", "Navn", ...view.numberColumns.map((c) => c.label), "Detaljer"];
  const body = view.rows.map((r): Cell[] => [r.placeText, r.name, ...view.numberColumns.map((c) => r.numbers[c.key] ?? null), r.detail]);
  return buildCsv([head, ...body]);
}

/** Verdien i en rute av «Alle runder» som tekst (poeng og slag som tall, mot par som «+3», «E», «−2»). */
export function gridValue(row: RoundsGridRow, n: number, mode: GridMode): Cell {
  switch (mode) {
    case "points":
      return row.points[n];
    case "strokes":
      return row.strokes[n];
    case "toPar": {
      const t = row.toPar[n];
      return t === null ? null : toParText(t);
    }
  }
}

/** Summen til høyre, som `RoundsLeaderboardView.total`: «–» for slag uten førte hull. */
export function gridTotal(row: RoundsGridRow, mode: GridMode): string {
  switch (mode) {
    case "points":
      return `${row.pointsTotal}`;
    case "strokes":
      return row.strokes.some((x) => x !== null) ? `${row.strokesTotal}` : "–";
    case "toPar":
      return row.toPar.some((x) => x !== null) ? toParText(row.toParTotal) : "–";
  }
}

/** Er ruta best i runden (gul i appen)? Mot par følger slagene. */
export function isBest(grid: RoundsGrid, row: RoundsGridRow, n: number, mode: GridMode): boolean {
  if (mode === "points") return row.points[n] !== null && row.points[n] === grid.bestPoints[n];
  return row.strokes[n] !== null && row.strokes[n] === grid.bestStrokes[n];
}

/** «Alle runder»: én kolonne per runde («1 · 8.10 · Kveld 1»), sum til slutt. Runder som ikke teller får «(teller ikke)». */
export function gridCsv(grid: RoundsGrid, mode: GridMode): string {
  const head: Cell[] = ["Plass", "Navn", ...grid.columns.map((c) => [c.label, c.date, c.title].filter((x) => x).join(" · ")), "Sum"];
  const body = grid.rows.map((r): Cell[] => [
    r.place,
    r.name,
    ...grid.columns.map((_, n) => {
      const v = gridValue(r, n, mode);
      if (v === null || v === undefined) return null;
      return r.counted !== null && !r.counted[n] ? `${cellText(v)} (teller ikke)` : v;
    }),
    mode === "points" ? r.pointsTotal : gridTotal(r, mode),
  ]);
  return buildCsv([head, ...body]);
}

/** Filnavn uten tegn som ikke tåles: «Vår 2026 tabell.csv». */
export function fileName(title: string, suffix: string): string {
  const clean = title.replace(/[\\/:*?"<>|]+/g, " ").replace(/\s+/g, " ").trim() || "tabell";
  return `${clean} ${suffix}.csv`;
}
