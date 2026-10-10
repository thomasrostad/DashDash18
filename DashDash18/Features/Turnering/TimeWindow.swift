import Foundation
import GolfgutuCore
import SwiftUI

/// Turneringer med tidsvindu, «Spill når det passer» (fase 26, `sql/042_tidsvindu.sql`).
nonisolated enum TimeWindowFeature {
    /// Av til 042 er kjørt. Med flagget av finnes ikke valget, og `auto_count` hentes ikke.
    static let isEnabled = false
}

nonisolated enum TimeWindowText {
    /// «Spill når det passer · 1. okt–31. okt · de beste 3 teller».
    static func summary(startsOn: String?, endsOn: String?, best: Int?) -> String {
        var parts = ["Spill når det passer"]
        if let s = startsOn, let e = endsOn {
            parts.append("\(EveningDates.dayMonthText(s))–\(EveningDates.dayMonthText(e))")
        }
        parts.append(best.map { $0 == 1 ? "den beste runden teller" : "de beste \($0) teller" } ?? "alle runder teller")
        return parts.joined(separator: " · ")
    }

    static let footer = "Påmeldte spiller når det passer i perioden, så mange runder de vil. Rundene teller av seg selv, også løse runder, og de beste teller i tabellen."
}

/// Valget i «Ny turnering» for liga og morro: av/på, og hvor mange runder som teller.
struct TimeWindowSection: View {
    @Binding var draft: CompetitionDraft

    var body: some View {
        Section {
            Toggle("Spill når det passer", isOn: Binding(get: { draft.playsWhenItSuits }, set: { on in
                draft.playsWhenItSuits = on
                if on { draft.hasPeriod = true }
            }))
            if draft.playsWhenItSuits {
                Toggle("Alle runder teller", isOn: Binding(
                    get: { draft.leagueRules.bestRounds == nil },
                    set: { draft.leagueRules.bestRounds = $0 ? nil : 3 }))
                if let best = draft.leagueRules.bestRounds {
                    Stepper("De beste \(best) teller", value: Binding(
                        get: { best }, set: { draft.leagueRules.bestRounds = max(1, min(20, $0)) }), in: 1...20)
                }
            }
        } header: {
            DDHeader("Tidsvindu")
        } footer: {
            DDFooter(TimeWindowText.footer)
        }
    }
}
