// Lesing av JSON som Swifts `Decodable`: `decodeIfPresent` gir `null` når feltet mangler eller er
// `null`, og feil type kaster (som `DecodingError`). Heltall må være hele tall.

export type JSONObject = Record<string, unknown>;

export class DecodeError extends Error {
  constructor(path: string, message: string) {
    super(`${path}: ${message}`);
    this.name = "DecodeError";
  }
}

export function isObject(x: unknown): x is JSONObject {
  return x !== null && typeof x === "object" && !Array.isArray(x);
}

export function obj(x: unknown, path = "$"): JSONObject {
  if (!isObject(x)) throw new DecodeError(path, "ventet et objekt");
  return x;
}

/** Har objektet nøkkelen (også med `null`)? Som `container.contains(key)`. */
export function has(o: JSONObject, key: string): boolean {
  return Object.prototype.hasOwnProperty.call(o, key);
}

function present(o: JSONObject, key: string): unknown {
  return has(o, key) ? o[key] : undefined;
}

export function optNumber(o: JSONObject, key: string, path = "$"): number | null {
  const v = present(o, key);
  if (v === undefined || v === null) return null;
  if (typeof v !== "number") throw new DecodeError(`${path}.${key}`, "ventet et tall");
  return v;
}

export function optInt(o: JSONObject, key: string, path = "$"): number | null {
  const v = optNumber(o, key, path);
  if (v !== null && !Number.isInteger(v)) throw new DecodeError(`${path}.${key}`, "ventet et heltall");
  return v;
}

export function optString(o: JSONObject, key: string, path = "$"): string | null {
  const v = present(o, key);
  if (v === undefined || v === null) return null;
  if (typeof v !== "string") throw new DecodeError(`${path}.${key}`, "ventet en streng");
  return v;
}

export function optBool(o: JSONObject, key: string, path = "$"): boolean | null {
  const v = present(o, key);
  if (v === undefined || v === null) return null;
  if (typeof v !== "boolean") throw new DecodeError(`${path}.${key}`, "ventet true/false");
  return v;
}

export function optArray(o: JSONObject, key: string, path = "$"): unknown[] | null {
  const v = present(o, key);
  if (v === undefined || v === null) return null;
  if (!Array.isArray(v)) throw new DecodeError(`${path}.${key}`, "ventet en liste");
  return v;
}

export function optObject(o: JSONObject, key: string, path = "$"): JSONObject | null {
  const v = present(o, key);
  if (v === undefined || v === null) return null;
  return obj(v, `${path}.${key}`);
}

export function reqString(o: JSONObject, key: string, path = "$"): string {
  const v = optString(o, key, path);
  if (v === null) throw new DecodeError(`${path}.${key}`, "mangler");
  return v;
}

export function reqNumber(o: JSONObject, key: string, path = "$"): number {
  const v = optNumber(o, key, path);
  if (v === null) throw new DecodeError(`${path}.${key}`, "mangler");
  return v;
}

export function reqInt(o: JSONObject, key: string, path = "$"): number {
  const v = optInt(o, key, path);
  if (v === null) throw new DecodeError(`${path}.${key}`, "mangler");
  return v;
}

export function reqBool(o: JSONObject, key: string, path = "$"): boolean {
  const v = optBool(o, key, path);
  if (v === null) throw new DecodeError(`${path}.${key}`, "mangler");
  return v;
}

export function numberArray(v: unknown[], path: string, integer = false): number[] {
  return v.map((x, i) => {
    if (typeof x !== "number" || (integer && !Number.isInteger(x))) {
      throw new DecodeError(`${path}[${i}]`, integer ? "ventet et heltall" : "ventet et tall");
    }
    return x;
  });
}

export function stringArray(v: unknown[], path: string): string[] {
  return v.map((x, i) => {
    if (typeof x !== "string") throw new DecodeError(`${path}[${i}]`, "ventet en streng");
    return x;
  });
}

/** En verdi fra en fast liste (Swift-enum med rå-verdier). */
export function enumValue<T extends string>(v: unknown, allowed: readonly T[], path: string): T {
  if (typeof v !== "string" || !(allowed as readonly string[]).includes(v)) {
    throw new DecodeError(path, `ukjent verdi ${JSON.stringify(v)}`);
  }
  return v as T;
}

export function optEnum<T extends string>(o: JSONObject, key: string, allowed: readonly T[], path = "$"): T | null {
  const v = present(o, key);
  if (v === undefined || v === null) return null;
  return enumValue(v, allowed, `${path}.${key}`);
}

/** `[Int: T]` fra et JSON-objekt med tallnøkler («0», «1» …). */
export function intKeyedMap<T>(o: JSONObject, path: string, value: (v: unknown, path: string) => T): Map<number, T> {
  const out = new Map<number, T>();
  for (const [k, v] of Object.entries(o)) {
    const n = Number(k);
    if (k.trim() === "" || !Number.isInteger(n)) throw new DecodeError(`${path}.${k}`, "ventet en heltallsnøkkel");
    out.set(n, value(v, `${path}.${k}`));
  }
  return out;
}

/** `[String: T]` fra et JSON-objekt. */
export function stringKeyedMap<T>(o: JSONObject, path: string, value: (v: unknown, path: string) => T): Map<string, T> {
  const out = new Map<string, T>();
  for (const [k, v] of Object.entries(o)) out.set(k, value(v, `${path}.${k}`));
  return out;
}

export function asNumber(v: unknown, path: string): number {
  if (typeof v !== "number") throw new DecodeError(path, "ventet et tall");
  return v;
}

export function asInt(v: unknown, path: string): number {
  if (typeof v !== "number" || !Number.isInteger(v)) throw new DecodeError(path, "ventet et heltall");
  return v;
}

export function asString(v: unknown, path: string): string {
  if (typeof v !== "string") throw new DecodeError(path, "ventet en streng");
  return v;
}
