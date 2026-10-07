import SwiftUI

/// Ulagrede endringer i et arrangørskjema: «tilbake» og sveip ned forkaster ikke uten å spørre.
/// Med endringer byttes tilbake-knappen ut med «Avbryt», som spør først.
private struct DiscardChangesGuard: ViewModifier {
    let hasChanges: Bool
    /// Ark som alltid har «Avbryt» (nytt navn, ny bane). Uten endringer lukker den med en gang.
    let alwaysShowsCancel: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(hasChanges)
            .interactiveDismissDisabled(hasChanges)
            .toolbar {
                if hasChanges || alwaysShowsCancel {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Avbryt") {
                            if hasChanges { confirming = true } else { dismiss() }
                        }
                    }
                }
            }
            .confirmationDialog("Forkaste endringene?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Forkast endringene", role: .destructive) { dismiss() }
                Button("Fortsett å redigere", role: .cancel) {}
            } message: {
                Text("Det du har endret, er ikke lagret.")
            }
    }
}

extension View {
    /// Spør før ulagrede endringer forkastes (tilbake, «Avbryt» eller sveip ned).
    func discardChangesGuard(hasChanges: Bool, alwaysShowsCancel: Bool = false) -> some View {
        modifier(DiscardChangesGuard(hasChanges: hasChanges, alwaysShowsCancel: alwaysShowsCancel))
    }
}
