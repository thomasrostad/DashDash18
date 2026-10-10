// Avrunding, sortering og små hjelpere som gir nøyaktig samme svar som Swift-motoren
// (Packages/GolfgutuCore/Sources/GolfgutuCore/JSMath.swift) og PWA-en (db-nytt.js).
//
// All avrunding i regelmotoren går gjennom disse. `Math.round` brukes aldri direkte: Swift-motoren
// regner `floor(x + 0.5)`, og det gjør vi også.

/** JS `Math.round(x)` slik Swift-motoren regner den: `floor(x + 0.5)`. */
export function jsRound(x: number): number {
  return Math.floor(x + 0.5);
}

/** `rund2` i db-nytt.js: `Math.round(x * 100) / 100`. */
export function round2(x: number): number {
  return jsRound(x * 100) / 100;
}

/** Nærmeste halve: `Math.round(x * 2) / 2`. */
export function roundHalf(x: number): number {
  return jsRound(x * 2) / 2;
}

/** Swifts `.rounded()` (`toNearestOrAwayFromZero`): ,5 bort fra null. Eksakt, uten `x + 0.5`. */
export function roundAwayFromZero(x: number): number {
  if (!Number.isFinite(x)) return x;
  const t = Math.trunc(x);
  const frac = Math.abs(x - t);
  if (frac >= 0.5) return t + (x < 0 ? -1 : 1);
  // −0,4 gir −0 i Swift; vi gir 0 (det er likt som tall).
  return t === 0 ? 0 : t;
}

/** `String(n)` for et endelig tall: «4», ikke «4.0»; −0 som «0». */
export function jsString(x: number): string {
  if (x === 0) return "0";
  return String(x);
}

/** `String(n).replace('.', ',')`: norsk desimalkomma. */
export function norwegianString(x: number): string {
  return jsString(x).replace(".", ",");
}

// MARK: Norsk sortering

const collator = new Intl.Collator("no");

/** Som `a.localeCompare(b, 'no')`: −1, 0 eller 1. Æ, ø og å etter z. */
export function norwegianCompare(a: string, b: string): number {
  const c = collator.compare(a, b);
  return c < 0 ? -1 : c > 0 ? 1 : 0;
}

/** `true` når `a` skal stå før `b`. */
export function norwegianLess(a: string, b: string): boolean {
  return norwegianCompare(a, b) < 0;
}

// MARK: Sortering som i Swift

/**
 * Stabil sortering med et «står før»-predikat, som Swifts `sorted(by:)`. Returnerer en ny liste.
 * JS-sorteringen er stabil, og Swifts er det i praksis; komparatorene i motoren skiller uansett
 * alt som betyr noe.
 */
export function sortedBy<T>(items: readonly T[], less: (a: T, b: T) => boolean): T[] {
  return [...items].sort((a, b) => (less(a, b) ? -1 : less(b, a) ? 1 : 0));
}

/** Swifts `String <` for id-er (ASCII): kodepunktrekkefølge. */
export function stringLess(a: string, b: string): boolean {
  return a < b;
}

/** Sorterte strenger, som Swifts `sorted()` på `[String]`. */
export function sortedStrings(items: Iterable<string>): string[] {
  return [...items].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
}

/** Leksikografisk sammenligning av tallister (`lexicographicallyPrecedes`), med `less` per element. */
export function lexicographicallyPrecedes(a: readonly number[], b: readonly number[], less: (x: number, y: number) => boolean): boolean {
  const n = Math.min(a.length, b.length);
  for (let i = 0; i < n; i++) {
    if (less(a[i], b[i])) return true;
    if (less(b[i], a[i])) return false;
  }
  return a.length < b.length;
}

/** Dyp likhet for JSON-aktige verdier (objekter, lister, Map, tall, strenger, null). */
export function deepEqual(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (typeof a === "number" && typeof b === "number") return Number.isNaN(a) && Number.isNaN(b);
  if (a === null || b === null || typeof a !== "object" || typeof b !== "object") return false;
  if (a instanceof Map || b instanceof Map) {
    if (!(a instanceof Map && b instanceof Map) || a.size !== b.size) return false;
    for (const [k, v] of a) {
      if (!b.has(k) || !deepEqual(v, b.get(k))) return false;
    }
    return true;
  }
  if (Array.isArray(a) !== Array.isArray(b)) return false;
  if (Array.isArray(a) && Array.isArray(b)) {
    if (a.length !== b.length) return false;
    return a.every((x, i) => deepEqual(x, b[i]));
  }
  const ka = Object.keys(a as object).filter((k) => (a as Record<string, unknown>)[k] !== undefined);
  const kb = Object.keys(b as object).filter((k) => (b as Record<string, unknown>)[k] !== undefined);
  if (ka.length !== kb.length) return false;
  return ka.every((k) => deepEqual((a as Record<string, unknown>)[k], (b as Record<string, unknown>)[k]));
}

/** Dyp kopi av en JSON-aktig verdi (også Map). */
export function deepCopy<T>(x: T): T {
  if (x === null || typeof x !== "object") return x;
  if (x instanceof Map) return new Map([...x].map(([k, v]) => [k, deepCopy(v)])) as T;
  if (Array.isArray(x)) return x.map(deepCopy) as T;
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(x as object)) out[k] = deepCopy(v);
  return out as T;
}

/** JSON med sorterte nøkler, som Swifts `JSONEncoder` med `.sortedKeys`. */
export function stableStringify(x: unknown): string {
  return JSON.stringify(sortKeys(x));
}

function sortKeys(x: unknown): unknown {
  if (x === null || typeof x !== "object") return x;
  if (Array.isArray(x)) return x.map(sortKeys);
  const out: Record<string, unknown> = {};
  for (const k of Object.keys(x as object).sort()) {
    const v = (x as Record<string, unknown>)[k];
    if (v !== undefined) out[k] = sortKeys(v);
  }
  return out;
}

/** `Map` → vanlig objekt (for JSON). */
export function mapToObject<V>(m: ReadonlyMap<string | number, V>): Record<string, V> {
  const out: Record<string, V> = {};
  for (const [k, v] of m) out[String(k)] = v;
  return out;
}
