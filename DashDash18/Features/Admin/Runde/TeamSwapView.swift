import GolfgutuCore
import SwiftUI

/// «Bytt to spillere»: velg to på hvert sitt lag, så bytter de lag (`Teams.swap`). Matchene følger lagene.
struct TeamSwapView: View {
    let model: RundeAdminModel
    @Binding var draft: RoundDraft
    let plan: MatchDrawPlan

    @Environment(\.dismiss) private var dismiss
    @State private var first: UUID?
    @State private var second: UUID?

    var body: some View {
        DDForm {
            Section {
                picker("Første", selection: $first, excluding: nil)
                picker("Andre", selection: $second, excluding: first.flatMap { draft.teams[$0] })
            } footer: {
                DDFooter("De to bytter lag. Matchene settes opp på nytt etter lagene.")
            }
            Section {
                Button("Bytt", systemImage: "arrow.left.arrow.right") {
                    guard let first, let second else { return }
                    draft.teams = TeamPlanner.swap(draft.teams, first, second)
                    draft.redrawMatches(roster: model.members, plan: plan)
                    dismiss()
                }
                .disabled(!canSwap)
            }
        }
        .navigationTitle("Bytt to spillere")
        .ddNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: first) { _, _ in
            // Den andre må stå på et annet lag enn den første.
            if let second, let a = first.flatMap({ draft.teams[$0] }), draft.teams[second] == a { self.second = nil }
        }
    }

    private var canSwap: Bool {
        guard let first, let second, let a = draft.teams[first], let b = draft.teams[second] else { return false }
        return a != b
    }

    /// Spillerne med lag. `excluding`: laget til den første, så den andre står på et annet lag.
    private func picker(_ title: String, selection: Binding<UUID?>, excluding team: Int?) -> some View {
        Picker(title, selection: selection) {
            Text("Velg").tag(UUID?.none)
            ForEach(draft.participants.filter { draft.teams[$0] != nil && draft.teams[$0] != team }, id: \.self) { id in
                Text("\(model.memberName(id)) · lag \(draft.teams[id] ?? 0)").tag(Optional(id))
            }
        }
    }
}
