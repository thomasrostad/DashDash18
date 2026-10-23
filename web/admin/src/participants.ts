// Deltakere uten innlogging i en klubbturnering (sql/059–061): arrangøren limer inn lista
// (`add_competition_participants`) og deler turneringens lenke (`competition_invite`), så hver deltaker
// tar plassen sin i appen. Som ParticipantInvite.swift og InviteTarget.competition. Ren logikk her; kallene
// står i participantsApi.ts.

import { LINK_DOMAIN } from "./sharing.ts";
import { plainErrorText } from "./text.ts";
import type { Competition } from "./data.ts";

/** Kan arrangøren legge inn deltakere? Klubbturnering (liga, cup, morro) med påmelding, ikke ferdig. */
export function canAddParticipants(c: Pick<Competition, "club_id" | "entry" | "kind" | "status">): boolean {
  return c.club_id !== null && c.entry === "listed" && (c.kind === "league" || c.kind === "cup" || c.kind === "fun")
    && c.status !== "finished";
}

/** «https://dashdash18.com/konkurranse/KODE». */
export function inviteURL(code: string): string {
  return `https://${LINK_DOMAIN}/konkurranse/${code}`;
}

/** «ABCDE-FGHJK»: lettere å lese høyt og skrive av. */
export function inviteDisplay(code: string): string {
  return code.length === 10 ? `${code.slice(0, 5)}-${code.slice(5)}` : code;
}

/** Teksten som deles med deltakerne (InviteTarget.competition med klubb). */
export function inviteShareText(competitionName: string, clubName: string, code: string): string {
  return `Bli med i ${competitionName} (${clubName}) i Atten. Står du på lista, tar du plassen din.\n`
    + `${inviteURL(code)}\n`
    + `Eller skriv inn koden ${inviteDisplay(code)} under Turneringer → «Har du en kode?».`;
}

export const INVITE_HELP =
  "Skann QR-koden med kameraet, eller trykk på lenken i meldingen. Uten lenke: skriv inn koden under "
  + "Turneringer → «Har du en kode?». Står navnet på lista, velger de det og tar plassen; ellers "
  + "meldes de på som nye deltakere. De blir deltakere i turneringen, ikke medlem i klubben. "
  + "Koden virker i 60 dager, og til turneringen er ferdig.";

export const AFTER_IMPORT_HELP = "Del lenken med deltakerne. De velger navnet sitt, lager en bruker i Atten og fører selv.";

/** Svaret fra competition_invite. */
export function inviteFromRow(row: { code?: unknown; expires_at?: unknown } | null): { code: string; expiresAt: string | null } {
  if (!row || typeof row.code !== "string") throw new Error("Serveren ga en ugyldig kode.");
  return { code: row.code, expiresAt: typeof row.expires_at === "string" ? row.expires_at : null };
}

/** Feilene fra RPC-ene. Databasen gir norske tekster («Høyst 300 om gangen», «Turneringen er ferdig»). */
export function participantErrorText(error: { code?: string; message?: string }): string {
  if (error.code === "PGRST202" || error.code === "42883") return "Dette kan ikke brukes før databasen er oppdatert.";
  return plainErrorText(error);
}
