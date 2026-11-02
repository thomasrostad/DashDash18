// /for-klubber: Atten for golfklubber, simulatorsentre og arrangører. Budskapet er hentet fra forsiden i
// web-admin (web/admin/src/landing/), som er noindex og bygges i nettleseren, så Google ser den ikke.
// Teksten beskriver bare det som står i README.md («Hva appen gjør nå») og web/admin/README.md.
// Ingen priser, kundenavn, sitater eller tall (test/for-klubber.test.ts).

import type { ContentPage } from "../innhold.ts";
import { APP_STORE_URL, SITE } from "../html.ts";

export const ADMIN_URL = "https://admin.dashdash18.com";

const TITLE = "Turneringssystem for golfklubber og simulatorsentre – Atten";
const DESCRIPTION =
  "Atten for klubb, simulatorsenter og golfgjeng: påmelding, flighter, scorekort hull for hull, live tavle på TV og liga hele sesongen.";

const CONTENT = `
<h1>Golfturneringen er ferdig regnet før dere er i baren</h1>
<p>Atten er appen og turneringssystemet for den som arrangerer golf: klubbkvelden, simulatorligaen eller firmaturneringen. Spillerne melder seg på og fører scoren hull for hull på telefonen, regelmotoren regner, og tavla på skjermen oppdaterer seg mens de spiller.</p>
<a class="knapp" href="${APP_STORE_URL}" rel="noopener">Last ned Atten fra App Store</a>
<a class="knapp" href="${ADMIN_URL}" rel="noopener">Logg inn som arrangør</a>

<h2>Turneringssystem for golf: dette får arrangøren</h2>
<ul>
<li><strong>Påmelding.</strong> Spillerne melder seg på i appen. Du kan sette tak, frister og venteliste, og lime inn en liste med navn og handicap fra e-post, GolfBox eller et regneark.</li>
<li><strong>Båser og flighter.</strong> Sett opp runden med bane, tee, startliste og båser eller flighter med markør. Gunstart går også.</li>
<li><strong>Scorekort hull for hull.</strong> Spillerne fører selv på telefonen, og handicap og poeng regnes med en gang.</li>
<li><strong>Tavla live.</strong> Tabellen oppdateres mens det føres, med «Alle runder» og scorekortet til hver spiller. Del tavla som en lenke, så kan tilskuere følge med i nettleseren uten app.</li>
<li><strong>TV-visning.</strong> Lag en TV-kode, så viser skjermen i klubbhuset eller simulatorsenteret tabellen på dashdash18.com/tv, uten appen.</li>
<li><strong>Liga og cup over sesongen.</strong> Serie, liga, cup og morro, med spilledager gjennom hele sesongen.</li>
<li><strong>Arrangør på web.</strong> Sett opp turneringer, terminliste, tropp, runder og tabeller fra PC-en på <a href="${ADMIN_URL}" rel="noopener">admin.dashdash18.com</a>, med samme konto og tilganger som i appen.</li>
</ul>

<h2>App for golfturnering i klubben</h2>
<p>En klubb kan ha flere turneringer i gang samtidig: serien på torsdager, en cup og en åpen turnering der også spillere utenfor klubben melder seg på. Medlemmene får invitasjon med lenke eller QR-kode, og klubben får en egen feed med bilder og reaksjoner fra kvelden. Les mer om hvordan du <a href="/guide/golfturnering">arrangerer en golfturnering</a>.</p>

<h2>Golfsimulator-turnering og liga i båsen</h2>
<p>Atten virker likt på bane og i simulator. Legg inn simulatorbanene med par per hull i web-admin, fordel spillerne på båsene og sett TV-koden på skjermen i lokalet. Mens runden går, viser «Bayen nå» stillingen i båsen.</p>

<h2>Golfliga-app for hele sesongen</h2>
<p>En liga kan gå over mange uker. Med «Spill når det passer» spiller deltakerne i perioden, og de beste rundene teller av seg selv. Tabellen holder seg oppdatert etter hver runde. Se også <a href="/guide/golfliga">hvordan du setter opp en golfliga</a>.</p>

<h2>Regelsett som arrangøren styrer</h2>
<p>Ingenting er låst. Du velger spillform (stableford, slagspill eller matchspill, og former som amerikaner, københavner og lag mot lag), hva som teller (alle runder eller de beste), handicapandel og sidepremier som lengste drive og nærmest pinnen. Tabellen regnes likt i appen, på web og på TV.</p>

<h2>For firmagjengen og golfgjengen</h2>
<p>Dere trenger ikke være en klubb. Lag en privat liga, cup eller morroturnering i appen, inviter gjengen med en lenke, og la gjester være med uten egen konto.</p>

<h2>Kom i gang</h2>
<ol class="steg">
<li>Last ned Atten fra App Store og lag klubben eller turneringen.</li>
<li>Inviter spillerne med lenke eller QR-kode, eller lim inn lista.</li>
<li>Logg inn på admin.dashdash18.com med samme konto når du vil sette opp fra PC-en.</li>
</ol>
<a class="knapp" href="${APP_STORE_URL}" rel="noopener">Last ned Atten fra App Store</a>
<a class="knapp" href="${ADMIN_URL}" rel="noopener">Logg inn som arrangør</a>
<p class="liten">Ny klubb eller senter? Skriv til <a href="mailto:hei@dashdash18.com">hei@dashdash18.com</a>, så viser vi hvordan en sesong ser ut i Atten.</p>`;

export const FOR_KLUBBER: ContentPage = {
  path: "/for-klubber",
  title: TITLE,
  description: DESCRIPTION,
  lastmod: "2026-11-02",
  linkText: "For klubber og sentre",
  content: CONTENT,
  // Ingen aggregateRating: appen har ingen vurderinger å vise.
  jsonLd: {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "WebPage",
        name: TITLE,
        description: DESCRIPTION,
        url: `${SITE}/for-klubber`,
        inLanguage: "nb",
      },
      {
        "@type": "Service",
        name: "Atten for klubber og simulatorsentre",
        serviceType: "Turneringssystem for golf",
        description: DESCRIPTION,
        url: `${SITE}/for-klubber`,
        areaServed: { "@type": "Country", name: "Norge" },
        audience: { "@type": "Audience", audienceType: "Golfklubber, simulatorsentre og arrangører" },
        provider: { "@type": "Organization", name: "Atten", url: `${SITE}/` },
      },
    ],
  },
};
