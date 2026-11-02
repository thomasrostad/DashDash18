// Høydekurvene på forsiden: konturene av en green som driver sakte. Høydefeltet er støy pluss
// en kul (greenens topp), og kurvene finnes med marching squares. Ren logikk øverst (testes i
// test/topo.test.ts), tegningen nederst.

/** Et linjestykke i pikselkoordinater: [x1, y1, x2, y2]. */
export type Segment = [number, number, number, number];

const PERM = (() => {
  const p = Array.from({ length: 256 }, (_, i) => i);
  // Fast stokking, så kurvene ser like ut hver gang siden lastes.
  let s = 7;
  for (let i = 255; i > 0; i--) {
    s = (s * 16807) % 2147483647;
    const j = s % (i + 1);
    [p[i], p[j]] = [p[j], p[i]];
  }
  return Uint8Array.from([...p, ...p]);
})();

const fade = (t: number) => t * t * t * (t * (t * 6 - 15) + 10);
const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
function grad(h: number, x: number, y: number, z: number): number {
  const u = h < 8 ? x : y;
  const v = h < 4 ? y : h === 12 || h === 14 ? x : z;
  return ((h & 1) ? -u : u) + ((h & 2) ? -v : v);
}

/** Perlin-støy i tre dimensjoner, omtrent mellom -1 og 1. Den tredje er tiden. */
export function noise3(x: number, y: number, z: number): number {
  const X = Math.floor(x) & 255, Y = Math.floor(y) & 255, Z = Math.floor(z) & 255;
  x -= Math.floor(x); y -= Math.floor(y); z -= Math.floor(z);
  const u = fade(x), v = fade(y), w = fade(z);
  const A = PERM[X] + Y, AA = PERM[A] + Z, AB = PERM[A + 1] + Z, B = PERM[X + 1] + Y, BA = PERM[B] + Z, BB = PERM[B + 1] + Z;
  return lerp(
    lerp(lerp(grad(PERM[AA] & 15, x, y, z), grad(PERM[BA] & 15, x - 1, y, z), u),
      lerp(grad(PERM[AB] & 15, x, y - 1, z), grad(PERM[BB] & 15, x - 1, y - 1, z), u), v),
    lerp(lerp(grad(PERM[AA + 1] & 15, x, y, z - 1), grad(PERM[BA + 1] & 15, x - 1, y, z - 1), u),
      lerp(grad(PERM[AB + 1] & 15, x, y - 1, z - 1), grad(PERM[BB + 1] & 15, x - 1, y - 1, z - 1), u), v),
    w);
}

/** Linjestykkene der feltet krysser `iso`. Feltet er `cols × rows` punkter med `step` piksler mellom. */
export function contourSegments(field: ArrayLike<number>, cols: number, rows: number, step: number, iso: number): Segment[] {
  const out: Segment[] = [];
  for (let j = 0; j < rows - 1; j++) {
    for (let i = 0; i < cols - 1; i++) {
      const a = field[j * cols + i], b = field[j * cols + i + 1];
      const c = field[(j + 1) * cols + i + 1], d = field[(j + 1) * cols + i];
      const k = (a > iso ? 8 : 0) | (b > iso ? 4 : 0) | (c > iso ? 2 : 0) | (d > iso ? 1 : 0);
      if (k === 0 || k === 15) continue;
      const x = i * step, y = j * step;
      const top: [number, number] = [x + step * (iso - a) / (b - a), y];
      const right: [number, number] = [x + step, y + step * (iso - b) / (c - b)];
      const bottom: [number, number] = [x + step * (iso - d) / (c - d), y + step];
      const left: [number, number] = [x, y + step * (iso - a) / (d - a)];
      const seg = (p: [number, number], q: [number, number]) => out.push([p[0], p[1], q[0], q[1]]);
      switch (k) {
        case 1: case 14: seg(left, bottom); break;
        case 2: case 13: seg(bottom, right); break;
        case 3: case 12: seg(left, right); break;
        case 4: case 11: seg(top, right); break;
        case 5: seg(left, top); seg(bottom, right); break;
        case 6: case 9: seg(top, bottom); break;
        case 7: case 8: seg(left, top); break;
        case 10: seg(top, right); seg(left, bottom); break;
      }
    }
  }
  return out;
}

/** Nivåene mellom laveste og høyeste punkt, uten endepunktene. Hvert fjerde er en indekskurve, som på kart. */
export function contourLevels(field: ArrayLike<number>, count: number): { iso: number; index: boolean }[] {
  let min = Infinity, max = -Infinity;
  for (let i = 0; i < field.length; i++) { const v = field[i]; if (v < min) min = v; if (v > max) max = v; }
  if (!(max > min)) return [];
  return Array.from({ length: count - 1 }, (_, n) => ({ iso: min + (max - min) * (n + 1) / count, index: (n + 1) % 4 === 0 }));
}

