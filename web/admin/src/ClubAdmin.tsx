import { useCallback, useEffect, useState } from "react";
import { committees as loadCommittees, competitions, events, members, type Competition, type EventRow, type Member, type Membership } from "./data.ts";
import { Schedule } from "./Schedule.tsx";
import { Roster } from "./Roster.tsx";
import { Standings } from "./standings/Standings.tsx";
import { errorText } from "./supabase.ts";
import { TournamentDetail } from "./TournamentDetail.tsx";
import { NewTournament } from "./NewTournament.tsx";
import { kindText, longDate, statusText } from "./text.ts";

type Tab = "turneringer" | "terminliste" | "tropp" | "tabeller";

/** Arrangørsiden for én klubb. Del 1: oversikt over turneringer, terminliste og tropp. */
export function ClubAdmin({ membership }: { membership: Membership }) {
  const clubID = membership.club_id;
  const [tab, setTab] = useState<Tab>("turneringer");
  const [comps, setComps] = useState<Competition[] | null>(null);
  const [days, setDays] = useState<EventRow[] | null>(null);
  const [roster, setRoster] = useState<Member[] | null>(null);
  const [committees, setCommittees] = useState<Record<string, string[]>>({});
  const [error, setError] = useState<string | null>(null);
  const [openID, setOpenID] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);

  const load = useCallback(async () => {
    setError(null);
    try {
      const [c, e, m, k] = await Promise.all([competitions(clubID), events(clubID), members(clubID), loadCommittees(clubID)]);
      setComps(c); setDays(e); setRoster(m); setCommittees(k);
    } catch (err) {
      setError(errorText(err));
    }
  }, [clubID]);

  useEffect(() => { load(); }, [load]);

  return (
    <main className="page">
      <nav className="tabs">
        {(["turneringer", "terminliste", "tropp", "tabeller"] as Tab[]).map((t) => (
          <button key={t} className={t === tab ? "tab active" : "tab"} onClick={() => setTab(t)}>
            {{ turneringer: "Turneringer", terminliste: "Terminliste", tropp: "Tropp", tabeller: "Tabeller" }[t]}
          </button>
        ))}
        <span className="spacer" />
        <button className="link" onClick={load}>Oppdater</button>
      </nav>
      {error && <p className="error">{error}</p>}

      {tab === "turneringer" && openID && comps && roster && comps.find((c) => c.id === openID) && (
        <TournamentDetail competition={comps.find((c) => c.id === openID)!} roster={roster}
          onBack={() => setOpenID(null)} onChanged={load} />
      )}

      {tab === "turneringer" && creating && comps && (
        <NewTournament clubID={clubID} comps={comps} onCancel={() => setCreating(false)}
          onDone={() => { setCreating(false); load(); }} />
      )}

      {tab === "turneringer" && !openID && !creating && (
        <section>
          <div className="inline"><button className="primary" onClick={() => setCreating(true)}>Ny turnering</button></div>
          {!comps ? <p className="muted">Henter …</p> : comps.length === 0 ? <p className="muted">Ingen turneringer ennå.</p> : (
            <table>
              <thead><tr><th>Navn</th><th>Type</th><th>Status</th><th>Periode</th><th>Påmelding</th></tr></thead>
              <tbody>
                {comps.map((c) => (
                  <tr key={c.id} className="click" onClick={() => setOpenID(c.id)}>
                    <td><strong>{c.name}</strong>{c.is_main && <span className="pill">Hovedturnering</span>}{c.auto_count && <span className="pill">Spill når det passer</span>}</td>
                    <td>{kindText(c.kind)}</td>
                    <td>{statusText(c.status)}</td>
                    <td>{c.starts_on ? `${longDate(c.starts_on)}${c.ends_on ? ` – ${longDate(c.ends_on)}` : ""}` : "–"}</td>
                    <td>{c.signup_open ? "Åpen" : "–"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </section>
      )}

      {tab === "terminliste" && (!days || !comps || !roster ? <p className="muted">Henter …</p> : (
        <Schedule clubID={clubID} days={days} comps={comps} roster={roster} committees={committees} onChanged={load} />
      ))}

      {tab === "tropp" && (!roster ? <p className="muted">Henter …</p> : (
        <Roster clubID={clubID} roster={roster} joinCode={membership.clubs.join_code} onChanged={load} />
      ))}
      {tab === "tabeller" && (!comps ? <p className="muted">Henter …</p> : <Standings comps={comps} membership={membership} />)}
    </main>
  );
}
