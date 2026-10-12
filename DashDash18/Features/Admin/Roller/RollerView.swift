import SwiftUI

/// «Roller» (steg 2, sql/044): rollene i klubben med rettighetene som fire brytere. Eieren lager,
/// gir nytt navn, endrer rettigheter og sletter roller. Eierrollens rettigheter står fast.
struct RollerView: View {
    @Environment(\.clubContext) private var context
    @Environment(ClubModel.self) private var club: ClubModel?
    @State private var model: ClubRolesModel?

    var body: some View {
        Group {
            if let model {
                RollerList(model: model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Roller")
        .ddNavigationChrome()
        .task(id: context?.clubID) {
            guard let context else { return }
            let model = ClubRolesModel(context: context)
            let club = club
            model.onChange = { await club?.loadRoleAccess() }
            self.model = model
            await model.load()
        }
    }
}

private struct RollerList: View {
    @Bindable var model: ClubRolesModel
    @State private var creating = false
    @State private var renaming: ClubRoleRow?
    @State private var newName = ""
    @State private var deleting: ClubRoleRow?

    private var canEdit: Bool { model.viewer.canManageRoles }

    var body: some View {
        DDList {
            if model.hasLoaded && !model.isAvailable {
                ContentUnavailableView("Ingen roller ennå", systemImage: "person.badge.key",
                                       description: Text("Rollene kommer når klubben er oppdatert."))
            }
            ForEach(model.roles) { role in
                section(role)
            }
        }
        .disabled(model.isSaving)
        .refreshable { await model.load() }
        .toolbar {
            if canEdit && model.isAvailable {
                ToolbarItem(placement: .primaryAction) {
                    Button { creating = true } label: {
                        Label("Ny rolle", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $creating) {
            NavigationStack { NewRoleView(model: model) }
        }
        .alert("Nytt navn", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
               presenting: renaming) { role in
            TextField("Navn", text: $newName)
            Button("Lagre") {
                Task { _ = await model.save(id: role.id, name: newName, rights: role.rightSet) }
            }
            Button("Avbryt", role: .cancel) {}
        }
        .confirmationDialog(deleting.map { "Slette «\($0.name)»?" } ?? "",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { role in
            Button("Slett", role: .destructive) { Task { _ = await model.delete(role) } }
            Button("Avbryt", role: .cancel) {}
        }
        // Mens «Ny rolle» er åpen, viser den feilen selv.
        .messageAlert("Det gikk ikke", text: creating ? .constant(nil) : $model.error)
    }

    private func section(_ role: ClubRoleRow) -> some View {
        let count = model.memberCount(of: role.id)
        return Section {
            ForEach(ClubRight.allCases, id: \.self) { right in
                Toggle(isOn: Binding(
                    get: { role.rightSet.contains(right) },
                    set: { on in
                        var rights = role.rightSet
                        if on { rights.insert(right) } else { rights.remove(right) }
                        Task { _ = await model.save(id: role.id, name: role.name, rights: rights) }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(right.title)
                        Text(right.detail)
                            .font(.ddCaption)
                            .foregroundStyle(Color.ddInkSecondary)
                    }
                }
                .disabled(!canEdit || role.isOwner)
            }
            if canEdit {
                Button("Gi nytt navn") {
                    newName = role.name
                    renaming = role
                }
                if !role.isOwner {
                    Button("Slett rolle", role: .destructive) { deleting = role }
                        .disabled(count > 0)
                }
            }
        } header: {
            DDHeader("\(role.name) · \(count == 1 ? "1 medlem" : "\(count) medlemmer")")
        } footer: {
            if role.isOwner {
                DDFooter("Eier har alle rettighetene, og styrer roller og eierskap.")
            } else if canEdit && count > 0 {
                DDFooter("Ta rollen fra medlemmene i Troppen før den kan slettes.")
            }
        }
    }
}

/// Ny rolle: navn og rettigheter.
private struct NewRoleView: View {
    @Bindable var model: ClubRolesModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var rights: Set<ClubRight> = []

    var body: some View {
        DDForm {
            Section {
                TextField("Navn", text: $name)
                    .textInputAutocapitalization(.sentences)
            } header: {
                DDHeader("Navn")
            }
            Section {
                ForEach(ClubRight.allCases, id: \.self) { right in
                    Toggle(right.title, isOn: Binding(
                        get: { rights.contains(right) },
                        set: { rights = $0 ? rights.union([right]) : rights.subtracting([right]) }
                    ))
                }
            } header: {
                DDHeader("Rettigheter")
            } footer: {
                DDFooter("Uten rettigheter er rollen et merke, som Sosialkomité.")
            }
        }
        .navigationTitle("Ny rolle")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(model.isSaving)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Avbryt") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Lagre") {
                    Task {
                        if await model.save(id: nil, name: name, rights: rights) { dismiss() }
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .messageAlert("Det gikk ikke", text: $model.error)
    }
}
