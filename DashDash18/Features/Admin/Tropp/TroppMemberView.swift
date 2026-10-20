import GolfgutuCore
import SwiftUI

/// Én spiller i troppen: navn, handicap, seeding, roller, innlogging og status.
struct TroppMemberView: View {
    let model: TroppModel
    let memberID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var handicapText = ""
    @State private var confirming: TroppAction?
    @State private var isSaving = false
    @State private var confirmsTransfer = false

    var body: some View {
        Group {
            if let row = model.row(memberID) {
                form(row)
            } else {
                ContentUnavailableView("Spilleren er borte", systemImage: "person.slash")
            }
        }
        .navigationTitle(model.row(memberID)?.displayName ?? "Spiller")
        .ddNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
        .disabled(model.isBusy(memberID))
        .discardChangesGuard(hasChanges: model.row(memberID).map(isEdited) ?? false)
        .onAppear(perform: resetFields)
    }

    private func form(_ row: ClubMemberRow) -> some View {
        DDForm {
            if row.status == .pending {
                Section {
                    Button("Godkjenn") { run(.approve) }
                    Button("Avvis", role: .destructive) { confirming = .reject }
                } header: {
                    DDHeader("Venter på godkjenning")
                } footer: {
                    DDFooter("Avvis arkiverer raden og frigjør innloggingen, så personen kan prøve igjen med riktig navn.")
                }
            }

            if row.isParticipant {
                participantSection(row)
            }

            detailsSection(row)

            if model.availability(.setSeedGroup, for: row).isVisible {
                seedSection(row)
            }

            if row.status == .active, !row.isParticipant {
                if model.roles.isAvailable {
                    clubRolesSection(row)
                } else {
                    rolesSection(row)
                }
            }

            loginSection(row)
            statusSection(row)
        }
        .confirmationDialog(
            confirming.map(confirmTitle) ?? "",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible,
            presenting: confirming
        ) { action in
            Button(confirmButton(action), role: action == .makeMember ? nil : .destructive) { run(action) }
            Button("Avbryt", role: .cancel) {}
        }
        .confirmationDialog("Gi eierskapet til \(row.displayName)?", isPresented: $confirmsTransfer,
                            titleVisibility: .visible) {
            Button("Overfør eierskap", role: .destructive) {
                Task { _ = await model.roles.transferOwnership(to: memberID) }
            }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text("Du mister Eier, men beholder de andre rollene dine.")
        }
        .messageAlert("Det gikk ikke", text: Bindable(model.roles).error)
    }

    /// Rollene (sql/044): én bryter per rolle. Bare roller du kan gi, kan endres.
    private func clubRolesSection(_ row: ClubMemberRow) -> some View {
        let roles = model.roles
        let viewer = roles.viewer
        let current = roles.roleIDs(of: memberID)
        let canTransfer = ClubRoleInput.canTransferOwnership(viewer: viewer, to: row, me: model.context.memberID,
                                                             memberIsOwner: roles.isOwner(memberID))
        return Section {
            ForEach(roles.roles) { role in
                Toggle(role.name, isOn: Binding(
                    get: { current.contains(role.id) },
                    set: { on in
                        let next = ClubRoleInput.toggled(current, role: role.id, on: on)
                        Task { _ = await roles.setRoles(next, for: memberID) }
                    }
                ))
                .disabled(!viewer.canGrant(role) || roles.isSaving)
            }
            if canTransfer {
                Button("Overfør eierskap") { confirmsTransfer = true }
                    .disabled(roles.isSaving)
            }
        } header: {
            DDHeader("Roller")
        } footer: {
            DDFooter("Du kan bare gi roller med rettigheter du selv har. Bare en eier gir Eier.")
        }
    }

    private func detailsSection(_ row: ClubMemberRow) -> some View {
        Section {
            TextField("Navn", text: $name)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
            TextField("Handicapindeks (valgfritt)", text: $handicapText)
                .keyboardType(.numbersAndPunctuation)
            if isEdited(row) {
                Button("Lagre") {
                    isSaving = true
                    Task {
                        if await model.saveDetails(of: memberID, name: name, handicap: handicapText) {
                            resetFields()
                        }
                        isSaving = false
                    }
                }
                .disabled(isSaving)
            }
        } header: {
            DDHeader("Navn og handicap")
        } footer: {
            DDFooter("Plusshandicap skrives med «+».")
        }
    }

    private func seedSection(_ row: ClubMemberRow) -> some View {
        Section {
            Picker("Seedet gruppe", selection: Binding(
                get: { row.seedGroup },
                set: { group in Task { await model.setSeedGroup(group, of: memberID) } }
            )) {
                Text("Ingen gruppe").tag(Int?.none)
                ForEach(model.seedGroups, id: \.number) { group in
                    Text(TroppSeeding.label(group.number, groups: model.seedGroups)).tag(Int?.some(group.number))
                }
                if let current = row.seedGroup, !model.seedGroups.contains(where: { $0.number == current }) {
                    Text(TroppSeeding.label(current, groups: model.seedGroups)).tag(Int?.some(current))
                }
            }
        } header: {
            DDHeader("Seeding")
        } footer: {
            if let season = model.seasonName {
                Text("Gruppene kommer fra regelsettet i \(season).")
            } else {
                Text("Ingen aktiv turnering. Gruppene er fra Golfgutu-oppsettet.")
            }
        }
    }

