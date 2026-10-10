import { createClient } from "@supabase/supabase-js";

// Samme Supabase og samme tilgangsregler (RLS og RPC-ene) som appen. Bare publishable key.
const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const key = import.meta.env.VITE_SUPABASE_KEY as string | undefined;

export const configError = !url || !key ? "Mangler VITE_SUPABASE_URL eller VITE_SUPABASE_KEY (se .env.example)." : null;

export const supabase = createClient(url ?? "http://localhost", key ?? "x", {
  auth: { persistSession: true, autoRefreshToken: true },
});

/** Norsk feiltekst fra Supabase-feil. */
export function errorText(e: unknown): string {
  const m = (e as { message?: string })?.message ?? String(e);
  if (/Token has expired|invalid/i.test(m)) return "Koden er feil eller utløpt. Be om en ny kode.";
  if (/Signups not allowed|User not found/i.test(m)) return "Fant ingen bruker med den e-posten. Logg inn i appen først.";
  if (/Failed to fetch|NetworkError/i.test(m)) return "Får ikke kontakt med serveren. Sjekk nettet.";
  return m;
}
