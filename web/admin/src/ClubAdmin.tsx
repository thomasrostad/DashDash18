import { useCallback, useEffect, useState } from "react";
import { committees as loadCommittees, competitions, events, members, type Competition, type EventRow, type Member, type Membership } from "./data.ts";
import { Schedule } from "./Schedule.tsx";
import { Roster } from "./Roster.tsx";
import { Standings } from "./standings/Standings.tsx";
import { errorText } from "./supabase.ts";
import { TournamentDetail } from "./TournamentDetail.tsx";
import { NewTournament } from "./NewTournament.tsx";
import { kindText, longDate, statusText } from "./text.ts";
import { legacyRights, rightsOf, visibleTabs, type Tab } from "./roles.ts";
import { clubRoles, type RoleData } from "./rolesApi.ts";
import { Roles } from "./Roles.tsx";
import { ClubSettings } from "./ClubSettings.tsx";

const TAB_TITLES: Record<Tab, string> = {
  turneringer: "Turneringer", terminliste: "Terminliste", tropp: "Tropp", tabeller: "Tabeller", roller: "Roller", klubb: "Klubb",
};

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
  /** Rollene (sql/044). Null: 044 ikke kjørt, og flaggene gjelder som før. */
  const [roleData, setRoleData] = useState<RoleData | null>(null);
  const viewer = roleData
    ? rightsOf(roleData.roles, roleData.assignments.filter((a) => a.member_id === membership.id).map((a) => a.role_id))
    : legacyRights(membership.is_organizer, false);
  const tabs = visibleTabs(viewer, roleData !== null);

  const load = useCallback(async () => {
    setError(null);
    try {
      const [c, e, m, k, r] = await Promise.all([competitions(clubID), events(clubID), members(clubID), loadCommittees(clubID),
        clubRoles(clubID).catch(() => null)]);
      setComps(c); setDays(e); setRoster(m); setCommittees(k); setRoleData(r);
    } catch (err) {
      setError(errorText(err));
    }
  }, [clubID]);

  useEffect(() => { load(); }, [load]);
  // Står du på en fane du ikke har (rollene er endret), gå til den første du har.
  const tabKey = tabs.join(",");
  useEffect(() => { if (tabs.length > 0 && !tabs.includes(tab)) setTab(tabs[0]); }, [tabKey, tab]);

  return (
    <main className="page">
      <nav className="tabs">
        {tabs.map((t) => (
          <button key={t} className={t === tab ? "tab active" : "tab"} onClick={() => setTab(t)}>
            {TAB_TITLES[t]}
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
        <NewTournament clubID={clubID} comps={comps} canTemplates={viewer.rights.has("tournaments")} onCancel={() => setCreating(false)}
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
        <Schedule clubID={clubID} days={days} comps={comps} roster={roster} committees={committees} onChanged={load}
          canTournaments={viewer.rights.has("tournaments")} canRounds={viewer.rights.has("rounds")} />
      ))}

      {tab === "tropp" && (!roster ? <p className="muted">Henter …</p> : (
        <Roster clubID={clubID} roster={roster} joinCode={membership.clubs.join_code} onChanged={load}
          roleData={roleData} viewer={viewer} myMemberID={membership.id} />
      ))}
      {tab === "tabeller" && (!comps ? <p className="muted">Henter …</p> : <Standings comps={comps} membership={membership} />)}
      {tab === "roller" && roleData && <Roles clubID={clubID} data={roleData} viewer={viewer} onChanged={load} />}
      {tab === "klubb" && <ClubSettings clubID={clubID} onSaved={() => load()} />}
    </main>
  );
}
