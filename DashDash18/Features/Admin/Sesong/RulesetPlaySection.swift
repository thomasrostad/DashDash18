import GolfgutuCore
import SwiftUI

/// Føring og visning (regelvern, inspirert av Golfify): maks slag per hull, låst kort etter levering og
/// hvor mange av de siste hullene «Skjul de siste hullene» skjuler. Alt er som i dag til arrangøren endrer det.
struct RulesetPlaySection: View {
    @Binding var draft: RulesetDraft

    var body: some View {
        Section {
            Picker(selection: $draft.maxStrokesKind) {
                ForEach(RulesetDraft.MaxStrokesKind.allCases, id: \.self) { Text($0.title).tag($0) }
            } label: {
                RuleFieldLabel(title: "Maks slag per hull", changeNote: draft.changeNote(.maxStrokes))
            }
            if draft.maxStrokesKind == .fixed {
                RuleStepper("Høyst", value: $draft.fixedMaxStrokes, in: Ruleset.MaxStrokes.fixedRange)
            }
            Toggle(isOn: $draft.rules.play.lockSubmittedCards) {
                RuleFieldLabel(title: "Lås kortet når det er levert",
                               help: CardLockFeature.isAvailable ? nil : "Virker når databasen er oppdatert (sql/058).",
                               changeNote: draft.changeNote(.lockSubmittedCards))
            }
            RuleStepper("Skjul de siste hullene", value: $draft.rules.play.hiddenHoles,
                        in: Ruleset.PlayRules.hiddenHolesRange,
                        help: "Antallet når runden settes opp med «Skjul de siste hullene».",
                        changeNote: draft.changeNote(.hiddenHoles))
        } header: {
            DDHeader(RulesetSection.play.title)
        } footer: {
            RuleSectionFooter(text: footer, issues: draft.issues(in: .play))
        }
    }

    private var footer: String {
        var parts: [String] = []
        switch draft.rules.play.maxStrokes {
        case .off: parts.append("Uten grense kan du føre opp til 12 slag på et hull.")
        case .netDoubleBogey: parts.append("Netto dobbel bogey: par + 2 + slagene spilleren får på hullet.")
        case .fixed(let n): parts.append("Stepperen stopper på \(n).")
        }
        if draft.rules.play.lockSubmittedCards {
            parts.append("Markøren leverer kortet når alle hullene er ført. Etterpå kan bare arrangøren endre det eller åpne det igjen.")
        }
        return parts.joined(separator: " ")
    }
}
