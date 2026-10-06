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

            detailsSection(row)

            if model.availability(.setSeedGroup, for: row).isVisible {
                seedSection(row)
            }

            if row.status == .active {
                rolesSection(row)
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
            Button(confirmButton(action), role: .destructive) { run(action) }
            Button("Avbryt", role: .cancel) {}
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
                    Task {
                        if await model.saveDetails(of: memberID, name: name, handicap: handicapText) {
                            resetFields()
                        }
                    }
                }
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
                Text("Ingen aktiv sesong. Gruppene er fra Golfgutu-oppsettet.")
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
        default: ""
        }
    }

    private func confirmButton(_ action: TroppAction) -> String {
        switch action {
        case .reject: "Avvis"
        case .releaseLogin: "Frigjør"
        case .archive: "Arkiver"
        case .delete: "Slett"
        default: "OK"
        }
    }
}
