import GolfgutuCore
import SwiftUI

// V12 og 4.4 (UI-utbedringen): «I kveld» på arrangørsiden når kvelden er i dag. Kortet for runden
// med én rad per bås, påmeldingen med «Purr dem», sidepremiene og det som gjenstår før «Ferdig».
// Bare visning; handlingene er de som fantes (runden, purringen, TV-visningen, avslutningen).

/// Rundekortet mens runden går: «Runde 1 · St Andrews Old Course», form og båser, «Pågår»,
/// én rad per bås og hovedknappen «Vis live-tavla på TV».
struct TonightRoundCard: View {
    let title: String
    let shape: String
    let bays: [BayLive]
    /// «bås» i simulatoren, «flight» på ekte bane.
    let groupTerm: GroupTerm
    /// «1 hull har ulike tall fra to markører» (K6/6.3). nil: ingen.
    var conflictText: String?
    /// nil: ingen TV-knapp (skjer ikke i dag, men holder kortet enkelt å gjenbruke).
    var showTV: (() -> Void)?
    let openRound: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DDSpacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: DDSpacing.s) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.ddTitleSmall)
                        .foregroundStyle(Color.ddInk)
                    Text(shape)
                        .font(.ddCaption)
                        .foregroundStyle(Color.ddInkSecondary)
                }
                Spacer(minLength: 4)
                DDPill("Pågår", tone: .live)
                    .fixedSize()
            }
            .accessibilityElement(children: .combine)
            if bays.isEmpty {
                Text(TonightLive.noGroupsText(groupTerm))
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddInkSecondary)
            }
            ForEach(bays) { bay in
                Divider()
                BayLiveRow(bay: bay)
            }
            if let conflictText {
                // Arket ligger i føringen: «Gå til runden» under.
                DDInfoStripe(tone: .sun) {
                    Label(conflictText + ". Velg tallet i runden.", systemImage: "exclamationmark.2")
                        .labelStyle(DDIconLabelStyle())
                }
                .onTapGesture(perform: openRound)
                .accessibilityAddTraits(.isButton)
            }
            if let showTV {
                Button(action: showTV) {
                    Label("Vis live-tavla på TV", systemImage: "tv")
                }
                .buttonStyle(.dd(.primary, fullWidth: true))
                .padding(.top, DDSpacing.xs)
            }
            Button("Gå til runden", action: openRound)
                .buttonStyle(.dd(.text, fullWidth: true))
        }
        .padding(.vertical, DDSpacing.s)
    }
}

/// Én bås: navn og starttid, spillerne, funksjonæren, hullet og synkstatus, med fremdriftsstripe.
struct BayLiveRow: View {
    let bay: BayLive

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: DDSpacing.s) {
                Text([bay.title, bay.startsAt].compactMap { $0 }.joined(separator: " · "))
                    .font(.ddBodyEmphasis)
                    .foregroundStyle(Color.ddInk)
                Spacer(minLength: 4)
                Text(TonightLive.holeText(bay))
                    .font(.ddStatus)
                    .monospacedDigit()
                    .foregroundStyle(Color.ddInk)
            }
            Text(NorwegianList.join(bay.names))
                .font(.ddCaption)
                .foregroundStyle(Color.ddInkSecondary)
            if let scorer = bay.scorer {
                Label("Funksjonær: \(scorer)", systemImage: "pencil.and.list.clipboard")
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddForestInk)
            }
            BayProgressStripe(fraction: bay.fraction, warning: bay.sync.isWarning)
            if let text = TonightLive.syncText(bay.sync, startsAt: bay.startsAt) {
                Label(text, systemImage: bay.sync.isWarning ? "exclamationmark.triangle.fill" : syncIcon)
                    .font(.ddStatus)
                    .foregroundStyle(bay.sync.isWarning ? Color.ddRustText : Color.ddInkSecondary)
                    .labelStyle(DDIconLabelStyle())
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var syncIcon: String {
        switch bay.sync {
        case .startsIn: "clock"
        case .finished: "checkmark.circle"
        default: "arrow.triangle.2.circlepath"
        }
    }
}

