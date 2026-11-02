import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { applyDemoEvent, DEMO_EVENTS, DEMO_PLAYERS, type DemoEvent } from "./demo.ts";

const still = () => matchMedia("(prefers-reduced-motion: reduce)").matches;

/** Tavla på TV-en, med eksempeldata. Hvert niende sekund kommer en score inn, og tabellen sorterer seg på nytt. */
export function DemoTavla() {
  const [players, setPlayers] = useState(DEMO_PLAYERS);
  const [toast, setToast] = useState<DemoEvent | null>(null);
  const [bumped, setBumped] = useState<string | null>(null);
  const [shown, setShown] = useState(() => still());
  const [clock, setClock] = useState(() => new Date());
  const rows = useRef(new Map<string, HTMLTableRowElement>());
  const before = useRef(new Map<string, number>());

  useEffect(() => {
    const id = setInterval(() => setClock(new Date()), 15000);
    if (still()) return () => clearInterval(id);
    const appear = setTimeout(() => setShown(true), 300);
    let n = 0;
    let inner: ReturnType<typeof setTimeout> | undefined;
    const tick = () => {
      const e = DEMO_EVENTS[n++ % DEMO_EVENTS.length];
      setToast(e);
      inner = setTimeout(() => {
        before.current = new Map([...rows.current].map(([k, el]) => [k, el.getBoundingClientRect().top]));
        setBumped(e.name);
        setPlayers((p) => applyDemoEvent(p, e));
        inner = setTimeout(() => { setToast(null); setBumped(null); }, 2400);
      }, 1000);
    };
    const first = setTimeout(() => { tick(); loop = setInterval(tick, 9000); }, 4000);
    let loop: ReturnType<typeof setInterval> | undefined;
    return () => { clearInterval(id); clearTimeout(appear); clearTimeout(first); clearTimeout(inner); clearInterval(loop); };
  }, []);

  // Radene glir til sin nye plass (FLIP).
  useLayoutEffect(() => {
    if (before.current.size === 0) return;
    for (const [name, el] of rows.current) {
      const dy = (before.current.get(name) ?? 0) - el.getBoundingClientRect().top;
      if (!dy) continue;
      el.style.transition = "none";
      el.style.transform = `translateY(${dy}px)`;
      requestAnimationFrame(() => requestAnimationFrame(() => { el.style.transition = ""; el.style.transform = ""; }));
    }
    before.current = new Map();
  }, [players]);

  const hhmm = `${String(clock.getHours()).padStart(2, "0")}.${String(clock.getMinutes()).padStart(2, "0")}`;
  return (
    <div className="screen">
      <div className="tv" aria-label="Eksempel på tavla på TV-en">
        <div className="scr">
          <div className="bar"><span>Runde 7 av 10 · eksempel</span><b>Live {hhmm}</b></div>
          <div className="ttl"><span className="loud">Høstserien</span><span className="soft">beste 6 av 10, Stableford</span></div>
          <table>
            <thead><tr><th></th><th>Spiller</th><th className="r">Poeng</th></tr></thead>
            <tbody>
              {players.map((p, i) => (
                <tr key={p.name} ref={(el) => { if (el) rows.current.set(p.name, el); else rows.current.delete(p.name); }}
                  className={[i === 0 ? "lead" : "", bumped === p.name ? "bump" : "", shown ? "" : "pre"].join(" ").trim()}
                  style={shown ? { transitionDelay: `${i * 90}ms` } : undefined}>
                  <td className="pl">{i + 1}</td>
                  <td className="nm">{p.name}<span className="rd">{p.rounds.map((r, j) => <i key={j} className={j === 6 ? "x" : ""}>{r}</i>)}</span></td>
                  <td className="r pts">{p.points}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <div className={toast ? "toast in" : "toast"} aria-live="polite">
            {toast && <><span>{toast.name} · hull {toast.hole}</span><i>{toast.what}, +{toast.add}</i></>}
          </div>
        </div>
      </div>
      <div className="stand" />
      <p className="cap"><em>Tavla på TV-en i klubbhuset.</em> Åpnes med en kode på fire tegn.</p>
    </div>
  );
}
