import SwiftUI

/// Deg → Varsler: slå på push, velg hva du får push om, og hvordan tråden varsler.
/// Vises bare når `PushFeature.isEnabled` er på (se `DegView`).
struct PushSettingsView: View {
    let context: ClubContext
    @Environment(PushRegistrar.self) private var registrar
    @State private var preferences: PushPreferences?
    @State private var club = ClubPushSettings()
    @State private var error: String?

    private var store: PushSettingsStore {
        PushSettingsStore(client: context.client, memberID: context.memberID, clubID: context.clubID)
    }

    var body: some View {
        DDList {
            DDSection("Telefonen") {
                PushPermissionRow(status: registrar.status) {
                    Task { await registrar.requestAuthorization() }
                }
            }
            if let preferences {
                DDSection("Hva du får push om") {
                    ForEach(PushCategories.shownToPlayer, id: \.self) { category in
                        categoryToggle(category, preferences: preferences)
                    }
                }
                DDSection("Kveldens tråd") {
                    Picker("Tråden", selection: threadBinding(preferences)) {
                        ForEach(ThreadPushMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .disabled(club.blocksThread)
                    if club.blocksThread {
                        Text("Arrangøren har slått av push fra tråden.")
                            .font(.ddCallout)
                            .foregroundStyle(Color.ddInkSecondary)
                    }
                }
            } else if error == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            if let error {
                Text(error)
                    .foregroundStyle(Color.ddRustText)
            }
        }
        .navigationTitle("Varsler")
        .task { await load() }
    }

    private func categoryToggle(_ category: ActivityCategory, preferences: PushPreferences) -> some View {
        let blocked = club.blocks(category)
        return Toggle(isOn: Binding(
            get: { !blocked && preferences.isOn(category) },
            set: { on in
                var next = preferences
                next.set(category, on: on)
                Task { await save(next) }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                Text(blocked ? "Slått av av arrangøren" : PushCategories.subtitle(category))
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddInkSecondary)
            }
        }
        .disabled(blocked)
    }

    private func threadBinding(_ preferences: PushPreferences) -> Binding<ThreadPushMode> {
        Binding(
            get: { preferences.threadMode },
            set: { mode in
                var next = preferences
                next.threadMode = mode
                Task { await save(next) }
            }
        )
    }

    private func load() async {
        do {
            let (mine, clubSettings) = try await store.load()
            preferences = mine
            club = clubSettings
            error = nil
        } catch {
            self.error = error.message
        }
    }

    /// Viser valget med en gang, og ruller tilbake hvis databasen sier nei (som PWA-en).
    private func save(_ next: PushPreferences) async {
        let before = preferences
        preferences = next
        do {
            preferences = try await store.save(next)
            error = nil
        } catch {
            preferences = before
            self.error = "Klarte ikke å lagre: \(error.message)"
        }
    }
}

/// Status for varsler på telefonen, med knapp for å slå dem på.
private struct PushPermissionRow: View {
    let status: PushRegistrar.Status
    let enable: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        switch status {
        case .registered:
            LabeledContent("Varsler", value: "På")
        case .registering:
            LabeledContent("Varsler", value: "Kobler til …")
        case .notDetermined, .disabled:
            Button("Slå på varsler", action: enable)
                .fontWeight(.medium)
        case .denied:
            VStack(alignment: .leading, spacing: 6) {
                Text("Varsler er slått av for DashDash18 i Innstillinger.")
                Button("Åpne Innstillinger") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
                .fontWeight(.medium)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text("Fikk ikke slått på varsler: \(message)")
                Button("Prøv igjen", action: enable)
                    .fontWeight(.medium)
            }
        }
    }
}
