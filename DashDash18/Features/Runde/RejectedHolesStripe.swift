import SwiftUI

/// Stripa i føringen når hull i køen ble avvist av serveren (runden låst, ingen tilgang): tallene er
/// ikke lagret, og markøren må vite det. «OK» glemmer de avviste hullene (`RejectedHoles`).
struct AvvisteHullStripe: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        DDInfoStripe(tone: .blush) {
            VStack(alignment: .leading, spacing: DDSpacing.s) {
                Label(text, systemImage: "exclamationmark.triangle")
                    .labelStyle(DDIconLabelStyle())
                Button("OK", action: onDismiss)
                    .buttonStyle(.dd(.secondary, compact: true))
                    .accessibilityHint("Skjuler beskjeden om hullene som ikke ble lagret")
            }
        }
        .accessibilityElement(children: .contain)
    }
}
