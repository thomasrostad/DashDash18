import { supabase } from "./supabase.ts";
import { inviteFromRow, participantErrorText } from "./participants.ts";

// Deltakere uten innlogging (sql/060) og turneringens lenke (sql/022, 060). RPC-ene sjekker tilgangen.

/** Navnene som er påmeldt turneringen (medlemmer og deltakere), så lista ikke legger dem inn på nytt. */
export async function enteredNames(competitionID: string): Promise<string[]> {
  const { data, error } = await supabase.from("competition_participants")
    .select("club_members(display_name)").eq("competition_id", competitionID).eq("status", "active");
  if (error) throw error;
  return (data as unknown as { club_members: { display_name: string } | null }[])
    .flatMap((r) => (r.club_members ? [r.club_members.display_name] : []));
}

/** Legger inn deltakerne i én omgang. Gir hvor mange som ble lagt til. */
export async function addParticipants(competitionID: string, entries: object[]): Promise<number> {
  const { data, error } = await supabase.rpc("add_competition_participants", { p_competition_id: competitionID, p_entries: entries });
  if (error) throw new Error(participantErrorText(error));
  return data as number;
}

/** Koden som gjelder, eller en ny (`renew`: den gamle slutter å virke). */
export async function competitionInvite(competitionID: string, renew = false) {
  const { data, error } = await supabase.rpc("competition_invite", { p_competition_id: competitionID, p_renew: renew });
  if (error) throw new Error(participantErrorText(error));
  return inviteFromRow(data as { code?: unknown; expires_at?: unknown } | null);
}

/** Trekker koden tilbake. De påmeldte er fortsatt med. */
export async function revokeCompetitionInvite(competitionID: string): Promise<void> {
  const { error } = await supabase.rpc("revoke_competition_invite", { p_competition_id: competitionID });
  if (error) throw new Error(participantErrorText(error));
}
