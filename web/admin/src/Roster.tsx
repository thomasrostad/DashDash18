import { useState } from "react";
import { addMember, updateMember, type Member, type MemberPatch } from "./data.ts";
import { errorText } from "./supabase.ts";
import { memberStatusText } from "./text.ts";
import { canGrant, type Rights } from "./roles.ts";
import { setMemberRoles, transferOwnership, type RoleData } from "./rolesApi.ts";

/** Troppen: godkjenne, roller, handicap og seeding, arkivere, legge til, og invitasjonslenken. */
export function Roster({ clubID, roster, joinCode, onChanged, roleData, viewer, myMemberID }: {
  clubID: string; roster: Member[]; joinCode: string | null; onChanged: () => void;
  /** Rollene (sql/044). Null: bryterne for arrangør og kasserer, som før. */
  roleData: RoleData | null; viewer: Rights; myMemberID: string;
}) {
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [name, setName] = useState("");
  const [hcp, setHcp] = useState("");
  const [copied, setCopied] = useState(false);
  const link = joinCode ? `https://dashdash18.com/klubb/${joinCode}` : null;

  async function patch(m: Member, p: MemberPatch) {
    setBusy(m.id); setError(null);
    try { await updateMember(clubID, m.id, p); onChanged(); } catch (e) { setError(errorText(e)); } finally { setBusy(null); }
  }

  async function run(m: Member, f: () => Promise<void>) {
    setBusy(m.id); setError(null);
    try { await f(); onChanged(); } catch (e) { setError(errorText(e)); } finally { setBusy(null); }
  }

  function roleIDs(memberID: string): string[] {
    return roleData ? roleData.assignments.filter((a) => a.member_id === memberID).map((a) => a.role_id) : [];
  }

  function toggleRole(m: Member, roleID: string, on: boolean) {
    const current = new Set(roleIDs(m.id));
    if (on) current.add(roleID); else current.delete(roleID);
    run(m, () => setMemberRoles(m.id, [...current]));
  }

  function rolesCell(m: Member) {
    if (!roleData) return (
      <>
        <label className="check"><input type="checkbox" checked={m.is_organizer} disabled={busy === m.id || m.status !== "active"}
          onChange={(e) => patch(m, { is_organizer: e.target.checked })} />Arrangør</label>
        <label className="check"><input type="checkbox" checked={m.is_treasurer} disabled={busy === m.id || m.status !== "active"}
          onChange={(e) => patch(m, { is_treasurer: e.target.checked })} />Kasserer</label>
      </>
    );
    const mine = new Set(roleIDs(m.id));
    const isOwner = roleData.roles.some((r) => r.is_owner && mine.has(r.id));
    return (
      <>
        {roleData.roles.map((r) => (
          <label key={r.id} className="check"><input type="checkbox" checked={mine.has(r.id)}
            disabled={busy === m.id || m.status !== "active" || !canGrant(viewer, r)}
            onChange={(e) => toggleRole(m, r.id, e.target.checked)} />{r.name}</label>
        ))}
        {viewer.isOwner && !isOwner && m.status === "active" && m.user_id && m.id !== myMemberID && (
          <button className="link" disabled={busy === m.id}
            onClick={() => confirm(`Gi eierskapet til ${m.display_name}? Du mister Eier, men beholder de andre rollene dine.`)
              && run(m, () => transferOwnership(clubID, m.id))}>Overfør eierskap</button>
        )}
      </>
    );
  }

  async function add(e: React.FormEvent) {
    e.preventDefault();
    const h = hcp.trim() === "" ? null : Number(hcp.replace(",", "."));
    if (h !== null && (Number.isNaN(h) || h < -10 || h > 54)) { setError("Handicap må være mellom −10 og 54."); return; }
    setBusy("new"); setError(null);
    try { await addMember(clubID, name, h); setName(""); setHcp(""); onChanged(); } catch (err) { setError(errorText(err)); } finally { setBusy(null); }
  }

  const order = { pending: 0, active: 1, archived: 2 } as Record<string, number>;
  const sorted = [...roster].sort((a, b) => (order[a.status] ?? 3) - (order[b.status] ?? 3) || a.display_name.localeCompare(b.display_name, "nb"));

  return (
    <section>
      {link && (
        <div className="card">
          <h3>Inviter spillere</h3>
          <p className="muted">Send lenken til gjengen. De som har appen, kommer rett inn i troppen.</p>
          <div className="inline">
            <code>{link}</code>
            <button className="link" onClick={() => { navigator.clipboard.writeText(link); setCopied(true); }}>{copied ? "Kopiert" : "Kopier"}</button>
          </div>
        </div>
      )}
      {error && <p className="error">{error}</p>}
      <table>
        <thead><tr><th>Navn</th><th>Handicap</th><th>Seeding</th><th>Roller</th><th>Status</th><th></th></tr></thead>
        <tbody>
          {sorted.map((m) => (
            <tr key={m.id} className={m.status === "archived" ? "past" : ""}>
              <td>
                <input className="cell" defaultValue={m.display_name} maxLength={40}
                  onBlur={(e) => { const v = e.target.value.trim(); if (v && v !== m.display_name) patch(m, { display_name: v }); }} />
                {!m.user_id && <span className="pill">Ledig navn</span>}
              </td>
              <td>
                <input className="cell num" defaultValue={m.handicap_index ?? ""} inputMode="decimal"
                  onBlur={(e) => {
                    const t = e.target.value.trim().replace(",", ".");
                    const v = t === "" ? null : Number(t);
                    if (v !== null && (Number.isNaN(v) || v < -10 || v > 54)) { setError("Handicap må være mellom −10 og 54."); return; }
                    if (v !== m.handicap_index) patch(m, { handicap_index: v });
                  }} />
              </td>
              <td>
                <select value={m.seed_group ?? ""} onChange={(e) => patch(m, { seed_group: e.target.value ? Number(e.target.value) : null })}>
                  <option value="">–</option>{[1, 2, 3, 4].map((g) => <option key={g} value={g}>{g}</option>)}
                </select>
              </td>
              <td>{rolesCell(m)}</td>
              <td>{memberStatusText(m.status)}</td>
              <td className="actions">
                {m.status === "pending" && <>
                  <button className="link" disabled={busy === m.id} onClick={() => patch(m, { status: "active" })}>Godkjenn</button>
                  <button className="link" disabled={busy === m.id} onClick={() => patch(m, { status: "archived", user_id: null })}>Avvis</button>
                </>}
                {m.status === "active" && <button className="link" disabled={busy === m.id}
                  onClick={() => confirm(`Arkivere ${m.display_name}?`) && patch(m, { status: "archived", is_organizer: false, is_treasurer: false })}>Arkiver</button>}
                {m.status === "archived" && <button className="link" disabled={busy === m.id} onClick={() => patch(m, { status: "active" })}>Gjenopprett</button>}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      <form className="card" onSubmit={add}>
        <h3>Legg til et navn</h3>
        <p className="muted">Navnet står ledig i troppen til spilleren logger inn i appen og velger det.</p>
        <div className="inline">
          <input placeholder="Navn" required maxLength={40} value={name} onChange={(e) => setName(e.target.value)} />
          <input placeholder="Handicap" inputMode="decimal" value={hcp} onChange={(e) => setHcp(e.target.value)} />
          <button className="primary" disabled={busy === "new" || !name.trim()}>Legg til</button>
        </div>
      </form>
    </section>
  );
}
