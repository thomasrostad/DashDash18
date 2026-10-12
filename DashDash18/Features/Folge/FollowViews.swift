import Supabase
import SwiftUI

/// Portrettet til en profil (bøtta `avatars`), eller initialene når det ikke finnes eller ikke
/// kan leses.
struct FollowAvatar: View {
    let client: SupabaseClient?
    let name: String
    var path: String?
    var size: CGFloat = 40
    @State private var image: UIImage?

    var body: some View {
        DDAvatar(name: name, size: size, image: image)
            .task(id: path) { image = await FollowAvatarCache.shared.image(path: path, client: client) }
    }
}

/// Portrettene som alt er hentet, så lister ikke henter dem på nytt.
actor FollowAvatarCache {
    static let shared = FollowAvatarCache()
    private var images: [String: UIImage] = [:]
    private var failed: Set<String> = []

    func image(path: String?, client: SupabaseClient?) async -> UIImage? {
        guard let path, !path.isEmpty, let client else { return nil }
        if let cached = images[path] { return cached }
        if failed.contains(path) { return nil }
        do {
            let data = try await client.storage.from(DegAvatarPath.bucket).download(path: path)
            guard let image = UIImage(data: data) else { failed.insert(path); return nil }
            images[path] = image
            return image
        } catch {
            failed.insert(path)
            return nil
        }
    }
}

/// Knappen Følg / Venter / Følger. Slutt å følge spør først.
struct FollowStatusButton: View {
    let client: SupabaseClient
    let profileID: UUID
    let name: String
    @Binding var status: FollowStatus
    var source: FollowSource = .search
    var compact = true
    @State private var isWorking = false
    @State private var confirmsUnfollow = false
    @State private var error: String?

    var body: some View {
        Button {
            switch FollowButton.action(status) {
            case .request, .cancel: run(FollowButton.action(status))
            case .unfollow: confirmsUnfollow = true
            }
        } label: {
            HStack(spacing: 6) {
                Text(FollowButton.title(status))
                if isWorking { ProgressView().controlSize(.mini) }
            }
        }
        .buttonStyle(.dd(status == .none ? .primary : .secondary, compact: compact))
        .disabled(isWorking)
        .accessibilityHint(hint)
        .confirmationDialog("Slutte å følge \(name)?", isPresented: $confirmsUnfollow, titleVisibility: .visible) {
            Button("Slutt å følge", role: .destructive) { run(.unfollow) }
            Button("Avbryt", role: .cancel) {}
        }
        .alert("Noe gikk galt", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private var hint: String {
        switch status {
        case .none: "Ber om å følge \(name)."
        case .pending: "Trekker forespørselen."
        case .accepted: "Slutter å følge \(name)."
        }
    }

    private func run(_ action: FollowButton.Action) {
        isWorking = true
        Task {
            defer { isWorking = false }
            let service = FollowService(client: client)
            do {
                switch action {
                case .request:
                    status = try await service.request(profileID, source: source)
                case .cancel, .unfollow:
                    try await service.remove(profileID)
                    status = FollowButton.after(action, answer: nil)
                }
            } catch {
                self.error = FollowService.message(error)
            }
        }
    }
}

/// Én person i en liste: portrett, navn og en linje under.
struct FollowPersonLabel: View {
    let client: SupabaseClient?
    let name: String
    var avatarPath: String?
    var subtitle: String?

    var body: some View {
        HStack(spacing: DDSpacing.m) {
            FollowAvatar(client: client, name: name, path: avatarPath, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.ddBody)
                    .foregroundStyle(Color.ddInk)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.ddCaption)
                        .foregroundStyle(Color.ddInkSecondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
