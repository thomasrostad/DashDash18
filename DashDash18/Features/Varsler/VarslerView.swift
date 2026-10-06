import SwiftUI

/// Varsler: «I dag» og «Tidligere», med uleste, reaksjoner og «Melding til alle» for arrangøren.
/// Åpnes fra bjella i verktøylinjen.
struct VarslerView: View {
    @Environment(\.clubContext) private var context
    var badge: UnreadBadge?

    var body: some View {
        if let context {
            VarslerContent(model: VarslerModel(context: context, badge: badge))
        } else {
            ContentUnavailableView("Ingen klubb", systemImage: "bell.slash",
                                   description: Text("Velg en klubb for å se varslene."))
        }
    }
}

struct VarslerContent: View {
    @State var model: VarslerModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsAnnouncement = false

    var body: some View {
        content
            .navigationTitle("Varsler")
            .toolbar {
                if model.isOrganizer {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Melding til alle", systemImage: "megaphone") { showsAnnouncement = true }
                    }
                }
            }
            .sheet(isPresented: $showsAnnouncement) {
                AnnouncementSheet(model: model)
            }
            .alert("Noe gikk galt", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            .task { await model.load() }
            .refreshable { await model.load() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.load() } }
            }
            .onDisappear { Task { await model.stopRealtime() } }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("Henter varslene …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Fikk ikke hentet varslene", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Prøv igjen") { Task { await model.load() } }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded:
            let sections = model.sections()
            if sections.isEmpty {
                ContentUnavailableView("Ingenting ennå", systemImage: "bell",
                                       description: Text("Varslene dukker opp her når det skjer noe i klubben."))
            } else {
                List {
                    ForEach(sections) { section in
                        Section(section.title) {
                            ForEach(section.items) { item in
                                ActivityRowView(item: item, model: model)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Én linje: ikon, tekst, tid, ulest-prikk og reaksjonsbrikkene. Langt trykk gir hele settet.
struct ActivityRowView: View {
    let item: VarslerModel.Item
    let model: VarslerModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.display.symbol)
                .font(.body)
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
                .background(.tint.opacity(0.12), in: .rect(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.display.text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                if !item.chips.isEmpty {
                    ReactionChipsView(chips: item.chips) { reaction in
                        Task { await model.toggle(reaction, on: item.id) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                Text(item.time)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if item.isUnread {
                    Circle()
                        .fill(.tint)
                        .frame(width: 8, height: 8)
                        .accessibilityLabel("Ulest")
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .contextMenu {
            ForEach(ActivityReaction.allCases, id: \.self) { reaction in
                let mine = model.hasReacted(reaction, on: item.id)
                Button {
                    Task { await model.toggle(reaction, on: item.id) }
                } label: {
                    Text(reaction.rawValue + "  " + (mine ? "Fjern" : reaction.accessibilityName))
                }
            }
            let who = item.chips.map { $0.reaction.rawValue + " " + NorwegianList.join($0.names) }
            if !who.isEmpty {
                Section("Har reagert") {
                    ForEach(who, id: \.self) { Text($0) }
                }
            }
        }
    }
}

/// Brikkene: emoji og antall. Trykk setter eller fjerner din egen.
struct ReactionChipsView: View {
    let chips: [ReactionChip]
    let onTap: (ActivityReaction) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(chips) { chip in
                Button {
                    onTap(chip.reaction)
                } label: {
                    HStack(spacing: 3) {
                        Text(chip.reaction.rawValue)
                        Text("\(chip.count)").font(.caption.monospacedDigit())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(chip.isMine ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(.quaternary),
                                in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(chip.reaction.accessibilityName), \(chip.count): \(NorwegianList.join(chip.names))")
                .accessibilityAddTraits(chip.isMine ? .isSelected : [])
            }
        }
    }
}

/// «Melding til alle»: går som push til alle (fase 8) og står i varslene. Krever bekreftelse.
struct AnnouncementSheet: View {
    let model: VarslerModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var confirming = false

    private var cleaned: String { ActivityText.cleanAnnouncement(text) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Beskjed", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                } footer: {
                    Text("Går til alle i klubben. \(cleaned.count) av \(ActivityText.announcementMaxLength) tegn.")
                }
            }
            .navigationTitle("Melding til alle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { confirming = true }
                        .disabled(cleaned.isEmpty || model.isSending)
                }
            }
            .confirmationDialog("Sende denne til alle?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Send til alle") {
                    Task {
                        if await model.sendAnnouncement(text) { dismiss() }
                    }
                }
            } message: {
                Text("«\(cleaned)»")
            }
        }
    }
}

/// Bjella i verktøylinjen: åpner Varsler og viser antall uleste. Henter tallet når den vises
/// og når appen blir aktiv.
struct VarslerBell: View {
    let badge: UnreadBadge
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationLink {
            VarslerView(badge: badge)
        } label: {
            Image(systemName: badge.count > 0 ? "bell.badge" : "bell")
                .overlay(alignment: .topTrailing) {
                    if let label = badge.label {
                        Text(label)
                            .font(.caption2.bold().monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .background(.red, in: .capsule)
                            .offset(x: 10, y: -8)
                    }
                }
        }
        .accessibilityLabel(badge.count > 0 ? "Varsler, \(badge.count) uleste" : "Varsler")
        .task { await badge.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await badge.refresh() } }
        }
    }
}

// MARK: - Forhåndsvisning

private enum VarslerPreviewData {
    static let club = UUID()
    static let anders = UUID(), bjorn = UUID(), thomas = UUID()
    static let names = [anders: "Anders Berg", bjorn: "Bjørn Dahl", thomas: "Thomas Rostad"]

    static func row(_ event: ActivityEvent, minutesAgo: Double, actor: UUID? = nil) -> ActivityRow {
        ActivityRow(id: UUID(), clubID: club, kind: event.kind, category: event.category, data: event.data,
                    actorMemberID: actor, createdAt: Date.now.addingTimeInterval(-minutesAgo * 60))
    }

    static let rows: [ActivityRow] = [
        row(.bigScore(member: anders, hole: 5, holeIndex: 4, name: .eagle, strokes: 3, par: 5), minutesAgo: 3),
        row(.leadChanged(afterHole: 9, leaders: [anders, bjorn], points: 19, outcome: .shares), minutesAgo: 12),
        row(.sidePrize(kind: .drive, member: bjorn, hole: 7, meters: 245, passed: anders, passedMeters: 231),
            minutesAgo: 40),
        row(.roundStarted(roundNo: 1, courseName: "Pebble Beach", holeCount: 18, bays: 3, ldHole: 7, kpHole: 3),
            minutesAgo: 95),
        row(.announcement(text: "Vi starter 17:00 torsdag, husk sko."), minutesAgo: 60 * 26, actor: thomas),
        row(.signup(member: bjorn, status: .yes, eventDate: "2026-10-08"), minutesAgo: 60 * 50),
    ]

    static var reactions: [ActivityReactionRow] {
        [ActivityReactionRow(activityID: rows[0].id, memberID: bjorn, clubID: club, emoji: .fire),
         ActivityReactionRow(activityID: rows[0].id, memberID: thomas, clubID: club, emoji: .fire),
         ActivityReactionRow(activityID: rows[4].id, memberID: anders, clubID: club, emoji: .thumbsUp)]
    }
}

#Preview("Varsler") {
    NavigationStack {
        VarslerContent(model: VarslerModel(
            preview: VarslerPreviewData.rows, reactions: VarslerPreviewData.reactions,
            names: VarslerPreviewData.names, me: VarslerPreviewData.thomas, isOrganizer: true,
            seenAt: Date.now.addingTimeInterval(-30 * 60)))
    }
}

#Preview("Bjella") {
    NavigationStack {
        Text("Kveld")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    VarslerBell(badge: UnreadBadge(clubID: VarslerPreviewData.club, me: VarslerPreviewData.thomas, count: 3))
                }
            }
    }
}
