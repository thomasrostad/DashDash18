// Menyen i arrangørsiden: fanene (roles.ts `visibleTabs`) gruppert i «I dag», «Spill» og «Klubb», med
// tittel og en linje om hva siden er til. Fanen står i adressen (#terminliste), så en ny lasting blir der du var.
// Ren logikk, testes i test/nav.test.ts.
import type { Tab } from "./roles.ts";

export interface TabInfo { title: string; lead: string; icon: string }

export const TAB_INFO: Record<Tab, TabInfo> = {
  kvelden: { title: "Kvelden", lead: "Det som skjer nå: hvem som er inne, tabellen og det som trenger deg.", icon: "M12 3v2M12 19v2M4.2 4.2l1.4 1.4M18.4 18.4l1.4 1.4M3 12h2M19 12h2M4.2 19.8l1.4-1.4M18.4 5.6l1.4-1.4M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8z" },
  terminliste: { title: "Terminliste", lead: "Spilledagene. Sett opp runden, se påmeldingen og startlista.", icon: "M7 3v3M17 3v3M4 8h16M5 5h14a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1z" },
  turneringer: { title: "Turneringer", lead: "Sesonger, ligaer og cuper: regler, påmelding, tilleggspoeng og stab.", icon: "M8 21h8M12 17v4M7 4h10v5a5 5 0 0 1-10 0V4zM7 6H4a3 3 0 0 0 3 4M17 6h3a3 3 0 0 1-3 4" },
  tabeller: { title: "Tabeller", lead: "Stillingen i turneringene, slik spillerne ser den.", icon: "M4 20V10M10 20V4M16 20v-7M22 20H2" },
  tropp: { title: "Tropp", lead: "Medlemmene, handicap, invitasjoner og hvem som venter på godkjenning.", icon: "M16 19v-1a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v1M9 10a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM22 19v-1a4 4 0 0 0-3-3.9M16 4.1a3 3 0 0 1 0 5.8" },
  baner: { title: "Baner", lead: "Banene klubben spiller, også simulatorbaner. Baner fra slope.no velges i rundeoppsettet.", icon: "M6 21V4l10 4-10 4M6 21h12" },
  roller: { title: "Roller", lead: "Hvem som kan gjøre hva i klubben.", icon: "M12 3l8 4v5c0 5-3.5 8-8 9-4.5-1-8-4-8-9V7l8-4z" },
  klubb: { title: "Klubb", lead: "Navnet på klubben og innstillingene.", icon: "M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z" },
};

export const NAV_GROUPS: { title: string; tabs: Tab[] }[] = [
  { title: "I dag", tabs: ["kvelden"] },
  { title: "Spill", tabs: ["terminliste", "turneringer", "tabeller"] },
  { title: "Klubb", tabs: ["tropp", "baner", "roller", "klubb"] },
];

/** Gruppene med bare fanene du har, i menyens rekkefølge. Tomme grupper faller bort. */
export function navGroups(visible: readonly Tab[]): { title: string; tabs: Tab[] }[] {
  const has = new Set(visible);
  return NAV_GROUPS.map((g) => ({ title: g.title, tabs: g.tabs.filter((t) => has.has(t)) })).filter((g) => g.tabs.length > 0);
}

/** Fanen i adressen (#terminliste), hvis den finnes og du har den. */
export function tabFromHash(hash: string, visible: readonly Tab[]): Tab | null {
  const key = hash.replace(/^#/, "").split("/")[0];
  return (visible as readonly string[]).includes(key) ? (key as Tab) : null;
}
