// Ren logikk for delete-account (fase 17, App Store 5.1.1(v)). Ingen nettverk,
// så den kan testes med `deno test supabase/functions/delete-account/`.

/** Ordet brukeren skriver i appen for å bekrefte (AccountDeletion.confirmationWord i Swift). */
export const CONFIRMATION_WORD = "SLETT";

/** Én fil i Storage som skal bort (account_storage_objects i sql/019). */
export interface StorageObject {
  bucket_id: string;
  name: string;
}

/** Bøttene kontoen kan ha filer i. Alt annet ignoreres (sikkerhetsnett). */
export const BUCKETS = ["avatars", "thread"] as const;

/** Storage-API-et tar høyst så mange stier per kall. */
export const MAX_PATHS_PER_CALL = 100;

/** Godtar forespørselen bare med riktig bekreftelse (store eller små bokstaver, uten mellomrom). */
export function isConfirmed(body: unknown): boolean {
  if (!body || typeof body !== "object") return false;
  const value = (body as Record<string, unknown>).confirm;
  return typeof value === "string" && value.trim().toUpperCase() === CONFIRMATION_WORD;
}

/** Bearer-tokenet fra Authorization-headeren, eller null. */
export function bearerToken(header: string | null): string | null {
  if (!header) return null;
  const match = /^Bearer\s+(\S+)$/i.exec(header.trim());
  return match ? match[1] : null;
}

/** Filene gruppert per bøtte og delt i kall à høyst MAX_PATHS_PER_CALL. */
export function removalBatches(objects: StorageObject[], max = MAX_PATHS_PER_CALL): { bucket: string; paths: string[] }[] {
  const byBucket = new Map<string, string[]>();
  for (const o of objects) {
    if (!(BUCKETS as readonly string[]).includes(o.bucket_id)) continue;
    if (!o.name || o.name.includes("..") || o.name.startsWith("/")) continue;
    const list = byBucket.get(o.bucket_id) ?? [];
    if (!list.includes(o.name)) list.push(o.name);
    byBucket.set(o.bucket_id, list);
  }
  const batches: { bucket: string; paths: string[] }[] = [];
  for (const bucket of [...byBucket.keys()].sort()) {
    const paths = byBucket.get(bucket)!;
    for (let i = 0; i < paths.length; i += max) batches.push({ bucket, paths: paths.slice(i, i + max) });
  }
  return batches;
}

/** Stegene i rekkefølge. Filene først: etter anonymiseringen finner vi ikke mappene igjen. */
export const STEPS = ["files", "anonymize", "auth_user"] as const;
export type Step = typeof STEPS[number];

/** Svaret til appen. `failedAt` sier hvor det stoppet, så appen kan be om et nytt forsøk. */
export interface DeletionResult {
  ok: boolean;
  removedFiles: number;
  summary?: Record<string, unknown>;
  failedAt?: Step;
  error?: string;
}

export function failure(step: Step, error: unknown, removedFiles = 0): DeletionResult {
  const message = String((error as Error)?.message ?? error).slice(0, 300);
  return { ok: false, removedFiles, failedAt: step, error: message };
}

/** HTTP-status for et resultat: 200 ferdig, 502 når et steg mot Supabase feilet. */
export function statusFor(result: DeletionResult): number {
  return result.ok ? 200 : 502;
}
