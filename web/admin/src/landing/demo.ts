// Eksempeltavla på forsiden. Oppdiktede navn og poeng, merket som eksempel på siden.
// Ren logikk (testes i test/landingDemo.test.ts); visningen står i DemoTavla.tsx.

export interface DemoPlayer { name: string; points: number; rounds: number[] }
export interface DemoEvent { name: string; hole: number; what: "birdie" | "eagle"; add: number }

export const DEMO_PLAYERS: readonly DemoPlayer[] = [
  { name: "Kari Moen", points: 206, rounds: [38, 36, 35, 34, 33, 30, 29] },
  { name: "Henrik A.", points: 198, rounds: [37, 35, 34, 32, 31, 29, 27] },
  { name: "Marte L.", points: 191, rounds: [36, 34, 33, 31, 29, 28, 26] },
  { name: "Jon B.", points: 184, rounds: [35, 33, 32, 30, 28, 26, 25] },
  { name: "Sigrid H.", points: 177, rounds: [34, 32, 31, 29, 27, 24, 22] },
  { name: "Anders V.", points: 170, rounds: [33, 31, 30, 28, 25, 23, 21] },
  { name: "Nora H.", points: 163, rounds: [32, 30, 29, 27, 24, 21, 20] },
  { name: "Ola B.", points: 158, rounds: [31, 29, 28, 26, 23, 21, 19] },
];

export const DEMO_EVENTS: readonly DemoEvent[] = [
  { name: "Marte L.", hole: 16, what: "birdie", add: 4 },
  { name: "Jon B.", hole: 14, what: "eagle", add: 5 },
  { name: "Sigrid H.", hole: 12, what: "birdie", add: 4 },
  { name: "Nora H.", hole: 9, what: "birdie", add: 4 },
];

/** Tabellen etter en hendelse: poengene lagt til og sortert på nytt, høyest først (stabil ved likt). */
export function applyDemoEvent(players: readonly DemoPlayer[], e: DemoEvent): DemoPlayer[] {
  return players
    .map((p) => (p.name === e.name ? { ...p, points: p.points + e.add } : p))
    .map((p, i) => ({ p, i }))
    .sort((a, b) => b.p.points - a.p.points || a.i - b.i)
    .map(({ p }) => p);
}
