import { useEffect, useState } from "react";
import { organizerClubs, type Membership } from "./data.ts";
import { errorText } from "./supabase.ts";

export function ClubPicker({ onPick }: { onPick: (m: Membership) => void }) {
  const [clubs, setClubs] = useState<Membership[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    organizerClubs().then((c) => {
      setClubs(c);
      if (c.length === 1) onPick(c[0]);
    }).catch((e) => setError(errorText(e)));
  }, [onPick]);

  if (error) return <main className="page"><p className="error">{error}</p></main>;
  if (!clubs) return <main className="page"><p className="muted">Henter klubbene …</p></main>;
  return (
    <main className="page">
      <h2>Velg klubb</h2>
      {clubs.length === 0 && <p className="muted">Du er ikke arrangør i noen klubb. Arrangørsiden finnes for arrangører; spør klubben om å få rollen.</p>}
      <ul className="list">
        {clubs.map((m) => (
          <li key={m.id}><button className="row" onClick={() => onPick(m)}>{m.clubs.name}<span className="muted">Arrangør · {m.display_name}</span></button></li>
        ))}
      </ul>
    </main>
  );
}
