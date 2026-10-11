// Egne roller per klubb (steg 2, sql/044, docs/roller.md). Ren logikk, som ClubRoles.swift i appen:
// rettighetene, rekkefølgen, hva du har, hvilke roller du kan gi, og hvilke faner som vises.
// Serveren er vakta (RLS og RPC-ene); her skjules bare det du ikke har lov til.

export type Right = "tournaments" | "rounds" | "members" | "money";
export const RIGHTS: Right[] = ["tournaments", "rounds", "members", "money"];

export const RIGHT_TITLES: Record<Right, string> = {
  tournaments: "Turneringer og regler",
  rounds: "Runder og føring",
  members: "Medlemmer og invitasjon",
  money: "Penger og moderering",
};

export type ClubRole = {
  id: string; club_id: string; name: string; rights: string[]; is_owner: boolean;
  template_key: string | null; sort_order: number;
};
export type MemberRole = { club_id: string; member_id: string; role_id: string };

export type Rights = { rights: Set<Right>; isOwner: boolean };

/** Rettighetene til en rolle. Eier har alle fire, uansett hva raden sier. */
export function roleRights(role: ClubRole): Set<Right> {
  if (role.is_owner) return new Set(RIGHTS);
  return new Set(role.rights.filter((r): r is Right => (RIGHTS as string[]).includes(r)));
}

/** Rettighetene fra rollene medlemmet har, lagt sammen. */
export function rightsOf(roles: ClubRole[], roleIDs: Iterable<string>): Rights {
  const ids = new Set(roleIDs);
  const mine = roles.filter((r) => ids.has(r.id));
  const isOwner = mine.some((r) => r.is_owner);
  const rights = new Set<Right>(isOwner ? RIGHTS : []);
  for (const r of mine) for (const x of roleRights(r)) rights.add(x);
  return { rights, isOwner };
}

/** Uten roller (044 ikke kjørt): flaggene. Arrangør har alt, kasserer har penger. Ingen er eier. */
export function legacyRights(isOrganizer: boolean, isTreasurer: boolean): Rights {
  if (isOrganizer) return { rights: new Set(RIGHTS), isOwner: false };
  return { rights: new Set(isTreasurer ? ["money"] : []), isOwner: false };
}

export function hasAny(r: Rights): boolean {
  return r.isOwner || r.rights.size > 0;
}

/** Kan gi eller ta rollen: Eier bare av en eier; ellers kreves members, og rollens rettigheter må være blant dine. */
export function canGrant(viewer: Rights, role: ClubRole): boolean {
  if (role.is_owner) return viewer.isOwner;
  if (!viewer.rights.has("members")) return false;
  for (const r of roleRights(role)) if (!viewer.rights.has(r)) return false;
  return true;
}

/** Eier først, så malene, så klubbens egne. Innenfor hver: sort_order, så navn. */
export function sortRoles(roles: ClubRole[]): ClubRole[] {
  const rank = (r: ClubRole) => (r.is_owner ? 0 : r.template_key ? 1 : 2);
  return [...roles].sort((a, b) => rank(a) - rank(b) || a.sort_order - b.sort_order || a.name.localeCompare(b.name, "nb"));
}

/** Navnet på en rolle: 1–40 tegn, og ikke likt en annen rolle i klubben. Gir feilteksten eller null. */
export function roleNameError(name: string, roles: ClubRole[], editingID: string | null): string | null {
  const n = name.trim();
  if (n.length < 1 || n.length > 40) return "Rollen må ha et navn (1–40 tegn).";
  if (roles.some((r) => r.id !== editingID && r.name.trim().toLowerCase() === n.toLowerCase())) {
    return `Klubben har alt en rolle som heter «${n}».`;
  }
  return null;
}

/** Rettighetene i fast rekkefølge, som de sendes til club_role_save. */
export function rightsParam(rights: Iterable<string>): Right[] {
  const s = new Set(rights);
  return RIGHTS.filter((r) => s.has(r));
}

export type Tab = "turneringer" | "terminliste" | "tropp" | "tabeller" | "roller" | "klubb";

/** Fanene i web-admin for rettighetene. Roller bare for eieren, og bare når klubben har roller. */
export function visibleTabs(r: Rights, hasRoles: boolean): Tab[] {
  const tabs: Tab[] = [];
  if (r.rights.has("tournaments")) tabs.push("turneringer");
  if (r.rights.has("tournaments") || r.rights.has("rounds")) tabs.push("terminliste");
  if (r.rights.has("members")) tabs.push("tropp");
  if (hasAny(r)) tabs.push("tabeller", "klubb");
  if (r.isOwner && hasRoles) tabs.push("roller");
  return tabs;
}