/// Fremdriften i båsen: skog, eller rust når båsen ikke har ført på en stund.
struct BayProgressStripe: View {
    let fraction: Double
    var warning = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.ddHairline)
                Capsule()
                    .fill(warning ? Color.ddRust : Color.ddForestInk)
                    .frame(width: max(geo.size.width * fraction, fraction > 0 ? 6 : 0))
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

/// Påmeldingen i kveld: «12 av 14 kommer», hvem som mangler svar, og «Purr dem».
struct TonightSignupCard: View {
    let coming: String
    let followUp: String?
    /// De som ikke har svart. Tom: ingen purreknapp.
    let nudgeNames: [String]
    /// nil: du har ikke rettighet til å purre.
    let nudge: (() async throws(DataError) -> String)?
    let openEvening: () -> Void

    @State private var confirming = false
    @State private var sending = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DDSpacing.s) {
            Button(action: openEvening) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(coming)
                            .font(.ddBodyEmphasis)
                            .foregroundStyle(Color.ddInk)
                        if let followUp {
                            Text(followUp)
                                .font(.ddCallout)
                                .foregroundStyle(Color.ddInkSecondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.ddInkSecondary)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Åpner påmeldingen")
            if nudge != nil, !nudgeNames.isEmpty {
                Button {
                    confirming = true
                } label: {
                    HStack(spacing: 8) {
                        Text("Purr dem")
                        if sending { ProgressView() }
                    }
                }
                .buttonStyle(.dd(.secondary, fullWidth: true))
                .disabled(sending)
                .confirmationDialog(Nudge.confirmMessage(names: nudgeNames), isPresented: $confirming,
                                    titleVisibility: .visible) {
                    Button(Nudge.confirmButton) { send() }
                    Button("Avbryt", role: .cancel) {}
                }
            }
            if let message {
                Text(message)
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddInkSecondary)
            }
        }
        .padding(.vertical, DDSpacing.xs)
    }

    private func send() {
        guard let nudge else { return }
        sending = true
        message = nil
        Task {
            defer { sending = false }
            do throws(DataError) {
                message = try await nudge()
            } catch {
                message = "Klarte ikke å purre. \(error.message)"
            }
        }
    }
}

/// En sidepremie med «Registrer», som åpner runden (innmeldingen skjer på premiehullet i føringen).
struct TonightSidePrizeRow: View {
    let prize: TonightLive.SidePrize
    let register: () -> Void

    var body: some View {
        HStack(spacing: DDSpacing.m) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(prize.title) · hull \(prize.hole)")
                        .foregroundStyle(Color.ddInk)
                    Text(prize.statusText)
                        .font(.ddStatus)
                        .foregroundStyle(Color.ddInkSecondary)
                }
            } icon: {
                Image(systemName: prize.kind == .kp ? "flag" : "arrow.up.right")
            }
            .labelStyle(DDIconLabelStyle())
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button("Registrer", action: register)
                .buttonStyle(.dd(.secondary, compact: true))
                .accessibilityHint("Åpner runden")
        }
    }
}

/// Et punkt i «Før Ferdig»: ✓ når det er i orden.
struct TonightRemainingRow: View {
    let item: TonightLive.Remaining

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .foregroundStyle(item.isDone ? Color.ddInkSecondary : Color.ddInk)
                if let detail = item.detail {
                    Text(detail)
                        .font(.ddCaption)
                        .foregroundStyle(Color.ddInkSecondary)
                }
            }
        } icon: {
            Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.isDone ? Color.ddForestInk : Color.ddInkSecondary)
        }
        .labelStyle(DDIconLabelStyle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.isDone ? "I orden" : "Gjenstår")
    }
}

/// Fullskjerm-TV-en fra Tavla (`TavlaTVView`), med egen modell som følger scorene mens den vises.
struct TonightTVCover: View {
    @State var model: TavlaModel

    var body: some View {
        TavlaTVView(model: model)
            .task {
                await model.load()
                await model.follow()
            }
    }
}
