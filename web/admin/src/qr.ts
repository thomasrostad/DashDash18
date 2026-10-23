// QR-koden til TV-koden og lenken til turneringen, som QRCode.image i appen. Prikkene regnes av
// qrcode-generator (godkjent av Thomas 23.10.2026); tegningen står i QRCode.tsx.

import qrcode from "qrcode-generator";

/** Prikkene, rad for rad. Minste versjon som får plass, og feilretting M. */
export function qrMatrix(text: string): boolean[][] {
  const qr = qrcode(0, "M");
  qr.addData(text);
  qr.make();
  const n = qr.getModuleCount();
  return Array.from({ length: n }, (_, r) => Array.from({ length: n }, (_, c) => qr.isDark(r, c)));
}

/** SVG-stien for de mørke prikkene, én enhet per prikk (`M c r h1 v1 h-1 z`). */
export function qrPath(matrix: readonly (readonly boolean[])[]): string {
  const parts: string[] = [];
  matrix.forEach((row, r) => row.forEach((dark, c) => { if (dark) parts.push(`M${c} ${r}h1v1h-1z`); }));
  return parts.join("");
}
