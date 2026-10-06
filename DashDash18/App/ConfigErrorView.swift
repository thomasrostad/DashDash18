import SwiftUI

/// Vises hvis miljøkonfigen mangler eller er feil, i stedet for å krasje.
struct ConfigErrorView: View {
    let error: AppConfig.LoadError

    var body: some View {
        ContentUnavailableView(
            "Mangler oppsett",
            systemImage: "exclamationmark.triangle",
            description: Text(message)
        )
        .ddScreenBackground()
    }

    private var message: String {
        switch error {
        case .missingFile(let name):
            "Fant ikke \(name) i appen. Legg fila i DashDash18/Config/."
        case .unreadable:
            "Konfigfila kunne ikke leses."
        case .missingValue(let key):
            "Konfigfila mangler \(key)."
        case .wrongEnvironment(let expected, let found):
            "Konfigfila er for «\(found)», men bygget forventer «\(expected.rawValue)»."
        case .secretKey:
            "Konfigfila inneholder en hemmelig nøkkel. Bruk publishable key."
        }
    }
}

#Preview {
    ConfigErrorView(error: .missingFile("Supabase-Test.plist"))
}
