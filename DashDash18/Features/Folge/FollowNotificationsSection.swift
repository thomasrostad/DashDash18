import Supabase
import SwiftUI

/// Øverst i Varsler (sql/054): følging og kommentarer på kort i «Følger». En forespørsel som
/// fortsatt venter, har Godta og Avslå.
struct FollowNotificationsSection: View {
    let rows: [PersonalActivity]
    let client: SupabaseClient
    let userID: UUID
    var lastSeen: Date?
    /// Etter Godta eller Avslå: hent varslene på nytt.
    var onChange: () async -> Void = {}
    @State private var pending: Set<UUID> = []
    @State private var working: Set<UUID> = []
    @State private var comments: CommentsModel?
    @State private var error: String?

    var body: some View {
        if !rows.isEmpty {
            DDSection("Følging") {
                ForEach(rows) { row in
                    if let display = PersonalActivityText.display(row) {
                        line(row, display: display)
                    }
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").ddErrorStyle()
                }
            }
            .task(id: rows.map(\.id)) { await loadPending() }
            .sheet(item: $comments) { CommentsSheet(model: $0) }
        }
    }

    private func line(_ row: PersonalActivity, display: ActivityDisplay) -> some View {
        HStack(alignment: .top, spacing: 12) {
            DDIconTile(systemImage: display.symbol)
            VStack(alignment: .leading, spacing: 8) {
                Text(display.text)
                    .font(isUnread(row) ? .ddBodyEmphasis : .ddBody)
                    .foregroundStyle(Color.ddInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 7)
                if row.isFollowRequest, let actor = row.actorProfileID, pending.contains(actor) {
                    HStack(spacing: DDSpacing.s) {
                        Button("Godta") { respond(actor, accept: true) }
                            .buttonStyle(.dd(.primary, compact: true))
                        Button("Avslå") { respond(actor, accept: false) }
                            .buttonStyle(.dd(.secondary, compact: true))
                    }
                    .disabled(working.contains(actor))
                }
                if let card = row.cardID {
                    Button("Se kommentarene") { comments = commentsModel(card) }
                        .font(.ddCaption)
                        .foregroundStyle(Color.ddForestInk)
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(ActivityFeed.relativeTime(row.createdAt))
                .font(.ddMonoSmall)
                .monospacedDigit()
                .foregroundStyle(Color.ddInkSecondary)
                .padding(.top, 9)
        }
        .padding(.vertical, 4)
    }

    private func isUnread(_ row: PersonalActivity) -> Bool {
        lastSeen.map { row.createdAt > $0 } ?? true
    }

    private func commentsModel(_ card: UUID) -> CommentsModel {
        CommentsModel(target: SocialTarget(kind: .activity, id: card, clubID: nil), me: userID, isModerator: false,
                      isTargetAuthor: false, people: [], names: [:], client: client)
    }

    /// Forespørslene som fortsatt venter (et varsel står igjen etter at du har godtatt).
    private func loadPending() async {
        let rows = (try? await FollowService(client: client).myFollows()) ?? []
        pending = Set(FollowLists(rows).requests.map(\.profileID))
    }

    private func respond(_ follower: UUID, accept: Bool) {
        working.insert(follower)
        Task {
            defer { working.remove(follower) }
            do {
                try await FollowService(client: client).respond(to: follower, accept: accept)
                pending.remove(follower)
                error = nil
                await onChange()
            } catch {
                self.error = FollowService.message(error)
            }
        }
    }
}
