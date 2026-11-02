// Innholdssider for Google (SEO): kalkulator, klubbsiden og guidene. Hver side ligger i sin egen fil i
// src/innhold/ og legges til med én linje i CONTENT_PAGES. Ruting, sitemap.xml og lenkene i bunnen av
// de indekserte sidene hentes herfra (src/index.ts), så en ny side trenger ingen andre endringer.

import { GUIDE_GOLFLIGA } from "./innhold/guide-golfliga.ts";

export interface ContentPage {
  /** Adressen, uten skråstrek til slutt (f.eks. "/stableford"). */
  path: string;
  /** `<title>`: det folk søker etter først, så « – Atten». */
  title: string;
  /** Meta-beskrivelsen, høyst ca. 155 tegn. */
  description: string;
  /** Siste innholdsendring (ÅÅÅÅ-MM-DD), til sitemap.xml. */
  lastmod: string;
  /** Kort lenketekst i bunnen av de indekserte sidene. */
  linkText: string;
  /** HTML inne i `<main>`, allerede escapet. */
  content: string;
  /** Valgfritt skript for siden (kjøres med nonce, ingen eksterne skript). */
  script?: string;
  /** Valgfrie strukturerte data (schema.org), legges inn som JSON-LD. */
  jsonLd?: Record<string, unknown>;
}

export const CONTENT_PAGES: readonly ContentPage[] = [
  GUIDE_GOLFLIGA,
];

export function contentPage(pathname: string): ContentPage | null {
  const path = pathname.length > 1 ? pathname.replace(/\/$/, "") : pathname;
  return CONTENT_PAGES.find((p) => p.path === path) ?? null;
}
