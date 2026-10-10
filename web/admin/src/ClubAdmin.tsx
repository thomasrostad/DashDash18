import { useCallback, useEffect, useState } from "react";
import { competitions, events, members, type Competition, type EventRow, type Member, type Membership } from "./data.ts";
import { errorText } from "./supabase.ts";
import { TournamentDetail } from "./TournamentDetail.tsx";
import { kindText, longDate, memberStatusText, statusText, timeText, todayISO } from "./text.ts";

type Tab = "turneringer" | "terminliste" | "tropp";

/** Arrangørsiden for én klubb. Del 1: oversikt over turneringer, terminliste og tropp. */
export function ClubAdmin({ membership }: { membership: Membership }) {
  const clubID = membership.club_id;
  const [tab, setTab] = useState<Tab>("turneringer");
  const [comps, setComps] = useState<Competition[] | null>(null);
  const [days, setDays] = useState<EventRow[] | null>(null);
  const [roster, setRoster] = useState<Member[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [openID, setOpenID] = useState<string | null>(null);

  const load = useCallback(async () => {
    setError(null);
    try {
      const [c, e, m] = await Promise.all([competitions(clubID), events(clubID), members(clubID)]);
      setComps(c); setDays(e); setRoster(m);
    } catch (err) {
      setError(errorText(err));
    }
  }, [clubID]);

  useEffect(() => { load(); }, [load]);

  const nameOf = (e: EventRow) =>
    comps?.find((c) => (e.season_id && c.season_id === e.season_id) || (e.competition_id && c.id === e.competition_id))?.name ?? "Klubbens egen";

  return (
    <main className="page">
      <nav className="tabs">
        {(["turneringer", "terminliste", "tropp"] as Tab[]).map((t) => (
          <button key={t} className={t === tab ? "tab active" : "tab"} onClick={() => setTab(t)}>
            {{ turneringer: "Turneringer", terminliste: "Terminliste", tropp: "Tropp" }[t]}
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

      {tab === "turneringer" && !openID && (
        <section>
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

      {tab === "terminliste" && (
        <section>
          {!days ? <p className="muted">Henter …</p> : days.length === 0 ? <p className="muted">Ingen kvelder eller spilledager ennå.</p> : (
            <table>
              <thead><tr><th>Dato</th><th>Tid</th><th>Sted</th><th>Turnering</th><th>Notat</th></tr></thead>
              <tbody>
                {days.map((e) => (
                  <tr key={e.id} className={e.event_date < todayISO() ? "past" : ""}>
                    <td>{longDate(e.event_date)}</td>
                    <td>{timeText(e.start_time) ?? "–"}</td>
                    <td>{e.venue ?? "–"}</td>
                    <td>{nameOf(e)}</td>
                    <td className="muted">{e.note ?? ""}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </section>
      )}

      {tab === "tropp" && (
        <section>
          {!roster ? <p className="muted">Henter …</p> : (
            <>
              <p className="muted">{roster.filter((m) => m.status === "active").length} aktive · invitasjonskode <code>{membership.clubs.join_code ?? "–"}</code></p>
              <table>
                <thead><tr><th>Navn</th><th>Handicap</th><th>Seeding</th><th>Roller</th><th>Status</th></tr></thead>
                <tbody>
                  {roster.map((m) => (
                    <tr key={m.id} className={m.status === "archived" ? "past" : ""}>
                      <td>{m.display_name}{!m.user_id && <span className="pill">Ledig navn</span>}</td>
                      <td>{m.handicap_index ?? "–"}</td>
                      <td>{m.seed_group ?? "–"}</td>
                      <td>{[m.is_organizer && "Arrangør", m.is_treasurer && "Kasserer"].filter(Boolean).join(", ") || "–"}</td>
                      <td>{memberStatusText(m.status)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </>
          )}
        </section>
      )}
    </main>
  );
}
