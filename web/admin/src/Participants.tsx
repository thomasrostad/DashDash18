import { useEffect, useState } from "react";
import { ListImport } from "./ListImport.tsx";
import { PARTICIPANT_IMPORT_HELP, parseParticipantList, participantEntries, participantsAddedText } from "./listImport.ts";
import { AFTER_IMPORT_HELP, INVITE_HELP, inviteDisplay, inviteShareText, inviteURL } from "./participants.ts";
import { addParticipants, competitionInvite, enteredNames, revokeCompetitionInvite } from "./participantsApi.ts";
import { displayURL } from "./sharing.ts";
import { errorText } from "./supabase.ts";
import type { Competition } from "./data.ts";

/** Deltakere uten innlogging (sql/060): lim inn lista og del lenken, som ParticipantInviteRows i appen. */
export function Participants({ competition, clubName, onChanged }: {
  competition: Competition; clubName: string; onChanged: () => void;
}) {
  const [entered, setEntered] = useState<string[]>([]);

  // En feil her gir ingen melding: da sjekkes lista bare mot seg selv, og serveren hopper over dem som er
  // påmeldt med samme NGF-nummer (som i appen).
  useEffect(() => {
    let live = true;
    enteredNames(competition.id).then((n) => { if (live) setEntered(n); }).catch(() => {});
    return () => { live = false; };
  }, [competition.id]);

  return (
    <div className="grid2">
      <ListImport title="Legg til deltakere (lim inn liste)" participants
        intro="Fra e-post, GolfBox eller et regneark. De blir deltakere, ikke medlemmer."
        help={PARTICIPANT_IMPORT_HELP} parse={(text) => parseParticipantList(text, entered)}
        onAdd={async (lines) => {
          const n = await addParticipants(competition.id, participantEntries(lines));
          setEntered(await enteredNames(competition.id).catch(() => entered));
          onChanged();
          return participantsAddedText(n);
        }}>
        <p className="muted">{AFTER_IMPORT_HELP}</p>
      </ListImport>
      <InviteCard competition={competition} clubName={clubName} />
    </div>
  );
}

/** «Del lenken til turneringen»: lenken, koden og teksten som deles, med «Ny kode» og «Trekk tilbake». */
function InviteCard({ competition, clubName }: { competition: Competition; clubName: string }) {
  const [code, setCode] = useState<string | null>(null);
  const [shown, setShown] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  async function run(action: () => Promise<void>, done?: string) {
    setBusy(true); setError(null); setNotice(null);
    try { await action(); if (done) setNotice(done); }
    catch (e) { setError(errorText(e)); }
    finally { setBusy(false); }
  }

  return (
    <div className="card">
      <h3>Lenken til turneringen</h3>
      <p className="muted">Deltakerne tar plassen sin og lager en bruker i Atten.</p>
      {code && (
        <>
          <p className="big-code">{inviteDisplay(code)}</p>
          <p><a href={inviteURL(code)} target="_blank" rel="noreferrer"><code>{displayURL(inviteURL(code))}</code></a></p>
          <p className="muted">{INVITE_HELP}</p>
        </>
      )}
      {shown && !code && !busy && <p className="muted">Ingen kode. Lag en ny for å dele turneringen.</p>}
      <div className="inline">
        {code && (
          <button type="button" className="primary" disabled={busy}
            onClick={() => run(() => navigator.clipboard.writeText(inviteShareText(competition.name, clubName, code)), "Teksten med lenken er kopiert.")}>
            Kopier teksten
          </button>
        )}
        {!shown ? (
          <button type="button" className="primary" disabled={busy}
            onClick={() => run(async () => { setCode((await competitionInvite(competition.id)).code); setShown(true); })}>Vis lenken</button>
        ) : (
          <button type="button" className="tab" disabled={busy}
            onClick={() => (!code || confirm("Lage ny kode? Den gamle lenken slutter å virke."))
              && run(async () => setCode((await competitionInvite(competition.id, code !== null)).code), code ? "Ny kode laget. Den gamle virker ikke lenger." : undefined)}>
            {code ? "Ny kode" : "Lag kode"}
          </button>
        )}
        {code && (
          <button type="button" className="link" disabled={busy}
            onClick={() => confirm("Trekke tilbake koden? De påmeldte er fortsatt med.")
              && run(async () => { await revokeCompetitionInvite(competition.id); setCode(null); }, "Koden er trukket tilbake.")}>
            Trekk tilbake
          </button>
        )}
      </div>
      {error && <p className="error">{error}</p>}
      {notice && <p className="ok">{notice}</p>}
    </div>
  );
}
