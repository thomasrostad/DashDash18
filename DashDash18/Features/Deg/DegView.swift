import SwiftUI

struct DegView: View {
    let config: AppConfig
    let user: AuthUser
    @Environment(AuthModel.self) private var auth

    var body: some View {
        List {
            Section("Konto") {
                LabeledContent("Logget inn som", value: user.email ?? "ukjent e-post")
                Button("Logg ut", role: .destructive) {
                    Task { await auth.signOut() }
                }
            }
            Section("Om appen") {
                LabeledContent("Miljø", value: config.environment.displayName)
                LabeledContent("Database", value: config.projectRef)
            }
        }
    }
}
