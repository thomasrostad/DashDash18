import { supabase } from "./supabase.ts";
import { rightsParam, sortRoles, type ClubRole, type MemberRole } from "./roles.ts";

// Roller (sql/044) og klubbinnstillinger. Skriving av roller går bare gjennom RPC-ene.

export type RoleData = { roles: ClubRole[]; assignments: MemberRole[] };

/** Rollene i klubben og hvem som har dem. Null når 044 ikke er kjørt (eller noe feiler): da gjelder flaggene. */
export async function clubRoles(clubID: string): Promise<RoleData | null> {
  const [r, a] = await Promise.all([
    supabase.from("club_roles").select("id, club_id, name, rights, is_owner, template_key, sort_order").eq("club_id", clubID),
    supabase.from("club_member_roles").select("club_id, member_id, role_id").eq("club_id", clubID),
  ]);
  if (r.error || a.error || !r.data || r.data.length === 0) return null;
  return { roles: sortRoles(r.data as ClubRole[]), assignments: (a.data ?? []) as MemberRole[] };
}

export async function saveRole(clubID: string, roleID: string | null, name: string, rights: string[] | null): Promise<void> {
  const { error } = await supabase.rpc("club_role_save", {
    p_club_id: clubID, p_role_id: roleID, p_name: name.trim(), p_rights: rights === null ? null : rightsParam(rights),
  });
  if (error) throw error;
}

export async function deleteRole(roleID: string): Promise<void> {
  const { error } = await supabase.rpc("club_role_delete", { p_role_id: roleID });
  if (error) throw error;
}

export async function setMemberRoles(memberID: string, roleIDs: string[]): Promise<void> {
  const { error } = await supabase.rpc("club_member_set_roles", { p_member_id: memberID, p_role_ids: roleIDs });
  if (error) throw error;
}

export async function transferOwnership(clubID: string, memberID: string): Promise<void> {
  const { error } = await supabase.rpc("club_transfer_ownership", { p_club_id: clubID, p_to_member: memberID });
  if (error) throw error;
}

export type ClubSettings = { name: string; org_number: string | null; supportsOrgNumber: boolean };

/** Navn og organisasjonsnummer. Uten 044 finnes ikke org_number, og bare navnet hentes. */
export async function clubSettings(clubID: string): Promise<ClubSettings> {
  const full = await supabase.from("clubs").select("name, org_number").eq("id", clubID).single();
  if (!full.error) {
    const d = full.data as { name: string; org_number: string | null };
    return { name: d.name, org_number: d.org_number, supportsOrgNumber: true };
  }
  const { data, error } = await supabase.from("clubs").select("name").eq("id", clubID).single();
  if (error) throw error;
  return { name: (data as { name: string }).name, org_number: null, supportsOrgNumber: false };
}

export async function saveClubSettings(clubID: string, name: string, orgNumber: string | null, supportsOrgNumber: boolean): Promise<void> {
  const patch: Record<string, unknown> = { name: name.trim() };
  if (supportsOrgNumber) patch.org_number = orgNumber;
  const { data, error } = await supabase.from("clubs").update(patch).eq("id", clubID).select("id");
  if (error) throw error;
  if (!data || data.length === 0) throw new Error("Endringen ble ikke lagret. Du har kanskje ikke tilgang.");
}
