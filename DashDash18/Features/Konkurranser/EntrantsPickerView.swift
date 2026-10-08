import GolfgutuCore
import SwiftUI

/// Velg påmeldte i en ny turnering: troppen (klubbens) og folk du kjenner (privat).
struct EntrantsPickerView: View {
    @Binding var draft: CompetitionDraft
    let members: [ClubMemberRow]
    let friends: [ProfileRow]

    var body: some View {
        DDList {
            if draft.clubID != nil, !members.isEmpty {
                Section {
                    ForEach(members) { m in
                        row(m.displayName, chosen: draft.memberIDs.contains(m.id)) {
                            toggle(&draft.memberIDs, m.id)
                        }
                    }
                } header: {
                    DDHeader("Troppen")
                }
            }
            if draft.clubID == nil {
                Section {
                    if friends.isEmpty {
                        Text("Ingen ennå. Folk du deler en klubb, runde eller turnering med, står her.")
                            .foregroundStyle(Color.ddInkSecondary)
                    }
                    ForEach(friends) { f in
                        let name = LooseRoundInfo.name(f.displayName)
                        row(name, chosen: draft.profileIDs.contains(f.id)) {
                            toggle(&draft.profileIDs, f.id)
                        }
                    }
                } header: {
                    DDHeader("Folk du kjenner")
                } footer: {
                    DDFooter("Du er med selv som eier.")
                }
            }
        }
        .navigationTitle("Påmeldte")
        .ddNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ set: inout Set<UUID>, _ id: UUID) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }

    private func row(_ name: String, chosen: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                DDAvatar(name: name)
                Text(name).foregroundStyle(Color.ddInk)
                Spacer()
                Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(chosen ? Color.ddForestInk : Color.ddInkSecondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
