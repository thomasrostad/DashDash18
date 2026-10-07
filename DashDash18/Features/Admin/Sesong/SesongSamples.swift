#if DEBUG
import Foundation
import GolfgutuCore
import SwiftUI

/// «Sesong og regler» med oppdiktede sesonger, uten nett
/// (`-DDDesignScreen regler`, `reglerendre` og `nysesong`).
struct SesongSampleScreen: View {
    let screen: DesignScreenSamples.Screen
    @State private var model = SesongAdminModel(preview: Self.seasons)

    static let club = UUID()

    static var seasons: [SeasonRow] {
        var changed = Ruleset.golfgutu
        changed.handicap.allowanceOverride = 0.85
        changed.table.counting = .init(unit: .evening, best: 5)
        changed.table.roundingStep = nil
        return [
            SeasonRow(id: UUID(), clubID: club, name: "Høst 2026", status: .active, rules: changed),
            SeasonRow(id: UUID(), clubID: club, name: "Vår 2026", status: .finished, rules: .golfgutu),
        ]
    }

    var body: some View {
        NavigationStack {
            switch screen {
            case .reglerendre:
                if let season = model.seasons.first {
                    RulesetEditorView(model: model, season: season)
                }
            case .nysesong:
                NySesongView(model: model)
            default:
                if let season = model.seasons.first {
                    SesongDetailView(model: model, seasonID: season.id)
                }
            }
        }
    }
}
#endif
