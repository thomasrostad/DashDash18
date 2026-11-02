import { useEffect, useRef, useState } from "react";
import type { Session } from "@supabase/supabase-js";
import { configError, supabase } from "./supabase.ts";
import { Landing } from "./landing/Landing.tsx";
import { startTopo } from "./landing/topo.ts";
import { ClubPicker } from "./ClubPicker.tsx";
import { ClubAdmin } from "./ClubAdmin.tsx";
import type { Membership } from "./data.ts";

const TOP_TOPO = { weak: "rgba(228,199,103,.10)", strong: "rgba(228,199,103,.24)", levels: 10, cx: 0.85, cy: 0.5, r: 0.35, speed: 0.003 };

/** Høydekurvene i toppen, svakere enn på forsiden. */
function TopTopo() {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => (ref.current ? startTopo(ref.current, TOP_TOPO) : undefined), []);
  return <canvas ref={ref} className="topo" aria-hidden="true" />;
}

/** Forsiden med innlogging → klubben → arrangørsiden. Samme bruker og tilganger som i appen. */
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
  if (!session) return <Landing />;

  return (
    <div className="shell">
      <header className="topbar">
        <TopTopo />
        <div className="bar">
          <span className="wordmark">Atten<i>.</i></span>
          {club && (
            <button className="link onDark club" onClick={() => setClub(null)}>
              {club.clubs.name} ▾
            </button>
          )}
          <span className="spacer" />
          <span className="muted onDark">{session.user.email}</span>
          <button className="link onDark" onClick={() => supabase.auth.signOut()}>Logg ut</button>
        </div>
      </header>
      {club ? <ClubAdmin membership={club} /> : <ClubPicker onPick={setClub} />}
    </div>
  );
}
