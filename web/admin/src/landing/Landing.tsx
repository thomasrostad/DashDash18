import { useEffect, useRef, useState, type ReactNode } from "react";
import { SignIn } from "../SignIn.tsx";
import { DemoTavla } from "./DemoTavla.tsx";
import { startShade } from "./shade.ts";
import { startTopo } from "./topo.ts";
import "./landing.css";

const still = () => matchMedia("(prefers-reduced-motion: reduce)").matches;

/** Legger på klassen `in` første gang elementet er synlig. */
function useInView<T extends HTMLElement>(threshold = 0.25) {
  const ref = useRef<T>(null);
  const [seen, setSeen] = useState(false);
  useEffect(() => {
    const el = ref.current;
    if (!el || seen) return;
    const io = new IntersectionObserver((es) => { if (es.some((e) => e.isIntersecting)) { setSeen(true); io.disconnect(); } }, { threshold });
    io.observe(el);
    return () => io.disconnect();
  }, [seen, threshold]);
  return [ref, seen] as const;
}

function Topo({ options }: { options: Parameters<typeof startTopo>[1] }) {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => (ref.current ? startTopo(ref.current, options) : undefined), [options]);
  return <canvas ref={ref} className="topo" aria-hidden="true" />;
}
const HERO_TOPO = { weak: "rgba(228,199,103,.19)", strong: "rgba(228,199,103,.46)", levels: 18, cx: 0.7, cy: 0.55, r: 0.42 };
const CLOSE_TOPO = { weak: "rgba(228,199,103,.10)", strong: "rgba(228,199,103,.26)", levels: 14, cx: 0.8, cy: 0.4, r: 0.5, speed: 0.003 };

/** Setningen som leses fram ord for ord mens man scroller. */
function ReadingLine({ children }: { children: ReactNode }) {
  const ref = useRef<HTMLParagraphElement>(null);
  useEffect(() => {
    const p = ref.current;
    if (!p) return;
    const words = [...p.querySelectorAll<HTMLElement>(".w")];
    if (still()) { words.forEach((w) => w.classList.add("on")); return; }
    let raf = 0;
    const update = () => {
      raf = 0;
      const r = p.getBoundingClientRect();
      const start = innerHeight * 0.85, end = innerHeight * 0.35;
      const t = Math.min(1, Math.max(0, (start - r.top) / (start - end + r.height * 0.6)));
      const n = Math.round(t * words.length);
      words.forEach((w, i) => w.classList.toggle("on", i < n));
    };
    const onScroll = () => { if (!raf) raf = requestAnimationFrame(update); };
    addEventListener("scroll", onScroll, { passive: true });
    update();
    return () => { removeEventListener("scroll", onScroll); cancelAnimationFrame(raf); };
  }, []);
  return <p ref={ref} className="read">{children}</p>;
}
const words = (text: string) => text.split(/(\s+)/).map((w, i) => (/^\s+$/.test(w) ? w : <span key={i} className="w">{w}</span>));

function PhoneCard() {
  const [ref, seen] = useInView<HTMLElement>(0.6);
  const [score, setScore] = useState(4);
  const [tap, setTap] = useState(false);
  useEffect(() => {
    if (!seen || still()) return;
    const timers: ReturnType<typeof setTimeout>[] = [];
    const run = () => {
      timers.push(setTimeout(() => { setTap(true); timers.push(setTimeout(() => { setTap(false); setScore(3); }, 150)); }, 900));
      timers.push(setTimeout(() => setScore(4), 5200));
    };
    run();
    const loop = setInterval(run, 6400);
    return () => { clearInterval(loop); timers.forEach(clearTimeout); };
  }, [seen]);
  return (
    <article ref={ref} className="kcard">
      <p className="eb">Appen</p>
      <h3>Spillerne fører selv. <em>Poengene er regnet før neste tee.</em></h3>
      <div className="art">
        <div className="phone"><div className="pscr">
          <div className="top"><span>Losby · gul</span><span>Hull 7 av 18</span></div>
          <div className="hole">Par 4 · 352 m · idx 3<b>Kari</b></div>
          <div key={score} className={score === 3 ? "score pop" : "score"}>{score}</div>
          <div className="pm"><span className={tap ? "tap" : ""}>−</span><span className="on">+</span></div>
        </div></div>
      </div>
    </article>
  );
}

