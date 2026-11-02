import { useEffect, useRef, useState } from "react";
import { SignIn } from "../SignIn.tsx";
import { ARRANGOR_BY, ARRANGOR_CARDS, ARRANGOR_HERO, ARRANGOR_READING, demoTavla, PHOTO_CREDIT, photoBand, rail, readingLine } from "./markup.ts";
import { startLanding } from "./live.ts";
import { startShade } from "./shade.ts";
import { LANDING_STYLE } from "./style.ts";
import { CLOSE_TOPO, HERO_TOPO, startTopo } from "./topo.ts";
import { SITE } from "../../../atten-lenker/src/html.ts";
import { MENU_STYLE, siteMenu } from "../../../atten-lenker/src/meny.ts";

function Topo({ options }: { options: Parameters<typeof startTopo>[1] }) {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => (ref.current ? startTopo(ref.current, options) : undefined), [options]);
  return <canvas ref={ref} className="topo" aria-hidden="true" />;
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
const SITE_MENU = siteMenu({ base: SITE, login: "#signin-email" });

// Tavla, kortene, setningen og fotoet er fast HTML fra koden (markup.ts, samme som dashdash18.com/for-klubber),
// ingen brukerdata. Bevegelsen settes i gang av live.ts.
const TAVLA = demoTavla();
const RAIL = rail(ARRANGOR_CARDS, "Bli kjent med Arrangør");
const READING = readingLine(ARRANGOR_READING);
const PHOTO = photoBand();

export function Landing() {
  const root = useRef<HTMLDivElement>(null);
  useEffect(() => (root.current ? startLanding(root.current) : undefined), []);

  return (
    <div className="landing" ref={root}>
      <style>{LANDING_STYLE}</style>
      <header className="hero">
        <Topo options={HERO_TOPO} />
        <div className="pin" aria-hidden="true"><i /><span>Green 7 · fall 2,1 %</span></div>
        {/* Samme meny som dashdash18.com (atten-lenker/src/meny.ts). Fast HTML fra koden, ingen brukerdata. */}
        <style>{MENU_STYLE}</style>
        <div className="lnav" dangerouslySetInnerHTML={{ __html: SITE_MENU }} />
        <div className="wrap">
          <div className="first">
            <div className="pitch">
              <p className="name in-1"><b>{ARRANGOR_HERO.eyebrow}</b> · {ARRANGOR_HERO.eyebrowRest}</p>
              <h1>
                <span className="loud">{ARRANGOR_HERO.loud.map((l) => <span className="ln" key={l}><span>{l}</span></span>)}</span>
                <span className="soft in-2">{ARRANGOR_HERO.soft}</span>
              </h1>
              <p className="sub in-3">{ARRANGOR_HERO.ingress}</p>
              <div className="in-4"><SignIn /></div>
              <p className="new in-4">Ny klubb eller senter? <a href="#ny">Se hvordan det virker</a></p>
            </div>
            <div className="in-3" dangerouslySetInnerHTML={{ __html: TAVLA }} />
          </div>
        </div>
      </header>

      <section className="morning">
        <Shade />
        <div className="wrap">
          <div dangerouslySetInnerHTML={{ __html: READING }} />
          <p className="by">{ARRANGOR_BY}</p>
        </div>
      </section>

      <section className="know" id="bli-kjent">
        <div className="wrap"><h2><span className="loud">Bli kjent med</span><span className="soft">Arrangør.</span></h2></div>
        <div dangerouslySetInnerHTML={{ __html: RAIL }} />
      </section>

      <div dangerouslySetInnerHTML={{ __html: PHOTO }} />

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
      <footer className="lfoot"><div className="wrap"><span>Atten er laget av DashDash18 i Oslo.</span><span>{PHOTO_CREDIT}</span></div></footer>
    </div>
  );
}
