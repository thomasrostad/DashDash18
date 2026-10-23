import { supabase } from "./supabase.ts";
import { sharingErrorText } from "./sharing.ts";

// TV-kode (sql/041) og «Del tavla» (sql/056). Bare arrangøren av turneringen; RPC-ene sjekker tilgangen.

async function call<T>(fn: string, params: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn, params);
  if (error) throw new Error(sharingErrorText(error));
  return data as T;
}

/** Koden som gjelder, eller en ny (`renew` lager ny og trekker den gamle tilbake). */
export function tvCode(competitionID: string, renew = false): Promise<string> {
  return call("tv_code", { p_competition_id: competitionID, p_renew: renew });
}

export async function tvCodeRevoke(competitionID: string): Promise<void> {
  await call("tv_code_revoke", { p_competition_id: competitionID });
}

/** Er delingen på? Lager aldri en kode. */
export function tavlaShareCurrent(competitionID: string): Promise<string | null> {
  return call("tavla_share_current", { p_competition_id: competitionID });
}

/** På: lenken som gjelder, ellers en ny. `renew`: ny lenke, den gamle slutter å virke. */
export function tavlaShareCode(competitionID: string, renew = false): Promise<string> {
  return call("tavla_share_code", { p_competition_id: competitionID, p_renew: renew });
}

export async function tavlaShareRevoke(competitionID: string): Promise<void> {
  await call("tavla_share_revoke", { p_competition_id: competitionID });
}
