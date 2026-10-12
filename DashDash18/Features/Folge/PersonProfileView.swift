import Supabase
import SwiftUI

/// En annen spiller (sql/054): portrett, navn, Følg / Venter / Følger, og «Blokker» og
/// «Rapporter profil». Det du ser av rundene, står i «Følger» på Hjem.
struct PersonProfileView: View {
    let client: SupabaseClient
    let userID: UUID
    let profileID: UUID
    let name: String
    var avatarPath: String?
    var source: FollowSource = .search
    @State private var status: FollowStatus = .none
    @State private var followsMe = false
    @State private var loaded = false
    @State private var reporting = false
    @State private var confirmsBlock = false
    @State private var blocked = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DDList {
            Section {
                HStack(spacing: DDSpacing.m) {
                    FollowAvatar(client: client, name: name, path: avatarPath, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name)
                            .font(.ddName)
                            .foregroundStyle(Color.ddInk)
                        if followsMe {
                            DDPill("Følger deg", tone: .earth).fixedSize()
                        }
                    }
                }
                .padding(.vertical, 6)
                if profileID != userID, !blocked {
                    FollowStatusButton(client: client, profileID: profileID, name: name, status: $status,
                                       source: source, compact: false)
                        .disabled(!loaded)
                }
            } footer: {
                DDFooter(footer)
            }
            if profileID != userID, !blocked {
                Section {
                    Button("Blokker", systemImage: "hand.raised", role: .destructive) { confirmsBlock = true }
                        .foregroundStyle(Color.ddRustText)
                    Button("Rapporter profil", systemImage: "flag") { reporting = true }
                } footer: {
                    DDFooter("Blokkering fjerner følgingen begge veier. Den du blokkerer, får ikke vite det.")
                }
            }
            if blocked {
                Section {
                    Label("\(name) er blokkert.", systemImage: "hand.raised").foregroundStyle(Color.ddInkSecondary)
                }
            }
            if let error {
                Section { Label(error, systemImage: "exclamationmark.triangle").ddErrorStyle() }
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .ddNavigationChrome()
        .task { await load() }
        .sheet(isPresented: $reporting) {
            ReportSheet(target: ReportTarget(kind: .profile, targetID: profileID, memberID: nil, authorName: name)) {
                reason, note, _ in
                _ = try await ModerationService(client: client).report(kind: .profile, targetID: profileID,
                                                                       reason: reason, note: note)
            }
        }
        .confirmationDialog("Blokkere \(name)?", isPresented: $confirmsBlock, titleVisibility: .visible) {
            Button("Blokker", role: .destructive) { block() }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text("Følgingen fjernes begge veier, og dere finner ikke hverandre i søket.")
        }
    }

    private var footer: String {
        switch status {
        case .none: "Følger du, ser du de ferdige rundene til \(name) under «Følger» på Hjem."
        case .pending: "\(name) må godta forespørselen."
        case .accepted: "Du ser de ferdige rundene til \(name) under «Følger» på Hjem."
        }
    }

    private func load() async {
        let rows = (try? await FollowService(client: client).myFollows()) ?? []
        let lists = FollowLists(rows)
        status = lists.status(of: profileID)
        followsMe = lists.followsMe(profileID)
        loaded = true
    }

    private func block() {
        Task {
            do {
                _ = try await ModerationService(client: client).block(profileID: profileID)
                blocked = true
                status = .none
                followsMe = false
            } catch {
                self.error = DataError.from(error).message
            }
        }
    }
}
