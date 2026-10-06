import SwiftUI

/// Form med krem bakgrunn og kort-fargede rader. Bruk i stedet for `Form`.
struct DDForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            Group { content }
                .listRowBackground(Color.ddCard)
        }
        .ddListStyle()
    }
}

/// List med krem bakgrunn og kort-fargede rader. Bruk i stedet for `List`.
struct DDList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        List {
            Group { content }
                .listRowBackground(Color.ddCard)
        }
        .ddListStyle()
    }
}

/// `Section("Tittel")` med overskrift i designsystemet.
struct DDSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Section {
            content
        } header: {
            DDHeader(title)
        }
    }
}

/// Seksjonsoverskrift i en liste: mono versaler, som `.gg-section-label`.
struct DDHeader: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .ddEyebrow()
            .accessibilityAddTraits(.isHeader)
    }
}

/// Forklaring under en seksjon.
struct DDFooter: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.ddCaption)
            .foregroundStyle(Color.ddInkSecondary)
    }
}

extension View {
    /// Feilmelding i en rad eller under et kort.
    func ddErrorStyle() -> some View {
        font(.ddCallout).foregroundStyle(Color.ddError)
    }

    /// Advarsel eller noe som venter (før: oransje).
    func ddWarningStyle() -> some View {
        foregroundStyle(Color.ddRustText)
    }
}

#Preview("Liste") {
    NavigationStack {
        DDList {
            Section {
                Text("Thomas")
                LabeledContent("Handicap", value: "12,4")
            } header: {
                DDHeader("Troppen")
            } footer: {
                DDFooter("Navnet er det de andre ser.")
            }
            Section {
                Label("Klarte ikke å lagre.", systemImage: "exclamationmark.triangle").ddErrorStyle()
            }
        }
        .navigationTitle("Tropp")
        .ddNavigationChrome()
    }
}
