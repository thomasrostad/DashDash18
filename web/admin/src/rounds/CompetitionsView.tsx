import { competitionRowText, competitionScoreText, type CompetitionBoard, type RyderCupResult } from "../../../golfgutu-core/src/index.ts";

/** «Konkurranser» på rundens side (sql/048): hver konkurranse med resultatlista, og lag mot lag. */
export function CompetitionsView({ boards, team, name, reconstructed }: {
  boards: CompetitionBoard[]; team: RyderCupResult | null; name: (id: string) => string; reconstructed: boolean;
}) {
  return (
    <div className="card">
      <h3>Konkurranser</h3>
      {reconstructed && <p className="muted small">Regelsettet og hullene er hentet i ettertid, ikke fra da runden startet.</p>}
      {team && (
        <>
          <h4>Lag mot lag</h4>
          <ul className="plain">
            {team.table.map((r) => (
              <li key={r.side}>Side {r.side} <strong>{competitionScoreText(r.points)}</strong> <span className="muted small">{r.won} vunnet · {r.halved} delt · {r.lost} tapt</span></li>
            ))}
          </ul>
          {team.matches.some((m) => m.state === "invalid") && <p className="muted small">Matcher der spillerne ikke er på hver sin side, teller ikke.</p>}
        </>
      )}
      {boards.map((b) => (
        <div key={b.key}>
          <h4>{b.name}{b.isMain ? <span className="muted small"> · hovedkonkurransen</span> : null}</h4>
          {!b.supported ? <p className="muted small">Ikke støttet ennå</p>
            : b.rows.length === 0 ? <p className="muted small">Ingen resultater ennå</p> : (
              <ul className="plain">
                {b.rows.slice(0, 10).map((r) => (
                  <li key={r.players.join(",")}>{r.rank}. {r.players.map(name).join(" og ")} <strong>{competitionRowText(b, r)}</strong>
                    {!b.higherIsBetter && <span className="muted small"> slag · {r.holes} hull</span>}</li>
                ))}
              </ul>
            )}
        </div>
      ))}
    </div>
  );
}
