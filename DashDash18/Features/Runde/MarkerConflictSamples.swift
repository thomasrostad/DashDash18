#if DEBUG
import Foundation
import SwiftUI

/// Markørkonflikten (K6/6.3) med oppdiktede data, uten nett: `-DDDesignScreen markorkonflikt` (føringen på
/// hull 5 med stripa og merket på raden) og `markorkonfliktark` (arket med begge tallene).
enum MarkerConflictSamples {
    /// Kåre på hull 5: du førte 5 kl. 18:42, Ola førte 6 to minutter før.
    static func conflict(roundID: UUID) -> HoleConflictRow {
        let kept = EveningDates.time(from: "18:42", on: .now) ?? .now
        return HoleConflictRow(id: UUID(), roundID: roundID, memberID: SpillSamples.ids[1], holeIndex: 4,
                               keptStrokes: 5, keptBy: SpillSamples.me, keptAt: kept,
                               otherStrokes: 6, otherBy: SpillSamples.ids[2], otherAt: kept.addingTimeInterval(-120),
                               createdAt: kept, resolvedAt: nil)
    }

    /// Føringen fra `hullkort`, stående på hullet med konflikten.
    static func model() -> RundeModel {
        let model = SpillSamples.foeringModel()
        if let game = model.game {
            model.previewConflicts([conflict(roundID: game.roundID)])
            model.goTo(hole: 4)
        }
        return model
    }
}

/// Skjermprøven `markorkonfliktark`: føringen med arket åpent.
struct MarkerConflictSheetSample: View {
    @State private var model = MarkerConflictSamples.model()
    @State private var shows = true

    var body: some View {
        NavigationStack { RundeView(model: model) }
            .tint(Color.ddForestInk)
            .sheet(isPresented: $shows) {
                if let conflict = model.conflicts.first, let game = model.game {
                    MarkorKonfliktArk(title: "Hull \(game.holeNumber(conflict.holeIndex)) · \(game.name(conflict.memberID))",
                                      options: model.options(conflict)) { _ in }
                }
            }
    }
}

#Preview("Markørkonflikt") {
    NavigationStack { RundeView(model: MarkerConflictSamples.model()) }
        .tint(Color.ddForestInk)
}

#Preview("Markørkonflikt · arket") { MarkerConflictSheetSample() }
#endif
