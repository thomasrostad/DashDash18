// Guiden til spillformene i golf (/guide/spillformer). Reglene er fra Golfreglene (R&A, regel 3, 21, 22 og 23),
// handicapandelene fra WHS (Rules of Handicapping, Appendix C «Handicap Allowances»). Formene som står som
// støttet, er de som finnes i regelmotoren (CompetitionForm.catalog i Packages/GolfgutuCore). Skins er utelatt.
import type { ContentPage } from "../innhold.ts";
import { APP_STORE_URL, SITE } from "../html.ts";

const PATH = "/guide/spillformer";
const TITLE = "Spillformer i golf: stableford, matchspill og scramble – Atten";
const DESCRIPTION =
  "Stableford, slagspill, matchspill, fourball, foursome, greensome og Texas scramble: slik telles de, handicapandel etter WHS og når de passer.";
const PUBLISHED = "2026-11-02";

const CONTENT = `
<h1>Spillformer i golf</h1>
<p>Stableford, slagspill, matchspill, fourball, foursome, greensome og scramble. Her er hva formene går ut på, hvordan scoren telles, hvor mye handicap som brukes, og når de passer.</p>
<p>Reglene er fra Golfreglene (R&amp;A). Handicapandelene er anbefalingene i World Handicap System (WHS), Appendix C i handicapreglene. Andelen er en anbefaling: det er arrangøren (komiteen) som bestemmer den for turneringen.</p>

<h2>Oversikt over spillformene</h2>
<div class="tabell"><table>
<thead><tr><th>Spillform</th><th>Individuelt eller lag</th><th>Hva telles</th><th>Handicapandel (WHS)</th><th>Passer for</th><th>I Atten</th></tr></thead>
<tbody>
<tr><td>Stableford</td><td>Individuelt</td><td>Poeng per hull mot netto par</td><td>95 %</td><td>Alle, også nybegynnere</td><td>Ja</td></tr>
<tr><td>Slagspill</td><td>Individuelt</td><td>Sum slag, brutto eller netto</td><td>95 % (netto)</td><td>Erfarne spillere, mesterskap</td><td>Ja</td></tr>
<tr><td>Matchspill</td><td>Én mot én</td><td>Hull vunnet, tapt eller delt</td><td>100 %</td><td>Cup og utslagsturnering</td><td>Ja</td></tr>
<tr><td>Fourball (bestball)</td><td>Lag på to</td><td>Beste score på laget per hull</td><td>85 % slagspill, 90 % match</td><td>Par og lagkamp</td><td>Ja</td></tr>
<tr><td>Foursome</td><td>Lag på to, én ball</td><td>Lagets score, annethvert slag</td><td>50 % av summen</td><td>Par som vil spille raskt</td><td>Ja</td></tr>
<tr><td>Greensome</td><td>Lag på to, én ball</td><td>Lagets score, beste utslag</td><td>60 % laveste + 40 % høyeste</td><td>Blandet nivå, par</td><td>Ja</td></tr>
<tr><td>Chapman (Pinehurst)</td><td>Lag på to, én ball</td><td>Lagets score etter ballbytte</td><td>60 % laveste + 40 % høyeste</td><td>Par som vil slå mye</td><td>Ja</td></tr>
<tr><td>Texas scramble</td><td>Lag på to til fire</td><td>Lagets score, beste ball hvert slag</td><td>4 spillere: 25/20/15/10 %. 2 spillere: 35/15 %</td><td>Firmaturnering, nybegynnere</td><td>Ja (2 og 4 spillere)</td></tr>
<tr><td>Florida scramble</td><td>Lag</td><td>Som scramble, den som slo beste ball, står over neste slag</td><td>Ingen egen anbefaling</td><td>Lag som vil ha mer variasjon</td><td>Nei</td></tr>
</tbody>
</table></div>

<h2>Handicapandel: slik virker den</h2>
<p>Banehandicapet ditt sier hvor mange slag du får på banen du spiller. I en konkurranse ganges banehandicapet med handicapandelen, og resultatet er spillehandicapet: slagene du faktisk får i den runden. Med banehandicap 20 og 95 % får du 19 slag. Slagene fordeles på hullene etter hcp-indeksen på scorekortet, de vanskeligste hullene først.</p>
<p>Andelen er lavere enn 100 % i mange former fordi formen gir en fordel til spillere med høyt handicap, for eksempel når laget kan velge den beste av flere baller.</p>

<h2>Stableford</h2>
<p>Stableford er den vanligste formen i klubbturneringer i Norge. Du får poeng på hvert hull etter hvordan netto scoren din er mot par (Golfreglene, regel 21.1):</p>
<ul>
<li>2 over netto par eller mer: 0 poeng</li>
<li>1 over netto par (netto bogey): 1 poeng</li>
<li>Netto par: 2 poeng</li>
<li>1 under netto par (netto birdie): 3 poeng</li>
<li>2 under netto par: 4 poeng, og ett poeng mer for hvert slag bedre</li>
</ul>
<p>Høyest poengsum vinner. Spiller du på handicapet ditt, får du 36 poeng på 18 hull. Når du ikke lenger kan få poeng på et hull, kan du plukke opp ballen. Det holder tempoet oppe, og et dårlig hull ødelegger ikke runden.</p>
<p><strong>Handicapandel:</strong> 95 % (WHS). <strong>Passer for:</strong> alle, og spesielt for nybegynnere og blandede felt. Regn ut poengene med <a href="/stableford">stablefordkalkulatoren</a>.</p>

<h2>Slagspill (brutto og netto)</h2>
<p>I slagspill teller hvert slag på alle hull (regel 3.3). Lavest sum vinner. <strong>Brutto</strong> er rene slag uten handicap. <strong>Netto</strong> er slagene minus spillehandicapet. Du må fullføre hvert hull, så en runde i slagspill tar ofte lengre tid enn stableford.</p>
<p><strong>Handicapandel:</strong> 95 % i netto slagspill (WHS). Brutto bruker ikke handicap. <strong>Passer for:</strong> erfarne spillere og mesterskap, der brutto avgjør hvem som spiller best.</p>

<h2>Par/bogey og maksimumscore</h2>
<p><strong>Par/bogey</strong> (regel 21.3) er en match mot banen: du vinner hullet (+) med netto score under par, deler (0) med netto par og taper (−) over par. Resultatet er antall vunne minus tapte hull, for eksempel «+3».</p>
<p><strong>Maksimumscore</strong> (regel 21.2) er slagspill med et tak per hull, for eksempel netto dobbel bogey. Når du når taket, kan du plukke opp ballen. Det gir slagspill med bedre tempo.</p>
<p><strong>Handicapandel:</strong> 95 % for begge (WHS).</p>

<h2>Matchspill</h2>
<p>I matchspill spiller du hull mot hull mot én motstander (regel 3.2). Lavest netto score vinner hullet. Like score gir delt hull. Matchen er avgjort når den ene leder med flere hull enn det er igjen. «Vunnet 3&amp;2» betyr 3 opp med 2 hull igjen.</p>
<p><strong>Handicapandel:</strong> 100 % (WHS). Spilleren med lavest spillehandicap spiller på 0, og motstanderen får forskjellen i slag. <strong>Passer for:</strong> cup, utslagsturnering og lag mot lag.</p>

<h2>Fourball (bestball)</h2>
<p>Fourball (regel 23) spilles av lag på to. Begge spiller sin egen ball hele hullet, og den beste scoren på laget er lagets score på hullet. Spilles som slagspill, stableford eller match, to mot to.</p>
<p><strong>Handicapandel:</strong> 85 % i slagspill og stableford, 90 % i matchspill (WHS). I match spiller den med lavest spillehandicap på 0, og de tre andre får forskjellen. Spiller fire på laget, og bare den beste scoren teller, er anbefalingen 75 %. <strong>Passer for:</strong> par og lagkamper. Et dårlig hull fra den ene gjør lite når makkeren spiller godt.</p>

<h2>Foursome</h2>
<p>I foursome (regel 22) spiller laget på to én ball, og partnerne slår annethvert slag. Den ene slår ut på hullene med oddetall, den andre på partallshullene. Straffeslag endrer ikke rekkefølgen.</p>
<p><strong>Handicapandel:</strong> 50 % av summen av banehandicapene på laget (WHS). I match får laget med høyest handicap 50 % av forskjellen mellom lagenes summer. <strong>Passer for:</strong> par som kjenner hverandre, og når runden skal gå raskt. Med én ball for to går det fortere enn når alle spiller sin egen.</p>

<h2>Greensome</h2>
<p>I greensome slår begge på laget ut. Laget velger det beste utslaget, og den som ikke slo det, slår andreslaget. Deretter slår dere annethvert slag til ballen er i hullet. Greensome er ikke beskrevet i Golfreglene, så arrangøren bør skrive opp reglene for turneringen.</p>
<p><strong>Handicapandel:</strong> 60 % av det laveste og 40 % av det høyeste banehandicapet (WHS). <strong>Passer for:</strong> par med ulikt nivå. Den svakeste spilleren slipper presset på utslaget og får likevel slå mye.</p>

<h2>Chapman (Pinehurst)</h2>
<p>I chapman slår begge ut, og så slår dere andreslaget med hverandres ball. Laget velger den beste av de to ballene, og spiller annethvert slag derfra.</p>
<p><strong>Handicapandel:</strong> 60 % av det laveste og 40 % av det høyeste banehandicapet (WHS), som i greensome. <strong>Passer for:</strong> par som vil ha flere slag hver enn i foursome.</p>

<h2>Texas scramble</h2>
<p>I scramble slår alle på laget ut. Laget velger den beste ballen, og alle slår neste slag fra det stedet. Slik fortsetter dere til ballen er i hullet. Laget fører én score per hull. Texas scramble er navnet mange bruker i Norge, ofte med et krav om at hver spillers utslag skal brukes et visst antall ganger. Kravet bestemmer arrangøren.</p>
<p><strong>Handicapandel:</strong> med fire spillere 25 % av det laveste banehandicapet, så 20 %, 15 % og 10 % av det høyeste. Med to spillere 35 % av det laveste og 15 % av det høyeste (WHS). Andelene legges sammen til lagets handicap.</p>
<p><strong>Passer for:</strong> firmaturneringer, nybegynnere og store felt med blandet nivå. Alle bidrar, de dårlige slagene teller ikke, og runden går raskt.</p>

<h2>Florida scramble</h2>
<p>Florida scramble er en variant av scramble: den som slo ballen laget valgte, står over neste slag. Da får alle på laget slå, også når én spiller godt. WHS har ingen egen anbefaling for varianten. Handicapandelen er etter antall spillere på laget, som i scramble, eller det arrangøren bestemmer.</p>

<h2>Amerikaner og Københavner</h2>
<p>To poengspill fra Norges Golfforbunds oversikt over spilleformer. Spillerne i gruppa spiller hver sin ball og deler et fast antall poeng på hvert hull etter netto score. I <strong>amerikaner</strong> er dere fire og deler 12 poeng per hull. I <strong>københavner</strong> er dere tre og deler 6 poeng. Flest poeng etter runden vinner. Formene passer når én gruppe vil ha sin egen konkurranse i runden.</p>

<h2>Hvilken spillform passer?</h2>
<ul>
<li><strong>Firmaturnering og nybegynnere:</strong> Texas scramble eller greensome. Alle bidrar, og ingen trenger å telle alle sine egne slag.</li>
<li><strong>Golfgjengen hver uke:</strong> stableford. Alle har en sjanse med handicap, og dårlige hull koster lite.</li>
<li><strong>Cup og lagkamp:</strong> matchspill, fourball og foursome.</li>
<li><strong>Klubbmesterskap:</strong> slagspill, brutto og netto.</li>
</ul>
<p>Skal du sette opp hele turneringen, se <a href="/guide/golfturnering">guiden til å arrangere en golfturnering</a>.</p>

<h2>Spillformene i Atten</h2>
<p>Atten fører scoren hull for hull og regner med handicap. Appen støtter stableford og slagspill (brutto og netto), par/bogey, maksimumscore, matchspill, fourball (to og fire på laget), foursome, greensome, chapman, scramble med to og fire spillere, amerikaner og københavner. Florida scramble finnes ikke som egen form.</p>
<p>I formene med én ball per lag (foursome, greensome, chapman og scramble) fører laget én score per hull, og runden regnes som netto stableford med lagets handicap. Arrangøren velger handicapandelen i reglene, og kan bruke WHS-anbefalingen.</p>
<a class="knapp" href="${APP_STORE_URL}" rel="noopener">Last ned Atten fra App Store</a>`;

export const guideSpillformer: ContentPage = {
  path: PATH,
  title: TITLE,
  description: DESCRIPTION,
  lastmod: PUBLISHED,
  linkText: "Spillformer i golf",
  content: CONTENT,
  jsonLd: {
    "@context": "https://schema.org",
    "@type": "Article",
    headline: "Spillformer i golf: stableford, slagspill, matchspill, scramble og flere",
    description: DESCRIPTION,
    inLanguage: "nb",
    datePublished: PUBLISHED,
    dateModified: PUBLISHED,
    mainEntityOfPage: `${SITE}${PATH}`,
    author: { "@type": "Organization", name: "Atten", url: `${SITE}/` },
    publisher: {
      "@type": "Organization",
      name: "Atten",
      url: `${SITE}/`,
      logo: { "@type": "ImageObject", url: `${SITE}/apple-touch-icon.png` },
    },
  },
};