function RosterCard() {
  const [ref, seen] = useInView<HTMLElement>(0.6);
  const rows: [string, string, boolean][] = [["Kari Moen", "12,4", true], ["Jonas Lie", "22,7", false], ["Marte Lunde", "18,0", true], ["Jon Berg", "6,3", true]];
  return (
    <article ref={ref} className={seen ? "kcard in" : "kcard"}>
      <p className="eb">Troppen</p>
      <h3>Lim inn lista fra regnearket. <em>Resten ordner seg.</em></h3>
      <div className="art">
        <p className="paste">Har de appen, kobles de. Ellers får de en lenke.</p>
        <div className="plist">
          {rows.map(([n, h, app], i) => (
            <div key={n} style={{ transitionDelay: `${250 + i * 220}ms` }}><span>{n}</span><span className="h">{h}</span><em className={app ? "" : "inv"}>{app ? "Koblet" : "Lenke sendt"}</em></div>
          ))}
        </div>
      </div>
    </article>
  );
}

function CourseCard() {
  const [ref, seen] = useInView<HTMLElement>(0.6);
  const par = [4, 5, 3, 4, 4, 3, 5, 4, 4];
  return (
    <article ref={ref} className={seen ? "kcard img in" : "kcard img"}>
      <img src="/landing/fairway.jpg" alt="Klippet fairway med dugg om morgenen" loading="lazy" />
      <p className="eb">Baner</p>
      <h3>Fra slope.no, <em>eller egne baner i simulatoren.</em></h3>
      <div className="art">
        <div className="course">
          <div className="h"><b>Losby, gul tee</b><span>Par 72 · slope 128</span></div>
          <div className="holes">{par.map((p, i) => <i key={i} className={p === 3 ? "p3" : p === 5 ? "p5" : ""} style={{ transitionDelay: `${i * 50}ms` }}>{p}</i>)}</div>
        </div>
      </div>
    </article>
  );
}

function SimCard() {
  const [ref, seen] = useInView<HTMLElement>(0.6);
  return (
    <article ref={ref} className={seen ? "kcard dark in" : "kcard dark"}>
      <p className="eb">Simulatorsentre</p>
      <h3>Ligaen i båsen <em>får sin egen tavle.</em></h3>
      <div className="art simart">
        <div className="code">{"K7HQ".split("").map((c, i) => <span key={i} style={{ transitionDelay: `${i * 70}ms` }}>{c}</span>)}</div>
        <p>Koden på skjermen i lokalet. Trackman fordeler slagene.</p>
        <div className="bays"><i className="on" /><i className="on" /><i className="on" /><i className="on" /><i /><i /></div>
      </div>
    </article>
  );
}

function RulesCard() {
  return (
    <article className="kcard">
      <p className="eb">Reglene</p>
      <h3>Regnet likt <em>i appen, på web og på TV.</em></h3>
      <div className="art rules">
        <div><b>Spillform</b><span>Stableford</span></div>
        <div><b>Teller</b><span>Beste 6 av 10</span></div>
        <div><b>Handicapandel</b><span>95 %</span></div>
        <div><b>Sidepremier</b><span>Lengste drive, nærmest</span></div>
      </div>
    </article>
  );
}

function Rail() {
  const rail = useRef<HTMLDivElement>(null);
  const [edge, setEdge] = useState({ start: true, end: false });
  useEffect(() => {
    const el = rail.current;
    if (!el) return;
    const update = () => setEdge({ start: el.scrollLeft < 8, end: el.scrollLeft + el.clientWidth >= el.scrollWidth - 8 });
    el.addEventListener("scroll", update, { passive: true });
    addEventListener("resize", update);
    update();
    return () => { el.removeEventListener("scroll", update); removeEventListener("resize", update); };
  }, []);
  const by = (dir: number) => {
    const el = rail.current, card = el?.querySelector(".kcard");
    if (el && card) el.scrollBy({ left: dir * (card.getBoundingClientRect().width + 20), behavior: still() ? "auto" : "smooth" });
  };
  return (
    <>
      <div className="rail" ref={rail}><PhoneCard /><RosterCard /><CourseCard /><SimCard /><RulesCard /></div>
      <div className="wrap paddles">
        <button type="button" onClick={() => by(-1)} disabled={edge.start} aria-label="Forrige"><svg viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M9 2 4 7l5 5" /></svg></button>
        <button type="button" onClick={() => by(1)} disabled={edge.end} aria-label="Neste"><svg viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="m5 2 5 5-5 5" /></svg></button>
      </div>
    </>
  );
}

function Shade() {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => (ref.current ? startShade(ref.current) : undefined), []);
  return <canvas ref={ref} className="shade" aria-hidden="true" />;
}

