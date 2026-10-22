export function escapeHTML(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

export const SITE = "https://dashdash18.com";

/// Favorittikonet og hjemskjermikonet i public/, laget fra app-ikonet (DashDash18/AppIcon.icon).
export const ICON_LINKS = [
  '<link rel="icon" href="/favicon.ico" sizes="48x48">',
  '<link rel="icon" href="/favicon.svg" type="image/svg+xml">',
  '<link rel="apple-touch-icon" href="/apple-touch-icon.png">',
].join("\n");

/// Del-kortet i Messenger, WhatsApp, iMessage, Slack og X: tittel, tekst og bildet i public/og.png (1200 × 630).
/// `path` er adressen på dashdash18.com (f.eks. "/" eller "/tavla/KODE").
export function shareMeta(title: string, description: string, path: string): string {
  return [
    `<meta property="og:type" content="website">`,
    `<meta property="og:site_name" content="Atten">`,
    `<meta property="og:locale" content="nb_NO">`,
    `<meta property="og:url" content="${escapeHTML(SITE + path)}">`,
    `<meta property="og:title" content="${escapeHTML(title)}">`,
    `<meta property="og:description" content="${escapeHTML(description)}">`,
    `<meta property="og:image" content="${SITE}/og.png">`,
    `<meta property="og:image:width" content="1200">`,
    `<meta property="og:image:height" content="630">`,
    `<meta property="og:image:alt" content="Atten-logoen og teksten «Golfkvelden med gjengen, samlet i én app»">`,
    `<meta name="twitter:card" content="summary_large_image">`,
  ].join("\n");
}
