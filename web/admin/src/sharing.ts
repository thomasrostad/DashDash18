// TV-kode (sql/041, 043) og «Del tavla» (sql/056) på turneringssiden, som TVCode.swift og TavlaShare.swift i
// appen. Ren logikk her; kallene står i sharingApi.ts.

import { plainErrorText } from "./text.ts";

export const LINK_DOMAIN = "dashdash18.com";

/** «https://dashdash18.com/tv/ABCDEFGHJK». */
export function tvURL(code: string): string {
  return `https://${LINK_DOMAIN}/tv/${code}`;
}

/** «ABCDE FGHJK», lettere å lese av og skrive inn på en TV. */
export function spacedCode(code: string): string {
  return code.length === 10 ? `${code.slice(0, 5)} ${code.slice(5)}` : code;
}

/** «https://dashdash18.com/tavla/ABCDEFGHJK». */
export function tavlaURL(code: string): string {
  return `https://${LINK_DOMAIN}/tavla/${code}`;
}

/** Teksten som følger lenken når den deles (TavlaShare.message). */
export function tavlaMessage(competitionName: string): string {
  return `Følg ${competitionName} live – tabellen og scorekortene, uten app:`;
}

/** Lenken uten https://, slik appen viser den. */
export function displayURL(url: string): string {
  return url.replace(/^https:\/\//, "");
}

export const TV_TEXT = {
  howTo: `Åpn ${LINK_DOMAIN}/tv på skjermen og skriv koden, eller skann QR-koden.`,
  none: "Ingen kode. Lag en ny for å vise tabellen på en skjerm.",
  footer: (name: string) => `Skjermen viser tabellen og siste runde for ${name}, og oppdateres mens det føres. Ingen innlogging, e-post eller bilder vises.`,
  revokeQuestion: "Trekke tilbake koden? Skjermer som bruker koden, slutter å vise tabellen.",
};

export const SHARE_TEXT = {
  toggle: "Del tavla med en lenke",
  toggleFooter: "Slår du av, slutter lenken å virke med en gang. TV-koden påvirkes ikke.",
  on: "Alle med lenken ser tabellen, alle runder og scorekortene, oppdatert mens det føres. Uten app og uten innlogging.",
  onFooter: "Ingen e-post eller bilder vises. Er de siste hullene skjult mens runden går, vises de først når runden er låst.",
  off: "Slå på for å få en lenke du kan legge i gruppa. Den som åpner den, ser Tavla live i nettleseren, uten app.",
  renewQuestion: "Lage ny lenke? Den gamle lenken slutter å virke. Del den nye i gruppa.",
};

/** Feilene fra RPC-ene på norsk. Databasen gir egne norske tekster for 42501. */
export function sharingErrorText(error: { code?: string; message?: string }): string {
  if (error.code === "PGRST202" || error.code === "42883") return "Dette kan ikke brukes før databasen er oppdatert.";
  return plainErrorText(error);
}
