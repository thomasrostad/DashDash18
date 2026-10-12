import { supabase } from "./supabase.ts";
import { betsErrorText, enabledFromRow, setEnabledParams } from "./bets.ts";

// Veddemål på og av (sql/052). Uten 052 finnes ikke kolonnen: bryteren skjules.

/** competitions.bets_enabled, eller null når 052 ikke er kjørt. */
export async function betsEnabled(competitionID: string): Promise<boolean | null> {
  const { data, error } = await supabase.from("competitions").select("bets_enabled").eq("id", competitionID).maybeSingle();
  return enabledFromRow(data as { bets_enabled?: boolean } | null, error);
}

/** Slår veddemål på eller av (turneringens admin eller money). */
export async function setBetsEnabled(competitionID: string, on: boolean): Promise<void> {
  const { error } = await supabase.rpc("bets_set_enabled", setEnabledParams(competitionID, on));
  if (error) throw new Error(betsErrorText(error));
}
