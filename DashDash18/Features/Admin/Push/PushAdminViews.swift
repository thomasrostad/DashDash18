import SwiftUI

/// «Hva blir push»: arrangøren slår kategorier av for hele klubben.
struct ClubPushSettingsView: View {
    @Environment(\.clubContext) private var context
    @State private var model: ClubPushSettingsModel?

    var body: some View {
        Group {
            if let model {
                ClubPushSettingsList(model: model)
            } else {
                ContentUnavailableView("Ingen klubb", systemImage: "bell", description: Text("Velg en klubb først."))
            }
        }
        .navigationTitle("Hva blir push")
        .ddNavigationChrome()
        .task(id: context?.clubID) {
            guard let context else { return }
            let model = ClubPushSettingsModel(context: context)
            self.model = model
            await model.load()
        }
    }
}

private struct ClubPushSettingsList: View {
    let model: ClubPushSettingsModel

    var body: some View {
        DDList {
            if model.hasLoaded {
                Section {
                    ForEach(ClubPushPlan.toggles) { toggle in
                        Toggle(isOn: Binding(
                            get: { model.isOn(toggle.key) },
                            set: { on in Task { await model.set(toggle.key, on: on) } }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(toggle.title)
                                Text(toggle.subtitle)
                                    .font(.ddCallout)
                                    .foregroundStyle(Color.ddInkSecondary)
                            }
                        }
                        .disabled(model.isSaving)
                    }
                } header: {
                    DDHeader("For hele klubben")
                } footer: {
                    DDFooter(ClubPushPlan.footer)
                }
                Section {
                    ForEach(ClubPushPlan.locked, id: \.self) { category in
                        LabeledContent {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(Color.ddInkSecondary)
                                .accessibilityLabel("Alltid på")
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.title)
                                Text(PushCategories.subtitle(category))
                                    .font(.ddCallout)
                                    .foregroundStyle(Color.ddInkSecondary)
                            }
                        }
                    }
                } header: {
                    DDHeader("Alltid push")
                } footer: {
                    DDFooter(ClubPushPlan.lockedReason)
                }
            } else if model.error == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            if let error = model.error {
                Text(error)
                    .ddErrorStyle()
            }
        }
        .refreshable { await model.load() }
    }
}

/// «Hvem har push»: hvem i klubben som har en telefon registrert for push.
struct PushStatusView: View {
    @Environment(\.clubContext) private var context
    @State private var model: PushStatusModel?

    var body: some View {
        Group {
            if let model {
                PushStatusList(model: model)
            } else {
                ContentUnavailableView("Ingen klubb", systemImage: "iphone", description: Text("Velg en klubb først."))
            }
        }
        .navigationTitle("Hvem har push")
        .ddNavigationChrome()
        .task(id: context?.clubID) {
            guard let context else { return }
            let model = PushStatusModel(context: context)
            self.model = model
            await model.load()
        }
    }
}

private struct PushStatusList: View {
    let model: PushStatusModel

    var body: some View {
        DDList {
            if let sections = model.sections {
                Section {
                    ForEach(sections.on) { entry in PushStatusRowView(entry: entry) }
                } header: {
                    DDHeader("Har push (\(sections.on.count))")
                } footer: {
                    DDFooter("\(sections.summary). Sist sett er når appen sist meldte seg på en av telefonene.")
                }
                if !sections.off.isEmpty {
                    Section {
                        ForEach(sections.off) { entry in PushStatusRowView(entry: entry) }
                    } header: {
                        DDHeader("Uten push (\(sections.off.count))")
                    } footer: {
                        DDFooter("Har logget inn, men ikke slått på varsler i appen.")
                    }
                }
                if !sections.noLogin.isEmpty {
                    Section {
                        ForEach(sections.noLogin) { entry in PushStatusRowView(entry: entry) }
                    } header: {
                        DDHeader("Ledige navn (\(sections.noLogin.count))")
                    } footer: {
                        DDFooter("Ingen har logget inn med disse navnene ennå.")
                    }
                }
            } else if model.error == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            if let error = model.error {
                Text(error)
                    .ddErrorStyle()
            }
        }
        .refreshable { await model.load() }
    }
}

private struct PushStatusRowView: View {
    let entry: PushStatusEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.name)
            if case .on(_, let lastSeenAt) = entry.state {
                HStack(spacing: 4) {
                    if let devices = entry.devicesText { Text(devices) }
                    if let lastSeenAt {
                        Text("· sist sett \(lastSeenAt, format: .relative(presentation: .named))")
                    }
                }
                .font(.dd(.sans, size: 12, relativeTo: .caption))
                .foregroundStyle(Color.ddInkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
