import GolfgutuCore
import SwiftUI

/// Deg → Varsler: slå på push, velg gruppene og hva du får push om, hvordan tråden varsler, og
/// e-post når du ikke har varsler på. Vises bare når `PushFeature.isEnabled` er på (se `DegView`).
/// Uten sql/046 (ingen grupper) vises kategoriene som før.
struct PushSettingsView: View {
    @Environment(\.dayTerm) private var dayTerm
    let context: ClubContext
    @Environment(PushRegistrar.self) private var registrar
    @Environment(\.scenePhase) private var scenePhase
    @State private var preferences: PushPreferences?
    @State private var club = ClubPushSettings()
    /// nil når 046 ikke er kjørt.
    @State private var groups: PushGroupSettings?
    @State private var groupMap = PushGroupMap.local
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
                if let groups {
                    ForEach(PushGroup.shown(isOrganizer: context.isOrganizer), id: \.self) { group in
                        groupSection(group, groups: groups, preferences: preferences)
                    }
                    DDSection("E-post") {
                        Toggle(isOn: Binding(
                            get: { groups.emailFallback },
                            set: { on in
                                var next = groups
                                next.emailFallback = on
                                Task { await saveGroups(next) }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("E-post når du ikke har varsler på")
                                Text("Beskjeder, purring, påminnelser og plass fra ventelista.")
                                    .font(.ddCallout)
                                    .foregroundStyle(Color.ddInkSecondary)
                            }
                        }
                    }
                } else {
                    DDSection("Hva du får push om") {
                        ForEach(PushCategories.shownToPlayer, id: \.self) { category in
                            categoryToggle(category, preferences: preferences)
                        }
                    }
                    DDSection(DayTerm.capitalized(dayTerm.possessive) + " tråd") {
                        threadPicker(preferences)
                    }
                }
            } else if error == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            if let error {
                Text(error)
                    .foregroundStyle(Color.ddRustText)
                if preferences == nil {
                    Button("Prøv igjen") { Task { await load() } }
                        .fontWeight(.medium)
                }
            }
        }
        .navigationTitle("Varsler")
        .task {
            await registrar.refreshAuthorization()
            await load()
        }
        .refreshable { await load() }
        // Tilbake fra Innstillinger: tillatelsen kan være gitt eller tatt bort.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await registrar.refreshAuthorization() } }
        }
    }

    /// Én gruppe: bryteren, og når den er på, kategoriene under (og tråden under Sosialt).
    @ViewBuilder
    private func groupSection(_ group: PushGroup, groups: PushGroupSettings, preferences: PushPreferences) -> some View {
        DDSection(group.title(term: dayTerm)) {
            Toggle(isOn: Binding(
                get: { groups.isOn(group) },
                set: { on in
                    var next = groups
                    next.set(group, on: on)
                    Task { await saveGroups(next) }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Varsler")
                    Text(group.subtitle(term: dayTerm))
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddInkSecondary)
                }
            }
            if groups.isOn(group) {
                ForEach(groupMap.categories(in: group, shown: PushCategories.shownToPlayer), id: \.self) { category in
                    categoryToggle(category, preferences: preferences)
                }
                ForEach(groupMap.extraKinds(in: group), id: \.self) { kind in
                    if let title = PushGroupMap.kindTitle(kind, term: dayTerm) {
                        LabeledContent(title, value: "På")
                    }
                }
                if group == .social {
                    threadPicker(preferences)
                }
            }
        }
    }

    @ViewBuilder
    private func threadPicker(_ preferences: PushPreferences) -> some View {
        Picker(DayTerm.capitalized(dayTerm.possessive) + " tråd", selection: threadBinding(preferences)) {
            ForEach(ThreadPushMode.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .disabled(club.blocksThread)
        if club.blocksThread {
            Text("Arrangøren har slått av push fra tråden.")
                .font(.ddCallout)
                .foregroundStyle(Color.ddInkSecondary)
        }
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
                Text(blocked ? "Slått av av arrangøren" : PushCategories.subtitle(category, term: dayTerm))
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
            let groupSettings = try await store.loadGroups()
            if groupSettings != nil { groupMap = await store.loadGroupMap() }
            preferences = mine
            club = clubSettings
            groups = groupSettings
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

    private func saveGroups(_ next: PushGroupSettings) async {
        let before = groups
        groups = next
        do {
            groups = try await store.saveGroups(next)
            error = nil
        } catch {
            groups = before
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
                Text("Varsler er slått av for Atten i Innstillinger.")
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
