// /guide/golfturnering: «Slik arrangerer du en golfturnering» for én kveld eller én dag. Golfreglene (R&A) og
// World Handicap System er fasit. Liga og cup står på /guide/golfliga, spillformene på /guide/spillformer.
// Om Atten står bare det appen gjør i dag (README.md, «Hva appen gjør nå»). Ingen penger i sidekonkurransene.

import type { ContentPage } from "../innhold.ts";
import { APP_STORE_URL, SITE } from "../html.ts";

const PATH = "/guide/golfturnering";
const TITLE = "Slik arrangerer du en golfturnering – Atten";
const DESCRIPTION =
  "Golfturnering for gjengen, firmaet eller klubben: dato og bane, spillform, handicapandel, flighter, starttider, premier og en sjekkliste.";
const PUBLISHED = "2026-11-02";

const content = `
<h1>Slik arrangerer du en golfturnering</h1>
<p>Denne guiden er for deg som skal arrangere én golfturnering: en kveld med gjengen, en firmadag eller en klubbturnering. Den går gjennom alt fra dato og bane til resultatlista, og slutter med en sjekkliste.</p>

<h2>Planlegging: dato, bane og antall spillere</h2>
<p>Start med tre spørsmål: når, hvor og hvor mange. Svarene avgjør resten.</p>
<ul>
<li><strong>Dato og tid.</strong> Sjekk banens kalender før du sender ut invitasjonen.</li>
<li><strong>Bane eller simulator.</strong> På bane må dere bestille starttider eller gunstart (alle starter samtidig på hvert sitt hull) hos klubben. I simulator er antall båser og timer grensen.</li>
<li><strong>Antall spillere.</strong> En flight er normalt fire spillere. Med gunstart på 18 hull får dere plass til 72 spillere, fire på hvert hull. Er dere flere, må noen hull ha to flighter.</li>
<li><strong>Påmelding.</strong> Sett en påmeldingsfrist og be om navn og handicapindeks. Har dere tak på antall, før venteliste.</li>
</ul>
<p>Er det nybegynnere med, sjekk om banen krever grønt kort eller handicap for å spille. Ellers kan en kortere bane eller simulator være et bedre valg.</p>

<h2>Velg en enkel spillform</h2>
<p>Velg én hovedkonkurranse og hold den enkel. Alle skal forstå hvordan de vinner før første slag.</p>
<ul>
<li><strong>Stableford</strong> passer de fleste turneringer. Hver spiller får poeng per hull etter netto score, og et dårlig hull koster bare det ene hullet. Når du ikke kan få poeng, plukker du opp ballen og går videre.</li>
<li><strong>Scramble</strong> passer når nivået er svært ulikt, for eksempel på en firmadag. Laget velger det beste slaget hver gang, og alle bidrar.</li>
<li><strong>Slagspill</strong> passer erfarne spillere. Alle slag teller, så runden tar lengre tid når noen sliter.</li>
</ul>
<p>Flere former og hvordan de telles, står i <a href="/guide/spillformer">guiden til spillformer</a>. Skal dere spille flere runder over sesongen, se <a href="/guide/golfliga">guiden til golfliga</a>.</p>

<h2>Handicap og handicapandel</h2>
<p>Handicap gjør at spillere på ulikt nivå kan konkurrere på like vilkår. Reglene står i World Handicap System (WHS), som Norges Golfforbund (NGF) følger.</p>
<ul>
<li><strong>Handicapindeks</strong> er spillerens handicap, slik det står i GolfBox.</li>
<li><strong>Banehandicap</strong> er antall slag spilleren får på banen og teesteden dere spiller. Det regnes ut fra indeksen, banens slope og course rating.</li>
<li><strong>Spillehandicap</strong> er banehandicapet ganget med handicapandelen for spillformen. Det er slagene spilleren faktisk får i turneringen. Slagene fordeles på hullene etter hullenes indeks på scorekortet.</li>
</ul>
<p>WHS anbefaler disse handicapandelene:</p>
<div class="tabell"><table>
<thead><tr><th>Spillform</th><th>Anbefalt andel</th></tr></thead>
<tbody>
<tr><td>Slagspill og stableford, individuelt</td><td>95 %</td></tr>
<tr><td>Matchspill, individuelt</td><td>100 %</td></tr>
<tr><td>Bestball (fourball), slagspill og stableford</td><td>85 %</td></tr>
<tr><td>Bestball (fourball), matchspill</td><td>90 %</td></tr>
<tr><td>Foursome</td><td>50 % av lagets samlede banehandicap</td></tr>
<tr><td>Greensome</td><td>60 % av laveste og 40 % av høyeste</td></tr>
<tr><td>Scramble, fire spillere</td><td>25 %, 20 %, 15 % og 10 %, fra laveste til høyeste</td></tr>
<tr><td>Scramble, to spillere</td><td>35 % av laveste og 15 % av høyeste</td></tr>
</tbody>
</table></div>
<p>Arrangøren bestemmer andelen. Skriv den i invitasjonen, sammen med eventuell øvre grense for handicap i turneringen. Vil du se hvordan slag og poeng regnes ut, bruk <a href="/stableford">stableford-kalkulatoren</a>.</p>
<p>Skal runden telle for handicapindeksen, må den registreres som tellende runde før start, etter NGFs regler. Lagformer som scramble og runder i simulator teller ikke.</p>

<h2>Flighter og starttider</h2>
<p>Sett opp flightene noen dager før, og send ut lista med starttid eller starthull.</p>
<ul>
<li><strong>Bland nivåene</strong> i en sosial turnering, så nye spillere får følge av noen som kan reglene. I en jevnere turnering kan dere gruppere etter handicap.</li>
<li><strong>Starttider</strong> gir rolig flyt, men første og siste flight kommer inn til ulik tid. Spør banen hvilket startintervall de bruker.</li>
<li><strong>Gunstart</strong> gjør at alle er ferdige omtrent samtidig. Det passer når dere skal spise eller dele ut premier etterpå.</li>
<li><strong>Markør.</strong> Hver spiller trenger noen som fører og bekrefter scoren. Bestem hvem som fører for hvem i flighten.</li>
</ul>

<h2>Premier og sidekonkurranser</h2>
<p>Bestem premiene før start, og si dem i invitasjonen. Tenk på flere enn vinneren, så det er noe å spille for hele runden.</p>
<ul>
<li><strong>Nærmest hullet:</strong> på et par 3-hull vinner den som legger utslaget nærmest hullet. Ballen må ligge på greenen.</li>
<li><strong>Lengste drive:</strong> på et valgt hull vinner det lengste utslaget som ligger på fairway.</li>
<li><strong>Andre ideer:</strong> premie til beste nybegynner, beste lag eller den som kom nærmest et bestemt mål. Hold det til to eller tre, så det er lett å følge med.</li>
</ul>
<p>Merk av hullene med sidekonkurranser på scorekortet eller med et skilt ved teestedet.</p>

<h2>Resultatliste og delt plass</h2>
<p>Bestem på forhånd hvordan delt plass avgjøres. Vanlig er å sammenligne de siste 9, 6, 3 og til slutt siste hull. Skriv det i invitasjonen, så slipper du diskusjonen etterpå.</p>
<p>Samle inn scorekortene så snart flightene er inne, regn ut resultatet og les opp vinnerne. Del resultatlista med alle etterpå.</p>

<h2>Slik hjelper Atten</h2>
<p>Atten er en gratis golfapp for iPhone som tar papirarbeidet for deg:</p>
<ul>
<li>Påmelding i appen, med tak og venteliste. Har du en liste med navn og handicap fra et regneark eller GolfBox, limer du den inn.</li>
<li>Trekning av flighter og lag, også med gunstart.</li>
<li>Scorekort hull for hull på telefonen. Appen regner handicap og poeng i stableford, slagspill, matchspill og scramble.</li>
<li>Nærmest pinnen og longest drive som sidepremier.</li>
<li>En tavle som oppdateres mens dere spiller. Del lenken, så kan alle følge med i nettleseren uten appen, eller vis den på en skjerm i lokalet.</li>
</ul>
<a class="knapp" href="${APP_STORE_URL}" rel="noopener">Last ned Atten fra App Store</a>

<h2>Sjekkliste for golfturneringen</h2>
<ul>
<li>Dato, tid og bane eller simulator er bestilt.</li>
<li>Invitasjonen er sendt, med påmeldingsfrist.</li>
<li>Spillform, handicapandel og eventuell grense for handicap er bestemt og står i invitasjonen.</li>
<li>Regel for delt plass er bestemt.</li>
<li>Flighter, starttider eller starthull er sendt ut.</li>
<li>Scorekort eller app er klar, og alle vet hvem som fører for hvem.</li>
<li>Premier og hull for sidekonkurranser er bestemt og merket.</li>
<li>Plan for premieutdeling og resultatliste.</li>
</ul>`;

export const GUIDE_GOLFTURNERING: ContentPage = {
  path: PATH,
  title: TITLE,
  description: DESCRIPTION,
  lastmod: PUBLISHED,
  linkText: "Arrangere golfturnering",
  eyebrow: "Guide · golfturnering",
  heading: { loud: "Slik arrangerer du", soft: "en golfturnering" },
  content,
  jsonLd: {
    "@context": "https://schema.org",
    "@type": "Article",
    headline: "Slik arrangerer du en golfturnering",
    description: DESCRIPTION,
    inLanguage: "nb",
    datePublished: PUBLISHED,
    dateModified: PUBLISHED,
    mainEntityOfPage: `${SITE}${PATH}`,
    author: { "@type": "Organization", name: "Atten", url: `${SITE}/` },
    publisher: { "@type": "Organization", name: "Atten", url: `${SITE}/`, logo: `${SITE}/apple-touch-icon.png` },
  },
};
