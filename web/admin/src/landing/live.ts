// Bevegelsen på forsiden (delene i markup.ts): kortene som kommer inn, telefonen som fører en score, pilene under
// raden, setningen som tones inn, tavla som får nye scorer og fotoet som glir. Progressiv forbedring: uten skript
// står alt ferdig, og klassen `live` (style.ts) skrur på starttilstandene.
//
// Funksjonen er selvstendig (ingen import og ingen variabler utenfor), fordi dashdash18.com legger den inn som
// tekst i et inline-skript (web/atten-lenker/src/salgsside.ts). Landing.tsx kaller den i en useEffect.

export function startLanding(root: HTMLElement): () => void {
  const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const stops: (() => void)[] = [];
  const timers = new Set<number>();
  const later = (fn: () => void, ms: number) => {
    const id = window.setTimeout(() => { timers.delete(id); fn(); }, ms);
    timers.add(id);
  };
  const every = (fn: () => void, ms: number) => {
    const id = window.setInterval(fn, ms);
    stops.push(() => clearInterval(id));
  };
  const on = (target: EventTarget, type: string, fn: () => void) => {
    target.addEventListener(type, fn, { passive: true });
    stops.push(() => target.removeEventListener(type, fn));
  };
  /** Kjører `fn` første gang elementet er synlig. */
  const seen = (el: Element, threshold: number, fn: () => void) => {
    const io = new IntersectionObserver((es) => { if (es.some((e) => e.isIntersecting)) { io.disconnect(); fn(); } }, { threshold });
    io.observe(el);
    stops.push(() => io.disconnect());
  };
  /** Kaller `fn` høyst én gang per bilde mens man scroller. */
  const onScroll = (fn: () => void) => {
    let raf = 0;
    on(window, "scroll", () => { if (!raf) raf = requestAnimationFrame(() => { raf = 0; fn(); }); });
    stops.push(() => cancelAnimationFrame(raf));
  };

  root.classList.add("live");

  // Kortene: klassen `in` første gang de er synlige.
  root.querySelectorAll(".kcard[data-inview]").forEach((el) => seen(el, 0.6, () => el.classList.add("in")));

  // Telefonen: spilleren trykker − og scoren blir én mindre, så tilbake, om igjen.
  root.querySelectorAll<HTMLElement>("[data-telefon]").forEach((phone) => {
    const score = phone.querySelector<HTMLElement>(".score");
    const minus = phone.querySelector<HTMLElement>(".pm span");
    if (!score || !minus || still) return;
    const from = score.textContent ?? "";
    const run = () => {
      later(() => {
        minus.classList.add("tap");
        later(() => {
          minus.classList.remove("tap");
          score.textContent = String(Number(from) - 1);
          score.classList.remove("pop");
          void score.offsetWidth;
          score.classList.add("pop");
        }, 150);
      }, 900);
      later(() => { score.textContent = from; score.classList.remove("pop"); }, 5200);
    };
    seen(phone.closest(".kcard") ?? phone, 0.6, () => { run(); every(run, 6400); });
  });

  // Raden: pilene blar ett kort om gangen og er av i hver ende.
  root.querySelectorAll<HTMLElement>(".rail").forEach((rail) => {
    const buttons = rail.parentElement?.querySelectorAll<HTMLButtonElement>(".paddles button");
    if (!buttons || buttons.length !== 2) return;
    const update = () => {
      buttons[0].disabled = rail.scrollLeft < 8;
      buttons[1].disabled = rail.scrollLeft + rail.clientWidth >= rail.scrollWidth - 8;
    };
    on(rail, "scroll", update);
    on(window, "resize", update);
    update();
    buttons.forEach((b) => on(b, "click", () => {
      const card = rail.querySelector(".kcard");
      if (card) rail.scrollBy({ left: Number(b.dataset.dir) * (card.getBoundingClientRect().width + 20), behavior: still ? "auto" : "smooth" });
    }));
  });

  // Setningen leses fram ord for ord mens man scroller.
  root.querySelectorAll<HTMLElement>(".read").forEach((p) => {
    const words = [...p.querySelectorAll<HTMLElement>(".w")];
    if (still) { words.forEach((w) => w.classList.add("on")); return; }
    const update = () => {
      const r = p.getBoundingClientRect();
      const start = innerHeight * 0.85, end = innerHeight * 0.35;
      const t = Math.min(1, Math.max(0, (start - r.top) / (start - end + r.height * 0.6)));
      const n = Math.round(t * words.length);
      words.forEach((w, i) => w.classList.toggle("on", i < n));
    };
    onScroll(update);
    update();
  });

  // Fotoet glir litt saktere enn siden.
  root.querySelectorAll<HTMLElement>("[data-parallax]").forEach((photo) => {
    const img = photo.querySelector<HTMLElement>("img");
    if (!img || still) return;
    onScroll(() => {
      const r = photo.getBoundingClientRect();
      if (r.bottom > 0 && r.top < innerHeight) img.style.transform = `translateY(${(r.top + r.height / 2 - innerHeight / 2) / innerHeight * -40}px)`;
    });
  });

  // Tavla: klokka går, og hvert niende sekund kommer en score inn og tabellen sorterer seg på nytt (FLIP).
  root.querySelectorAll<HTMLElement>(".tv").forEach((tv) => {
    const clock = tv.querySelector<HTMLElement>("[data-klokke]");
    const tick = () => {
      const d = new Date();
      if (clock) clock.textContent = `${String(d.getHours()).padStart(2, "0")}.${String(d.getMinutes()).padStart(2, "0")}`;
    };
    tick();
    every(tick, 15000);
    const body = tv.querySelector("tbody");
    const toast = tv.querySelector<HTMLElement>(".toast");
    let events: { name: string; hole: number; what: string; add: number }[] = [];
    try { events = JSON.parse(tv.dataset.hendelser ?? "[]"); } catch { events = []; }
    if (still || !body || !toast || !events.length) return;
    const points = (r: HTMLElement) => Number(r.querySelector(".pts")?.textContent ?? 0);
    let n = 0;
    const step = () => {
      const e = events[n++ % events.length];
      const who = document.createElement("span");
      who.textContent = `${e.name} · hull ${e.hole}`;
      const what = document.createElement("i");
      what.textContent = `${e.what}, +${e.add}`;
      toast.replaceChildren(who, what);
      toast.classList.add("in");
      later(() => {
        const rows = [...body.querySelectorAll<HTMLTableRowElement>("tr")];
        const before = new Map(rows.map((r) => [r, r.getBoundingClientRect().top]));
        const row = rows.find((r) => r.dataset.navn === e.name);
        const pts = row?.querySelector(".pts");
        if (row && pts) { pts.textContent = String(points(row) + e.add); row.classList.add("bump"); }
        rows.map((r, i) => ({ r, i, p: points(r) }))
          .sort((a, b) => b.p - a.p || a.i - b.i)
          .forEach(({ r }, i) => {
            body.appendChild(r);
            r.classList.toggle("lead", i === 0);
            const place = r.querySelector(".pl");
            if (place) place.textContent = String(i + 1);
          });
        for (const r of rows) {
          const dy = (before.get(r) ?? 0) - r.getBoundingClientRect().top;
          if (!dy) continue;
          r.style.transition = "none";
          r.style.transform = `translateY(${dy}px)`;
          requestAnimationFrame(() => requestAnimationFrame(() => { r.style.transition = ""; r.style.transform = ""; }));
        }
        later(() => { toast.classList.remove("in"); row?.classList.remove("bump"); }, 2400);
      }, 1000);
    };
    later(() => { step(); every(step, 9000); }, 4000);
  });

  return () => {
    stops.forEach((stop) => stop());
    timers.forEach((id) => clearTimeout(id));
    root.classList.remove("live");
  };
}
