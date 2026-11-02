import type { ContentPage } from "../innhold.ts";
import { APP_STORE_URL } from "../html.ts";

// Guide: golfliga eller cup for en hel sesong. Én turnering står i /guide/golfturnering, spillformene i
// /guide/spillformer og regningen i /stableford; her lenkes det dit i stedet for å gjenta.
// Atten-delen beskriver bare det appen gjør (regelsettet i Packages/GolfgutuCore/REGELSETT.md).

const PUBLISHED = "2026-11-02";

const content = `
<h1>Slik lager du en golfliga eller cup for sesongen</h1>
<p>En golfliga samler gjengen, firmaet, klubben eller simulatorsenteret til faste kvelder gjennom sesongen, med en tabell som avgjør hvem som vinner til slutt. Her er valgene du bør ta før første kveld: liga eller cup, antall kvelder, poengsystem, handicap og hva som skjer ved likt.</p>
<p>Skal dere bare spille én turnering, se <a href="/guide/golfturnering">guiden til golfturnering</a>.</p>

<h2>Liga eller cup?</h2>
<p><strong>Liga</strong> (serie) betyr at alle spiller mange kvelder og samler poeng i én tabell. Alle er med hele sesongen, og en dårlig kveld kan tas igjen. Det passer best når dere vil møtes ofte.</p>
<p><strong>Cup</strong> betyr utslag: to og to spiller matchspill, og den som vinner, går videre til neste runde. Med 16 spillere blir det fire runder fram til finalen. Cupen er spennende, men halvparten er ute etter første runde.</p>
<p>Mange kombinerer: en liga gjennom sesongen og en cup ved siden av, der plassen i ligaen gir seedingen i cupen.</p>

<h2>Hvor mange kvelder?</h2>
<p>Tell opp kveldene dere realistisk får til fra sesongstart til avslutning, og trekk fra ferier. Det er bedre med færre kvelder som blir spilt, enn mange som blir avlyst. Bestem samtidig om en spiller må ha spilt et minste antall kvelder for å kunne vinne.</p>
<p>Får ikke alle til å møtes samme kveld, kan ligaen ha en periode i stedet, der hver spiller leverer runder når det passer, og de beste teller.</p>

<h2>Poengsystem: tre vanlige måter</h2>
<div class="tabell"><table>
<thead><tr><th>System</th><th>Slik virker det</th><th>Passer når</th></tr></thead>
<tbody>
<tr><td>Stablefordpoeng summert</td><td>Poengene fra hver kveld legges sammen.</td><td>Dere spiller samme type bane hver gang og vil at hvert slag skal telle.</td></tr>
<tr><td>Plasseringspoeng (order of merit)</td><td>Plassen på kvelden gir poeng, for eksempel 25 for vinneren, 20 for nummer to og så videre.</td><td>Banene eller været varierer. En storkveld gir ikke mer enn en seier.</td></tr>
<tr><td>Matchpoeng</td><td>Spillerne trekkes mot hverandre i matcher, og seier, uavgjort og tap gir poeng.</td><td>Dere vil ha dueller og prat om hvem som slo hvem.</td></tr>
</tbody>
</table></div>
<p>Hvordan stablefordpoengene regnes ut, står på <a href="/stableford">stableford-kalkulatoren</a>. Spillformene, som slagspill, matchspill og scramble, er forklart i <a href="/guide/spillformer">guiden til spillformer</a>.</p>

<h2>La de beste kveldene telle</h2>
<p>Alle går glipp av en kveld eller to. Lar du for eksempel de beste 5 av 7 kveldene telle, taper ingen på å være borte en gang. Det holder også spenningen oppe mot slutten, fordi en god kveld kan erstatte en svak.</p>
<p>Et alternativ er snitt per spilte kveld. Da bør dere kreve et minste antall kvelder, ellers kan én god kveld vinne hele sesongen.</p>

<h2>Handicap gjennom sesongen</h2>
<p>Med handicap kan alle vinne. Etter World Handicap System (WHS) regnes handicapindeksen om til banehandicap for banen og teestedet dere spiller fra. Spillehandicapet er banehandicapet ganget med handicapandelen. WHS anbefaler 95 % i individuelt slagspill og stableford, og 100 % i singel matchspill.</p>
<p>Handicapindeksen endrer seg i løpet av sesongen. Bestem på forhånd om dere bruker indeksen spilleren har på spilledagen, eller fryser den ved sesongstart. Indeksen på spilledagen er mest rettferdig for den som blir bedre. Uansett bør et resultat stå som det ble spilt, også om noen endrer handicap senere.</p>
<p>Har ikke alle et offisielt handicap, kan dere dele spillerne i grupper (seeding) med et fast handicap for hver gruppe. I simulator kan dere bruke handicapindeksen som på banen, eller la simulatoren gi slagene.</p>

<h2>Individuelt eller lag?</h2>
<p>De fleste ligaer er individuelle. Lag gir en annen stemning: faste par eller lag som spiller fourball, foursome eller scramble, eller to sider som møtes lag mot lag, som i Ryder Cup. I lagformene gir WHS egne anbefalinger for lagshandicap. Se <a href="/guide/spillformer">spillformene</a> for detaljene.</p>

<h2>Når det står likt</h2>
<p>Skriv ned før sesongen hvordan likt i tabellen avgjøres, så slipper dere diskusjonen i finalen. Vanlige skiller er flest poeng i stableford, flest seire eller resultatet mellom dem det gjelder. Står det fortsatt likt om førsteplassen, kan en playoff over noen hull avgjøre.</p>
<p>I en cupmatch som står likt etter 18 hull, er det vanlig å spille videre til noen vinner et hull (sudden death).</p>

<h2>Finale og sesongavslutning</h2>
<p>En finalekveld gir sesongen en slutt. La gjerne finalen telle dobbelt, så flere har noe å spille for helt til slutt. Avslutt med premieutdeling og en vandrepremie, for eksempel en jakke, et trofé eller et skilt med vinnernes navn, som vinneren har til neste sesong.</p>

<h2>Sjekkliste før første kveld</h2>
<ul>
<li>Liga, cup eller begge</li>
<li>Datoene for kveldene, med finalen</li>
<li>Poengsystem og hvor mange kvelder som teller</li>
<li>Minste antall kvelder for å kunne vinne</li>
<li>Handicap: indeks på spilledagen eller fryst, og handicapandel</li>
<li>Individuelt eller lag</li>
<li>Skiller ved likt, og om det blir playoff</li>
<li>Premier og vandrepremie</li>
<li>Hvem som fører resultatene, og hvor alle ser tabellen</li>
</ul>

<h2>Slik gjør du det i Atten</h2>
<p>Atten er en gratis golfapp for iPhone som tar seg av sesongen for deg. Du lager en serie eller en cup i appen og velger reglene: antall kvelder, stablefordpoeng, plasseringspoeng eller matchpoeng, de beste kveldene som teller, minste antall kvelder, handicapandel og skiller ved likt.</p>
<ul>
<li>Spillerne melder seg på kveldene i appen og fører scoren hull for hull.</li>
<li>Tabellen regnes ut av seg selv etter hver runde, med handicapet spilleren hadde da runden startet.</li>
<li>Cupen har et cuptre, med seeding etter trekning, handicap eller plassen i hovedturneringen.</li>
<li>En finalekveld kan telle dobbelt, og står det likt øverst, kan playoffen føres i appen.</li>
<li>I simulator kan simulatoren gi slagene i stedet for appen.</li>
<li>Tilskuere følger tabellen i nettleseren med en lenke, uten app.</li>
</ul>
<a class="knapp" href="${APP_STORE_URL}" rel="noopener">Last ned Atten fra App Store</a>
`;

export const GUIDE_GOLFLIGA: ContentPage = {
  path: "/guide/golfliga",
  title: "Golfliga og cup for sesongen: oppsett og poeng – Atten",
  description:
    "Slik lager du en golfliga eller cup for sesongen: antall kvelder, poengsystem, beste kvelder som teller, handicap, likt og finale. Med sjekkliste.",
  lastmod: PUBLISHED,
  linkText: "Golfliga",
  content,
  jsonLd: {
    "@context": "https://schema.org",
    "@type": "Article",
    headline: "Slik lager du en golfliga eller cup for sesongen",
    inLanguage: "nb",
    datePublished: PUBLISHED,
    dateModified: PUBLISHED,
    author: { "@type": "Organization", name: "Atten", url: "https://dashdash18.com/" },
    publisher: { "@type": "Organization", name: "Atten", url: "https://dashdash18.com/" },
    mainEntityOfPage: "https://dashdash18.com/guide/golfliga",
  },
};
