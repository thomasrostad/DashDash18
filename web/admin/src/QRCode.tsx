import { qrMatrix, qrPath } from "./qr.ts";

/** QR-koden som SVG på hvit bakgrunn, med stille sone på fire prikker. */
export function QRCode({ value, label, size = 200 }: { value: string; label: string; size?: number }) {
  const matrix = qrMatrix(value);
  const n = matrix.length + 8;
  return (
    <svg className="qr" role="img" aria-label={label} width={size} height={size} viewBox={`-4 -4 ${n} ${n}`} shapeRendering="crispEdges">
      <rect x={-4} y={-4} width={n} height={n} fill="#fff" />
      <path d={qrPath(matrix)} fill="#000" />
    </svg>
  );
}
