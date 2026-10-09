import Observation
import GolfgutuCore
import SwiftUI

/// Det Kveld viser om tråden og tippekupongen for én kveld. Hentes hver for seg: feiler den
/// ene, vises den andre likevel.
@Observable
final class KveldExtrasModel {
    private(set) var thread: TradSummary?
    private(set) var tips: TipsBoard?

    let eventID: UUID
    private let context: ClubContext

    init(context: ClubContext, eventID: UUID) {
        self.context = context
        self.eventID = eventID
    }

    func load() async {
        async let thread = try? TradSummary.load(backend: SupabaseTradBackend(client: context.client),
                                                 clubID: context.clubID, eventID: eventID,
                                                 viewer: context.memberID)
        async let input = try? TipsQueries.load(client: context.client, eventID: eventID)
        if let summary = await thread { self.thread = summary }
        if let input = await input {
            tips = TipsBoard(input, me: context.memberID, isOrganizer: context.isOrganizer)
        }
    }
}

/// Kortene «Kveldens tråd» og «Tippekupongen» på Kveld (før runden).
struct KveldExtrasCards: View {
    @Environment(\.dayTerm) private var dayTerm
    @State var model: KveldExtrasModel
    /// Øker når Kveld hentes på nytt (dra ned, realtime): da hentes kortene også.
    var refresh = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: DDSpacing.cardGap) {
            NavigationLink {
                TradView(eventID: model.eventID)
            } label: {
                ExtrasCardLabel(
                    title: DayTerm.capitalized(dayTerm.possessive) + " tråd",
                    systemImage: "bubble.left.and.bubble.right",
                    subtitle: model.thread.map(KveldThreadStatus.subtitle) ?? "Praten om \(dayTerm.the)",
                    detail: model.thread.flatMap(KveldThreadStatus.lastLine),
                    unread: model.thread?.unread ?? 0
                )
            }
            NavigationLink {
                TipsView(eventID: model.eventID)
            } label: {
                ExtrasCardLabel(
                    title: "Tippekupongen",
                    systemImage: "ticket",
                    subtitle: model.tips.map(KveldTipsStatus.text) ?? "Fem spørsmål om \(dayTerm.the)",
                    detail: nil,
                    unread: 0
                )
            }
            BetsKveldCard()
        }
        .buttonStyle(.plain)
        // Også tilbake fra tråden eller kupongen: uleste og status kan være endret.
        .onAppear { Task { await model.load() } }
        .onChange(of: refresh) { Task { await model.load() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.load() } }
        }
    }
}

private struct ExtrasCardLabel: View {
    let title: String
    let systemImage: String
    let subtitle: String
    let detail: String?
    let unread: Int

    var body: some View {
        HStack(alignment: .center, spacing: DDSpacing.m) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.ddForestInk)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.ddBodyEmphasis)
                    .foregroundStyle(Color.ddInk)
                Text(subtitle)
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddInkSecondary)
                if let detail {
                    Text(detail)
                        .font(.ddCaption)
                        .foregroundStyle(Color.ddInkSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if unread > 0 {
                DDPill(KveldThreadStatus.unreadText(unread), tone: .sun)
                    .fixedSize()
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.ddInkSecondary)
        }
        .contentShape(.rect)
        .ddCard()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Under spill: to knapper til tråden og kupongen, med kort status.
struct KveldExtrasButtons: View {
    @State var model: KveldExtrasModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        HStack(spacing: DDSpacing.s) {
            NavigationLink {
                TradView(eventID: model.eventID)
            } label: {
                Label(buttonText("Tråden", model.thread.map(KveldThreadStatus.short)),
                      systemImage: "bubble.left.and.bubble.right")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            NavigationLink {
                TipsView(eventID: model.eventID)
            } label: {
                Label(buttonText("Tips", model.tips.map { KveldTipsStatus.short($0.phase) }), systemImage: "ticket")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.dd(.secondary, fullWidth: true, compact: true))
        .onAppear { Task { await model.load() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.load() } }
        }
    }

    private func buttonText(_ title: String, _ status: String?) -> String {
        status.map { "\(title) · \($0)" } ?? title
    }
}

/// Arrangøren: «Purr de N som ikke har svart …», med bekreftelse. I Kveld og på Kvelden.
struct NudgeSection: View {
    /// De som ikke har svart.
    let targets: [SignupSummary.Entry]
    /// Sender purringen. Gir teksten som skal vises etterpå.
    let onSend: () async throws(DataError) -> String
    @State private var confirming = false
    @State private var isSending = false
    @State private var message: String?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DDSpacing.s) {
            Button(Nudge.buttonTitle(count: targets.count), systemImage: "alarm") { confirming = true }
                .buttonStyle(.dd(.secondary, fullWidth: true))
                .disabled(isSending)
            if let message {
                Text(message)
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddInkSecondary)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .ddErrorStyle()
            }
        }
        .confirmationDialog(Nudge.confirmMessage(names: targets.map(\.name)), isPresented: $confirming,
                            titleVisibility: .visible) {
            Button(Nudge.confirmButton) { send() }
            Button("Avbryt", role: .cancel) {}
        }
    }

    private func send() {
        isSending = true
        error = nil
        message = nil
        Task {
            defer { isSending = false }
            do throws(DataError) {
                message = try await onSend()
            } catch {
                self.error = "Klarte ikke å purre. \(error.message)"
            }
        }
    }
}
