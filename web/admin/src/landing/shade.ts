// Morgenlys over den lyse delen av forsiden: skyggen av greiner som svaier sakte. Greinene tegnes én
// gang og gjøres uskarpe, så hver ramme bare flytter et ferdig bilde.

export function startShade(canvas: HTMLCanvasElement): () => void {
  const ctx = canvas.getContext("2d");
  if (!ctx) return () => {};
  const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
  let W = 0, H = 0, img: HTMLCanvasElement | null = null, visible = false, t = 0, raf = 0, last = 0;

  const build = () => {
    const off = document.createElement("canvas");
    off.width = Math.ceil(W * 1.3); off.height = Math.ceil(H * 1.3);
    const o = off.getContext("2d");
    if (!o) return;
    o.fillStyle = o.strokeStyle = "#1d2a22";
    let seed = 7;
    const rnd = () => { seed = (seed * 16807) % 2147483647; return seed / 2147483647; };
    const branch = (x: number, y: number, a: number, len: number, w: number, depth: number) => {
      if (depth === 0 || len < 8) return;
      const x2 = x + Math.cos(a) * len, y2 = y + Math.sin(a) * len;
      o.lineWidth = w;
      o.beginPath(); o.moveTo(x, y);
      o.quadraticCurveTo((x + x2) / 2 + rnd() * 20 - 10, (y + y2) / 2 + rnd() * 20 - 10, x2, y2);
      o.stroke();
      if (depth < 4) for (let k = 0; k < 7; k++) {
        const lx = x + (x2 - x) * rnd(), ly = y + (y2 - y) * rnd();
        o.save(); o.translate(lx + rnd() * 30 - 15, ly + rnd() * 30 - 15); o.rotate(rnd() * Math.PI);
        o.beginPath(); o.ellipse(0, 0, 10 + rnd() * 12, 5 + rnd() * 5, 0, 0, Math.PI * 2); o.fill(); o.restore();
      }
      branch(x2, y2, a - 0.35 - rnd() * 0.4, len * 0.72, w * 0.7, depth - 1);
      branch(x2, y2, a + 0.3 + rnd() * 0.4, len * 0.7, w * 0.7, depth - 1);
      if (rnd() > 0.5) branch(x2, y2, a + rnd() * 0.3 - 0.15, len * 0.6, w * 0.6, depth - 1);
    };
    branch(-40, off.height * 0.15, 0.35, off.width * 0.22, 14, 7);
    branch(off.width + 40, off.height * 0.05, Math.PI - 0.5, off.width * 0.2, 12, 7);
    branch(off.width * 0.55, -60, 1.75, off.height * 0.28, 10, 6);
    const blurred = document.createElement("canvas");
    blurred.width = off.width; blurred.height = off.height;
    const bc = blurred.getContext("2d");
    if (!bc) return;
    bc.filter = "blur(9px)";
    bc.drawImage(off, 0, 0);
    img = blurred;
  };
  const draw = () => {
    if (!img) return;
    ctx.clearRect(0, 0, W, H);
    ctx.save();
    ctx.translate(W / 2, -H * 0.05);
    ctx.rotate(Math.sin(t * 0.6) * 0.012 + Math.sin(t * 1.7) * 0.004);
    ctx.translate(-W * 0.65 + Math.sin(t * 0.9) * 6, -H * 0.1);
    ctx.drawImage(img, 0, 0);
    ctx.restore();
  };
  const size = () => {
    const r = canvas.getBoundingClientRect();
    if (!r.width) return;
    const dpr = Math.min(1.5, devicePixelRatio || 1);
    W = r.width; H = r.height;
    canvas.width = W * dpr; canvas.height = H * dpr;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    build(); draw();
  };
  const loop = (now: number) => {
    raf = requestAnimationFrame(loop);
    if (!visible || still || now - last < 50) return;
    last = now; t += 0.05; draw();
  };
  const io = new IntersectionObserver((es) => es.forEach((e) => { visible = e.isIntersecting; }));
  io.observe(canvas);
  const ro = new ResizeObserver(() => size());
  ro.observe(canvas);
  size();
  raf = requestAnimationFrame(loop);
  return () => { cancelAnimationFrame(raf); io.disconnect(); ro.disconnect(); };
}