export interface TopoOptions {
  weak: string; strong: string; levels: number;
  /** Greenens topp, som andel av bredden og høyden. */
  cx: number; cy: number; r: number;
  speed?: number;
}

/** Fyller høydefeltet (`cols × rows` punkter med `step` piksler mellom, flaten er `W × H`) ved tiden `t`:
 *  støy pluss greenens kul, og pekeren som trykker feltet ned. Brukes også av dashdash18.com (web/atten-lenker),
 *  som tegner kurvene én gang som SVG på serveren. */
export function fillTopoField(field: Float32Array, cols: number, rows: number, step: number, W: number, H: number,
                              t: number, o: Pick<TopoOptions, "cx" | "cy" | "r">, mouse = { x: -9999, y: -9999 }): void {
  const s = 0.0021, cx = W * o.cx, cy = H * o.cy, R = Math.max(W, H) * o.r;
  for (let j = 0; j < rows; j++) for (let i = 0; i < cols; i++) {
    const x = i * step, y = j * step;
    let h = noise3(x * s, y * s, t) * 0.9 + noise3(x * s * 2.1, y * s * 2.1, t * 1.3 + 7) * 0.35;
    const dx = (x - cx) / R, dy = (y - cy) / R;
    h += Math.exp(-(dx * dx + dy * dy) * 1.6) * 0.9;
    const mx = x - mouse.x, my = y - mouse.y;
    h += Math.exp(-(mx * mx + my * my) / (2 * 130 * 130)) * 0.42;
    field[j * cols + i] = h;
  }
}

/** Tegner og animerer kurvene i `canvas`. Pekeren trykker feltet ned, som en ball i gresset.
 *  Stopper når lerretet er ute av syne, og står stille med redusert bevegelse. Returnerer en opprydding. */
export function startTopo(canvas: HTMLCanvasElement, o: TopoOptions): () => void {
  const ctx = canvas.getContext("2d");
  if (!ctx) return () => {};
  const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
  let W = 0, H = 0, step = 16, cols = 0, rows = 0, field = new Float32Array(0), visible = true, t = 3.1, raf = 0, last = 0;
  const mouse = { x: -9999, y: -9999, tx: -9999, ty: -9999 };

  const fill = () => fillTopoField(field, cols, rows, step, W, H, t, o, mouse);
  const draw = () => {
    if (!cols) return;
    fill();
    ctx.clearRect(0, 0, W, H);
    for (const { iso, index } of contourLevels(field, o.levels)) {
      ctx.beginPath();
      for (const [x1, y1, x2, y2] of contourSegments(field, cols, rows, step, iso)) { ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); }
      ctx.strokeStyle = index ? o.strong : o.weak;
      ctx.lineWidth = index ? 1.15 : 0.7;
      ctx.stroke();
    }
  };
  const size = () => {
    const r = canvas.getBoundingClientRect();
    if (!r.width) return;
    const dpr = Math.min(2, devicePixelRatio || 1);
    W = r.width; H = r.height;
    canvas.width = W * dpr; canvas.height = H * dpr;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    step = W < 700 ? 20 : 16;
    cols = Math.ceil(W / step) + 1; rows = Math.ceil(H / step) + 1;
    field = new Float32Array(cols * rows);
    draw();
  };
  const loop = (now: number) => {
    raf = requestAnimationFrame(loop);
    if (!visible || still || now - last < 50) return;
    last = now;
    t += o.speed ?? 0.0045;
    mouse.x += (mouse.tx - mouse.x) * 0.12; mouse.y += (mouse.ty - mouse.y) * 0.12;
    draw();
  };
  const host = canvas.parentElement ?? canvas;
  const move = (e: PointerEvent) => {
    const r = canvas.getBoundingClientRect();
    mouse.tx = e.clientX - r.left; mouse.ty = e.clientY - r.top;
    if (mouse.x < -9000) { mouse.x = mouse.tx; mouse.y = mouse.ty; }
  };
  const leave = () => { mouse.tx = -9999; mouse.ty = -9999; };
  host.addEventListener("pointermove", move);
  host.addEventListener("pointerleave", leave);
  const io = new IntersectionObserver((es) => es.forEach((e) => { visible = e.isIntersecting; }));
  io.observe(canvas);
  const ro = new ResizeObserver(() => size());
  ro.observe(canvas);
  size();
  raf = requestAnimationFrame(loop);
  return () => {
    cancelAnimationFrame(raf); io.disconnect(); ro.disconnect();
    host.removeEventListener("pointermove", move); host.removeEventListener("pointerleave", leave);
  };
}
