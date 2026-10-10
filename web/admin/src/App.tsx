import { useEffect, useState } from "react";
import type { Session } from "@supabase/supabase-js";
import { configError, supabase } from "./supabase.ts";
import { Login } from "./Login.tsx";
import { ClubPicker } from "./ClubPicker.tsx";
import { ClubAdmin } from "./ClubAdmin.tsx";
import type { Membership } from "./data.ts";

/** Innlogging → klubben → arrangørsiden. Samme bruker og tilganger som i appen. */
export function App() {
  const [session, setSession] = useState<Session | null | undefined>(undefined);
  const [club, setClub] = useState<Membership | null>(null);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSession(data.session));
    const { data } = supabase.auth.onAuthStateChange((_event, s) => setSession(s));
    return () => data.subscription.unsubscribe();
  }, []);

  if (configError) return <main className="center"><p className="error">{configError}</p></main>;
  if (session === undefined) return <main className="center"><p className="muted">Henter …</p></main>;
  if (!session) return <Login />;

  return (
    <div className="shell">
      <header className="topbar">
        <span className="brand">Atten · Arrangør</span>
        {club && (
          <button className="link onDark" onClick={() => setClub(null)}>
            {club.clubs.name} ▾
          </button>
        )}
        <span className="spacer" />
        <span className="muted onDark">{session.user.email}</span>
        <button className="link onDark" onClick={() => supabase.auth.signOut()}>Logg ut</button>
      </header>
      {club ? <ClubAdmin membership={club} /> : <ClubPicker onPick={setClub} />}
    </div>
  );
}
