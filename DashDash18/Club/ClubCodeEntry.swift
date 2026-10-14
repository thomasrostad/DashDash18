import SwiftUI

/// Feltet for invitasjonen til en klubb: koden eller hele lenken (også hele meldingen), med
/// «Lim inn» som henter fra utklippstavla uten å spørre om lov hver gang (`PasteButton`).
struct ClubCodeEntrySection: View {
    @Binding var text: String
    var isBusy = false
    var header = "Har du fått en invitasjon?"
    /// «Bli med», også rett etter «Lim inn».
    let onSubmit: () -> Void

    /// Koden eller lenken er gyldig (10–12 tegn, eller en klubblenke).
    private var isValid: Bool { ClubInvite.parse(text) != nil }

    var body: some View {
        Section {
            TextField("Lenke eller kode", text: $text,
                      prompt: Text("Lenke eller kode").foregroundStyle(Color.ddInkSecondary))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .font(.ddBody)
                .submitLabel(.join)
                .onSubmit { if isValid { onSubmit() } }
            VStack(spacing: DDSpacing.s) {
                // Én hovedhandling (planen P7): aktiv når koden er gyldig, ellers en linje om hvorfor.
                Button(action: onSubmit) {
                    ZStack {
                        Text("Bli med").opacity(isBusy ? 0 : 1)
                        if isBusy { ProgressView().tint(DDToken.buttonPrimaryText.color) }
                    }
                }
                .buttonStyle(.dd(.primary, fullWidth: true))
                .disabled(isBusy || !isValid)
                if !isValid {
                    Text(text.isEmpty ? "Skriv inn koden først" : "Koden har 10–12 bokstaver og tall")
                        .font(.ddCaption)
                        .foregroundStyle(Color.ddInkSecondary)
                }

                PasteButton(payloadType: String.self) { strings in
                    guard let pasted = strings.first else { return }
                    Task { @MainActor in
                        text = ClubInvite.parse(pasted)?.code ?? pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSubmit()
                    }
                }
                // Systemknappen spør ikke om lov hver gang; teksten følger telefonens språk
                // («Lim inn» på norsk telefon).
                .buttonBorderShape(.capsule)
                .labelStyle(.titleAndIcon)
                .tint(Color.ddForestInk)
            }
            .frame(maxWidth: .infinity)
        } header: {
            DDHeader(header)
        } footer: {
            DDFooter(ClubInvite.whereToGetIt)
        }
    }
}
