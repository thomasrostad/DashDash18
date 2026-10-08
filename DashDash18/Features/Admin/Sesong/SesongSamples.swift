#if DEBUG
import Foundation
import GolfgutuCore
import SwiftUI

/// «Turneringen» med oppdiktede sesonger, uten nett (`-DDDesignScreen regler` lander på den aktive
/// sesongen; `reglerendre` er regelredigeringen for den, en stableford-serie med ett valg endret).
struct SesongSampleScreen: View {
    let screen: DesignScreenSamples.Screen
    @State private var model = SesongAdminModel(preview: Self.seasons)

    static var club: UUID { KonkurranseSamples.club }

    static var seasons: [SeasonRow] {
        var stableford = RulesetTemplate.stablefordSeries.rules
        stableford.evenings = 10
        return [
            SeasonRow(id: TavlaSamples.id(9101), clubID: club, name: "Høst 2026", status: .active, rules: stableford),
            SeasonRow(id: TavlaSamples.id(9102), clubID: club, name: "Vår 2026", status: .finished, rules: .golfgutu),
        ]
    }

    var body: some View {
        NavigationStack {
            switch screen {
            case .reglerendre:
                if let season = model.seasons.first {
                    RulesetEditorView(model: model, season: season)
                }
            default:
                SesongLandingView(model: model, competitions: KonkurranseSamples.list())
            }
        }
    }
}

/// «Ny turnering» og «Alle turneringer» med oppdiktede data (`nyturnering`, `nyturnering2`, `turneringer`).
struct TurneringSampleScreen: View {
    let screen: DesignScreenSamples.Screen

    /// 8. oktober 2026, så navneforslaget blir «Høst 2026».
    static let now = Date(timeIntervalSince1970: 1_791_453_600)

    static func model() -> NewTournamentModel {
        // Bare en ferdig sesong, så den nye serien starter med en gang.
        let seasons = SesongAdminModel(preview: [SesongSampleScreen.seasons[1]])
        return NewTournamentModel(preview: KonkurranseSamples.list(), seasons: seasons, offersPrivate: false,
                                  members: TavlaSamples.members, now: now)
    }

    var body: some View {
        NavigationStack {
            switch screen {
            case .nyturnering2:
                let model = Self.model()
                NyTurneringDetailsView(model: model, draft: model.draft(for: .stablefordSeries), onDone: {})
            case .turneringer:
                AlleTurneringerView(model: SesongAdminModel(preview: SesongSampleScreen.seasons),
                                    competitions: KonkurranseSamples.list())
            default:
                NyTurneringView(model: Self.model(), onDone: {})
            }
        }
        .tint(Color.ddForestInk)
    }
}
#endif