function CopyMail() {
  const [label, setLabel] = useState("Kopier e-post");
  const addr = useRef<HTMLSpanElement>(null);
  async function copy() {
    try { await navigator.clipboard.writeText("hei@dashdash18.com"); setLabel("Kopiert"); }
    catch {
      const r = document.createRange();
      if (addr.current) { r.selectNodeContents(addr.current); const s = getSelection(); s?.removeAllRanges(); s?.addRange(r); }
      setLabel("Markert");
    }
    setTimeout(() => setLabel("Kopier e-post"), 2000);
  }
  return <div className="mailrow"><span className="addr" ref={addr}>hei@dashdash18.com</span><button className="primary" type="button" onClick={copy}>{label}</button></div>;
}

/** Forsiden før innlogging: selger Atten til klubber og sentre, og lar arrangørene logge inn med en gang. */
export function Landing() {
  const [photo, setPhoto] = useState(0);
  const photoBox = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (still()) return;
    let raf = 0;
    const update = () => {
      raf = 0;
      const el = photoBox.current;
      if (!el) return;
      const r = el.getBoundingClientRect();
      if (r.bottom > 0 && r.top < innerHeight) setPhoto((r.top + r.height / 2 - innerHeight / 2) / innerHeight * -40);
    };
    const onScroll = () => { if (!raf) raf = requestAnimationFrame(update); };
    addEventListener("scroll", onScroll, { passive: true });
    return () => { removeEventListener("scroll", onScroll); cancelAnimationFrame(raf); };
  }, []);

  return (
    <div className="landing">
      <header className="hero">
        <Topo options={HERO_TOPO} />
        <div className="pin" aria-hidden="true"><i /><span>Green 7 · fall 2,1 %</span></div>
        <nav className="lnav"><div className="wrap">
          <span className="wordmark">Atten<i>.</i></span>
          <span className="spacer" />
          <a className="n hide-s" href="#bli-kjent">Bli kjent</a>
          <a className="n" href="#ny">Ny klubb eller senter</a>
        </div></nav>
        <div className="wrap">
          <div className="first">
            <div className="pitch">
              <p className="name in-1"><b>Atten Arrangør</b> · for klubber og simulatorsentre</p>
              <h1>
                <span className="loud"><span className="ln"><span>Tabellen</span></span><span className="ln"><span>er ferdig</span></span></span>
                <span className="soft in-2">før dere er i baren.</span>
              </h1>
              <p className="sub in-3">Serier, cuper og simulatorligaer, satt opp fra PC-en. Spillerne fører i appen, og tavla på TV-en oppdaterer seg mens de spiller.</p>
              <div className="in-4"><SignIn /></div>
              <p className="new in-4">Ny klubb eller senter? <a href="#ny">Se hvordan det virker</a></p>
            </div>
            <div className="in-3"><DemoTavla /></div>
          </div>
        </div>
      </header>

      <section className="morning">
        <Shade />
        <div className="wrap">
          <ReadingLine>
            {words("Klubbkvelden fortjener bedre enn et regneark som blir ferdig klokka ett om natta. Med Atten fører spillerne selv, regelmotoren regner, og ")}
            <span className="soft">{words("tavla står på skjermen")}</span>
            {words(" før siste putt er holet.")}
          </ReadingLine>
          <p className="by">Atten Arrangør. Laget for de som sitter igjen med lista.</p>
        </div>
      </section>

      <section className="know" id="bli-kjent">
        <div className="wrap"><h2><span className="loud">Bli kjent med</span><span className="soft">Arrangør.</span></h2></div>
        <Rail />
      </section>

      <div className="photo" ref={photoBox}>
        <img src="/landing/kveld.jpg" alt="Tre golfere skåler på banen etter runden" loading="lazy" style={{ transform: `translateY(${photo}px)` }} />
        <div className="wrap">
          <p className="t">Onsdag, <b>21.47</b>. Siste flight er inne.</p>
          <p className="s">Kari vant kvelden med 38 poeng, og alle visste det før de hadde tatt av seg skoene.</p>
        </div>
      </div>

      <section className="close" id="ny">
        <Topo options={CLOSE_TOPO} />
        <div className="wrap">
          <div>
            <h2><span className="loud">Ny klubb</span><span className="soft">eller senter?</span></h2>
            <p>Skriv til oss, så viser vi hvordan en sesong ser ut i Atten.</p>
          </div>
          <CopyMail />
        </div>
      </section>
      <footer className="lfoot"><div className="wrap"><span>Atten er laget av DashDash18 i Oslo.</span><span>Foto: Sugar Golf og FilterGrade på Unsplash</span></div></footer>
    </div>
  );
}
