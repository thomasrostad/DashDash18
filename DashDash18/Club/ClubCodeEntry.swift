import SwiftUI

/// Feltet for invitasjonen til en klubb: koden eller hele lenken (også hele meldingen), med
/// «Lim inn» som henter fra utklippstavla uten å spørre om lov hver gang (`PasteButton`).
struct ClubCodeEntrySection: View {
    @Binding var text: String
    var isBusy = false
    var header = "Har du fått en invitasjon?"
    /// «Finn klubben», også rett etter «Lim inn».
    let onSubmit: () -> Void

    var body: some View {
        Section {
            TextField("Lenke eller kode", text: $text)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .font(.dd(.mono, size: 14, relativeTo: .body))
                .submitLabel(.search)
                .onSubmit(onSubmit)
            HStack(spacing: DDSpacing.m) {
                PasteButton(payloadType: String.self) { strings in
                    guard let pasted = strings.first else { return }
                    Task { @MainActor in
                        text = ClubInvite.parse(pasted)?.code ?? pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSubmit()
                    }
                }
                .buttonBorderShape(.capsule)
                .labelStyle(.titleAndIcon)
                .tint(Color.ddForestInk)
                Spacer(minLength: 0)
                Button(action: onSubmit) {
                    HStack(spacing: DDSpacing.s) {
                        Text("Finn klubben")
                        if isBusy { ProgressView() }
                    }
                }
                .buttonStyle(.dd(.primary, compact: true))
                .disabled(isBusy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            DDHeader(header)
        } footer: {
            DDFooter(ClubInvite.whereToGetIt)
        }
    }
}
