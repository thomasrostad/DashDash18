import Supabase
import SwiftUI

/// Velgeren øverst på Hjem: klubbens feed eller «Følger» (sql/054).
enum HjemFeedTab: String, CaseIterable, Identifiable {
    case club
    case following

    var id: Self { self }

    var title: String {
        switch self {
        case .club: "Klubben"
        case .following: "Følger"
        }
    }
}

struct HjemFeedTabPicker: View {
    @Binding var tab: HjemFeedTab

    var body: some View {
        DDSegmentedControl(HjemFeedTab.allCases.map { ($0, $0.title) }, selection: $tab)
            .accessibilityLabel("Feed")
            .padding(.horizontal, DDSpacing.gutter)
        .padding(.vertical, DDSpacing.s)
    }
}

/// «Følger»: ferdige runder fra dem du følger, og dine egne, nyeste først.
struct FollowingFeedView: View {
    @State var model: FollowingFeedModel
    /// «Klubben/Følger» øverst i innholdet, som på Hjem. nil: ingen velger.
    var tabPicker: Binding<HjemFeedTab>?
    /// Kortet «Finn folk å følge» øverst (Hjem). Av der lista åpnes fra Deg → Følger.
    var showsAddFriends = true
    @State private var addFriends: FollowAddFriendsModel?
    @State private var comments: CommentsModel?
    @State private var emojiTarget: FollowingCard?

    var body: some View {
        ScrollView {
            if let tabPicker {
                HjemFeedTabPicker(tab: tabPicker)
            }
            LazyVStack(alignment: .leading, spacing: DDSpacing.cardGap) {
                switch model.state {
                case .loading where model.cards.isEmpty:
                    ProgressView("Henter rundene …")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                case .failed(let message) where model.cards.isEmpty:
                    ContentUnavailableView {
                        Label("Fikk ikke hentet rundene", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Prøv igjen") { Task { await model.load() } }
                            .buttonStyle(.dd(.secondary, compact: true))
                    }
                    .padding(.top, DDSpacing.l)
                default:
                    if let addFriends {
                        FollowAddFriendsCard(model: addFriends, feedIsEmpty: model.cards.isEmpty)
                    } else if model.cards.isEmpty {
                        ContentUnavailableView("Ingenting her ennå", systemImage: "person.2",
                                               description: Text("Følg andre spillere, så kommer de ferdige rundene deres her."))
                            .padding(.top, DDSpacing.l)
                    }
                    ForEach(model.cards) { card in
                        FollowingCardView(card: card, client: model.client, userID: model.userID,
                                          toggle: { emoji in Task { await model.toggle(emoji, on: card) } },
                                          pickOther: { emojiTarget = card },
                                          openComments: { comments = model.comments(for: card) })
                    }
                    if model.canLoadMore, !model.cards.isEmpty {
                        HjemLoadMore(isLoading: model.isLoadingMore) { Task { await model.loadMore() } }
                    }
                }
            }
            .padding(.horizontal, DDSpacing.gutter)
            .padding(.top, 12)
            .padding(.bottom, DDSpacing.xxl)
            // Aldri bredere enn skjermen, som på Hjem (`HjemFeedView`): ellers kan lista dras sideveis.
            .containerRelativeFrame(.horizontal)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .task {
            if showsAddFriends, addFriends == nil, let client = model.client {
                addFriends = FollowAddFriendsModel(client: client, userID: model.userID)
            }
            async let feed: Void = model.load()
            async let friends: Void? = addFriends?.load()
            _ = await (feed, friends)
        }
        .refreshable {
            async let feed: Void = model.load()
            async let friends: Void? = addFriends?.load()
            _ = await (feed, friends)
        }
        .sheet(item: $comments) { CommentsSheet(model: $0) }
        .sheet(item: $emojiTarget) { card in
            EmojiPickerSheet { emoji in Task { await model.toggle(emoji, on: card) } }
        }
        .alert("Noe gikk galt", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

/// Ett kort: hvem (navnet åpner profilen), når og hvor, slagene og til par, hullene, og reaksjonene.
struct FollowingCardView: View {
    let card: FollowingCard
    let client: SupabaseClient?
    var userID: UUID?
    let toggle: (String) -> Void
    var pickOther: (() -> Void)?
    var openComments: (() -> Void)?
    @State private var showsHoles = false

    var body: some View {
        VStack(alignment: .leading, spacing: DDSpacing.m) {
            if !card.isMine, let client, let userID {
                NavigationLink {
                    PersonProfileView(client: client, userID: userID, profileID: card.profileID,
                                      name: card.name, avatarPath: card.avatarPath)
                } label: {
                    header.contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Åpner profilen.")
            } else {
                header
            }
            HStack(alignment: .firstTextBaseline, spacing: DDSpacing.l) {
                stat("Slag", card.strokes.map(String.init) ?? "–")
                stat("Til par", card.toParText ?? "–")
                if let played = card.holesPlayed {
                    stat("Hull", "\(played)")
                }
                Spacer()
                if !card.holes.isEmpty {
                    Button(showsHoles ? "Skjul hull" : "Se hull") { showsHoles.toggle() }
                        .buttonStyle(.dd(.text, compact: true))
                }
            }
            if showsHoles {
                FollowingHolesGrid(holes: card.holes)
            }
            ReactionBar(chips: card.chips, toggle: toggle, pickOther: pickOther,
                        comments: openComments.map { ReactionBarComments(count: card.commentCount, open: $0) })
        }
        .ddCard()
    }

    private var header: some View {
        HStack(spacing: DDSpacing.m) {
            FollowAvatar(client: client, name: card.name, path: card.avatarPath, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.isMine ? "Din runde" : card.name)
                    .font(.ddBodyEmphasis)
                    .foregroundStyle(Color.ddInk)
                Text(card.subtitle)
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddInkSecondary)
            }
            Spacer(minLength: 8)
        }
        .accessibilityElement(children: .combine)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).ddEyebrow()
            Text(value).font(.ddNumberLarge).monospacedDigit().foregroundStyle(Color.ddInk)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Hull, par og slag i rader på ni.
struct FollowingHolesGrid: View {
    let holes: [FollowingCard.Hole]

    var body: some View {
        VStack(alignment: .leading, spacing: DDSpacing.s) {
            ForEach(Array(stride(from: 0, to: holes.count, by: 9)), id: \.self) { start in
                let chunk = Array(holes[start..<min(start + 9, holes.count)])
                Grid(horizontalSpacing: 4, verticalSpacing: 2) {
                    GridRow {
                        Text("Hull").ddEyebrow()
                        ForEach(chunk, id: \.hole) { Text("\($0.hole)").font(.ddCaption).monospacedDigit() }
                    }
                    GridRow {
                        Text("Par").ddEyebrow()
                        ForEach(chunk, id: \.hole) { Text($0.par.map(String.init) ?? "–").font(.ddCaption) }
                    }
                    GridRow {
                        Text("Slag").ddEyebrow()
                        ForEach(chunk, id: \.hole) { hole in
                            Text(hole.strokes.map(String.init) ?? "–")
                                .font(.ddCaption.weight(.semibold))
                                .monospacedDigit()
                        }
                    }
                }
                .foregroundStyle(Color.ddInk)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(holes.map { h in
            "Hull \(h.hole): " + (h.strokes.map { "\($0) slag" } ?? "ikke spilt")
        }.joined(separator: ", "))
    }
}

