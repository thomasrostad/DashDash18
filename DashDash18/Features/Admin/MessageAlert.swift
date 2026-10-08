import SwiftUI

extension View {
    /// Et varsel med «OK» som viser teksten så lenge den ikke er nil, og tømmer den når det lukkes.
    /// Brukes for «Det gikk ikke» og «Ferdig» på arrangørsiden.
    func messageAlert(_ title: String, text: Binding<String?>) -> some View {
        alert(title, isPresented: Binding(get: { text.wrappedValue != nil },
                                          set: { if !$0 { text.wrappedValue = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(text.wrappedValue ?? "")
        }
    }
}
