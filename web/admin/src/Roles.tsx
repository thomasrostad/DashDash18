import { useState } from "react";
import { RIGHT_TITLES, RIGHTS, roleNameError, roleRights, type ClubRole, type Rights } from "./roles.ts";
import { deleteRole, saveRole, type RoleData } from "./rolesApi.ts";
import { errorText } from "./supabase.ts";

/** Roller (sql/044): eieren lager, gir nytt navn, endrer rettigheter og sletter roller. Eiers rettigheter står fast. */
export function Roles({ clubID, data, viewer, onChanged }: {
  clubID: string; data: RoleData; viewer: Rights; onChanged: () => void;
}) {
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [name, setName] = useState("");
  const [rights, setRights] = useState<Set<string>>(new Set());
  const canEdit = viewer.isOwner;
  const count = (id: string) => data.assignments.filter((a) => a.role_id === id).length;

  async function run(f: () => Promise<void>) {
    setBusy(true); setError(null);
    try { await f(); onChanged(); } catch (e) { setError(errorText(e)); } finally { setBusy(false); }
  }

  function toggle(role: ClubRole, right: string, on: boolean) {
    const next = new Set(roleRights(role) as Set<string>);
    if (on) next.add(right); else next.delete(right);
    run(() => saveRole(clubID, role.id, role.name, [...next]));
  }

  function rename(role: ClubRole, value: string) {
    const v = value.trim();
    if (v === role.name) return;
    const err = roleNameError(v, data.roles, role.id);
    if (err) { setError(err); return; }
    run(() => saveRole(clubID, role.id, v, role.is_owner ? null : [...roleRights(role)]));
  }

  function create(e: React.FormEvent) {
    e.preventDefault();
    const err = roleNameError(name, data.roles, null);
    if (err) { setError(err); return; }
    run(async () => { await saveRole(clubID, null, name, [...rights]); setName(""); setRights(new Set()); });
  }

  return (
    <section>
      {error && <p className="error">{error}</p>}
      <table>
        <thead><tr><th>Rolle</th>{RIGHTS.map((r) => <th key={r}>{RIGHT_TITLES[r]}</th>)}<th>Medlemmer</th><th></th></tr></thead>
        <tbody>
          {data.roles.map((role) => (
            <tr key={role.id}>
              <td>
                {canEdit
                  ? <input className="cell" defaultValue={role.name} maxLength={40} disabled={busy} onBlur={(e) => rename(role, e.target.value)} />
                  : <strong>{role.name}</strong>}
                {role.is_owner && <span className="pill">Alle rettigheter</span>}
              </td>
              {RIGHTS.map((r) => (
                <td key={r}>
                  <input type="checkbox" aria-label={RIGHT_TITLES[r]} checked={roleRights(role).has(r)}
                    disabled={!canEdit || role.is_owner || busy} onChange={(e) => toggle(role, r, e.target.checked)} />
                </td>
              ))}
              <td>{count(role.id)}</td>
              <td className="actions">
                {canEdit && !role.is_owner && (
                  <button className="link" disabled={busy || count(role.id) > 0}
                    title={count(role.id) > 0 ? "Ta rollen fra medlemmene i Tropp først." : undefined}
                    onClick={() => confirm(`Slette «${role.name}»?`) && run(() => deleteRole(role.id))}>Slett</button>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      {canEdit && (
        <form className="card" onSubmit={create}>
          <h3>Ny rolle</h3>
          <p className="muted">Uten rettigheter er rollen et merke, som Sosialkomité.</p>
          <div className="inline">
            <input placeholder="Navn" required maxLength={40} value={name} onChange={(e) => setName(e.target.value)} />
            {RIGHTS.map((r) => (
              <label key={r} className="check">
                <input type="checkbox" checked={rights.has(r)} onChange={(e) => {
                  const next = new Set(rights); if (e.target.checked) next.add(r); else next.delete(r); setRights(next);
                }} />{RIGHT_TITLES[r]}
              </label>
            ))}
            <button className="primary" disabled={busy || !name.trim()}>Lag rolle</button>
          </div>
        </form>
      )}
    </section>
  );
}