    private func rolesSection(_ row: ClubMemberRow) -> some View {
        let organizer = model.availability(row.isOrganizer ? .revokeOrganizer : .grantOrganizer, for: row)
        let treasurer = model.availability(row.isTreasurer ? .revokeTreasurer : .grantTreasurer, for: row)
        return Section {
            Toggle("Arrangør", isOn: Binding(
                get: { row.isOrganizer },
                set: { run($0 ? .grantOrganizer : .revokeOrganizer) }
            ))
            .disabled(!organizer.isAllowed)
            Toggle("Kasserer", isOn: Binding(
                get: { row.isTreasurer },
                set: { run($0 ? .grantTreasurer : .revokeTreasurer) }
            ))
            .disabled(!treasurer.isAllowed)
        } header: {
            DDHeader("Roller")
        } footer: {
            if let reason = organizer.reason ?? treasurer.reason {
                Text(reason)
            }
        }
    }

    @ViewBuilder
    private func loginSection(_ row: ClubMemberRow) -> some View {
        let release = model.availability(.releaseLogin, for: row)
        Section {
            if row.userID == nil {
                Label("Har ikke logget inn", systemImage: "person.crop.circle.badge.questionmark")
                    .foregroundStyle(Color.ddInkSecondary)
            } else {
                Label(row.id == model.context.memberID ? "Dette er deg" : "Logget inn",
                      systemImage: "person.crop.circle.badge.checkmark")
            }
            if release.isVisible {
                Button("Frigjør innlogging", role: .destructive) { confirming = .releaseLogin }
                    .disabled(!release.isAllowed)
            }
        } header: {
            DDHeader("Innlogging")
        } footer: {
            if let reason = release.reason {
                Text(reason)
            } else if release.isVisible {
                Text("Bruk dette hvis spilleren logget inn med feil e-post. Navnet blir ledig igjen og kan tas på nytt.")
            }
        }
    }

    /// En deltaker i en av klubbens turneringer (sql/059): ser bare turneringen, ikke klubben.
    private func participantSection(_ row: ClubMemberRow) -> some View {
        let makeMember = model.availability(.makeMember, for: row)
        return Section {
            if makeMember.isVisible {
                Button("Gjør til medlem") { confirming = .makeMember }
                    .disabled(!makeMember.isAllowed)
            }
        } header: {
            DDHeader("Deltaker i turnering")
        } footer: {
            DDFooter(makeMember.reason
                     ?? "Meldte seg på en av klubbens turneringer uten å være medlem. Ser turneringen og rundene sine, ikke resten av klubben.")
        }
    }

    @ViewBuilder
    private func statusSection(_ row: ClubMemberRow) -> some View {
        let archive = model.availability(.archive, for: row)
        let restore = model.availability(.restore, for: row)
        let delete = model.availability(.delete, for: row)
        if archive.isVisible || restore.isVisible || delete.isVisible {
            Section {
                if archive.isVisible {
                    Button("Arkiver", role: .destructive) { confirming = .archive }
                        .disabled(!archive.isAllowed)
                }
                if restore.isVisible {
                    Button("Gjenopprett") { run(.restore) }
                        .disabled(!restore.isAllowed)
                }
                if delete.isVisible {
                    Button("Slett navnet", role: .destructive) { confirming = .delete }
                        .disabled(!delete.isAllowed)
                }
            } footer: {
                if let reason = archive.reason ?? restore.reason ?? delete.reason {
                    Text(reason)
                } else if archive.isVisible {
                    Text("En arkivert spiller er ute av troppen, men runder og historikk står.")
                }
            }
        }
    }

    // MARK: Hjelpere

    private func isEdited(_ row: ClubMemberRow) -> Bool {
        name != row.displayName || handicapText != TroppInput.handicapText(row.handicapIndex)
    }

    private func resetFields() {
        guard let row = model.row(memberID) else { return }
        name = row.displayName
        handicapText = TroppInput.handicapText(row.handicapIndex)
    }

    private func run(_ action: TroppAction) {
        Task {
            await model.perform(action, on: memberID)
            if action == .delete, model.row(memberID) == nil {
                dismiss()
            }
        }
    }

    private func confirmTitle(_ action: TroppAction) -> String {
        let name = model.row(memberID)?.displayName ?? "spilleren"
        return switch action {
        case .reject: "Avvise \(name)?"
        case .releaseLogin: "Frigjøre innloggingen til \(name)?"
        case .archive: "Arkivere \(name)?"
        case .delete: "Slette \(name)?"
        case .makeMember: "Gjøre \(name) til medlem?"
        default: ""
        }
    }

    private func confirmButton(_ action: TroppAction) -> String {
        switch action {
        case .reject: "Avvis"
        case .releaseLogin: "Frigjør"
        case .archive: "Arkiver"
        case .delete: "Slett"
        case .makeMember: "Gjør til medlem"
        default: "OK"
        }
    }
}
