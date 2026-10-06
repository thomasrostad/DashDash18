import SwiftUI

struct DegView: View {
    let config: AppConfig

    var body: some View {
        List {
            Section {
                ContentUnavailableView(
                    "Ikke logget inn",
                    systemImage: "person.crop.circle",
                    description: Text("Innlogging kommer snart.")
                )
            }
            Section("Om appen") {
                LabeledContent("Miljø", value: config.environment.displayName)
                LabeledContent("Database", value: config.projectRef)
            }
        }
    }
}

#Preview {
    NavigationStack {
        DegView(config: .preview)
    }
}
