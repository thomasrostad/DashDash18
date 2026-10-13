import GolfgutuCore
import SwiftUI

/// Hero for hullet (planen 4.2): stort hullnummer, par og meter, indeks, sidepremie og ‹ › på 44 pt.
struct HullHeroView: View {
    let card: HoleCard
    let onGoTo: (Int) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: DDSpacing.s) {
            arrow("chevron.left", label: "Forrige hull", enabled: card.hasPrevious) { onGoTo(card.holeIndex - 1) }
            VStack(spacing: 4) {
                Text(card.title)
                    .font(.ddStatus)
                    .foregroundStyle(Color.ddHeroSecondary)
                Text("\(card.number)")
                    .font(.dd(.sans, size: 60, weight: .light, relativeTo: .largeTitle))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(card.number)))
                    .foregroundStyle(Color.ddOnDark)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(card.parLine)
                    .font(.dd(.sans, size: 19, weight: .medium, relativeTo: .headline))
                    .monospacedDigit()
                    .foregroundStyle(Color.ddOnDark)
                ViewThatFits {
                    HStack(spacing: DDSpacing.s) { meta }
                    VStack(spacing: 6) { meta }
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)
            arrow("chevron.right", label: "Neste hull", enabled: card.hasNext) { onGoTo(card.holeIndex + 1) }
        }
        .ddCard(.hero, padding: DDSpacing.l)
        // Hullnummeret er alt 60 pt; resten vokser til xxxL så hero-kortet ikke fyller skjermen.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    @ViewBuilder
    private var meta: some View {
        if let index = card.indexLine {
            Text(index)
                .font(.ddStatus)
                .monospacedDigit()
                .foregroundStyle(Color.ddHeroSecondary)
        }
        if card.isLongestDrive {
            DDSidePrizeTag(kind: .longestDrive)
        }
        if card.isClosestToPin {
            DDSidePrizeTag(kind: .closestToPin)
        }
    }

    private var accessibilityText: String {
        var parts = ["Hull \(card.number)", card.parLine.replacingOccurrences(of: " · ", with: ", ")]
        if let index = card.indexLine { parts.append(index) }
        if card.isLongestDrive { parts.append("longest drive") }
        if card.isClosestToPin { parts.append("nærmest pinnen") }
        return parts.joined(separator: ", ")
    }

    private func arrow(_ image: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.ddOnDark)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.ddOnDark.opacity(0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(label)
    }
}

/// Hullkortet for hele båsen: én rad per spiller. «Lagre hull» står i bunnlinja (`FoeringBunnlinje`).
struct HullkortView: View {
    let card: HoleCard
    let isPending: Bool
    let onStep: (Int, UUID) -> Void
    let onConfirm: (UUID) -> Void
    /// Åpner scorekortet til spilleren (nil: ditt eget).
    let onScorecard: (UUID?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(card.header)
                Spacer()
                Text(card.strokesLabel)
            }
            .ddEyebrow()

            VStack(spacing: 0) {
                DDDivider()
                ForEach(card.rows) { row in
                    HullRadView(row: row, isPending: isPending, onStep: onStep, onConfirm: onConfirm,
                                onName: { onScorecard(row.memberID) })
                    if row.id != card.rows.last?.id { DDDivider() }
                }
            }

            if let outside = card.outsideTruncation {
                Text(outside)
                    .font(.ddCaption)
                    .ddWarningStyle()
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            if let hint = card.viewerHint {
                Text(hint)
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddInkSecondary)
            }
        }
        .ddCard(.large)
    }
}

/// Bunnlinja i glass (planen 4.2): synkstatus og hovedknappen «Lagre hull 7 og gå videre →».
struct FoeringBunnlinje: View {
    let card: HoleCard
    let isSaving: Bool
    let error: String?
    /// «Hull 1–6 er synket» eller «Lagret på telefonen …» (K6).
    var sync: SyncStatus?
    let onSave: () -> Void
    let onGoTo: (Int) -> Void
    let onScorecard: () -> Void

    var body: some View {
        VStack(spacing: DDSpacing.s) {
            statusLine
            actionView
        }
        .padding(.horizontal, DDSpacing.l)
        .padding(.vertical, DDSpacing.m)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: DDRadius.cardLarge))
        .padding(.horizontal, DDSpacing.s)
        .padding(.bottom, 4)
        // Linja ligger over lista hele tiden: den vokser med teksten, men ikke så mye at den
        // tar halve skjermen ved de største tilgjengelighetsstørrelsene.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    @ViewBuilder
    private var statusLine: some View {
        if let error {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.ddStatus)
                .ddErrorStyle()
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DDSpacing.s) { syncLabel; Spacer(minLength: 0); changedLabel }
                VStack(alignment: .leading, spacing: 2) { syncLabel; changedLabel }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.ddStatus)
            .monospacedDigit()
        }
    }

    @ViewBuilder
    private var syncLabel: some View {
        if let sync {
            Label {
                Text(sync.text)
            } icon: {
                Image(systemName: sync.isPending ? "icloud.and.arrow.up" : "checkmark.icloud")
                    .foregroundStyle(sync.isPending ? Color.ddRust : Color.ddForestInk)
            }
            .foregroundStyle(sync.isPending ? Color.ddRustText : Color.ddInkSecondary)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var changedLabel: some View {
        if case .save(_, _, let status?) = card.action {
            Text(status)
                .foregroundStyle(Color.ddInkSecondary)
        }
    }

    @ViewBuilder
    private var actionView: some View {
        switch card.action {
        case .save(let title, let enabled, _):
            Button(action: onSave) {
                ZStack {
                    // Samme bredde mens den lagrer (planen 1.3).
                    HStack(spacing: 6) {
                        Text(error == nil ? title : "Prøv igjen · \(title.lowercased())")
                        if card.actionAdvances && error == nil {
                            Image(systemName: "arrow.right").accessibilityHidden(true)
                        }
                    }
                    .opacity(isSaving ? 0 : 1)
                    if isSaving { ProgressView().tint(DDToken.buttonPrimaryText.color) }
                }
            }
            .buttonStyle(.ddPrimary)
            .disabled(!enabled || isSaving)
        case .next(let title, let hole):
            Button(title) { onGoTo(hole) }
                .buttonStyle(.dd(.secondary, fullWidth: true))
        case .scorecard:
            Button("Alle hull er lagret · se scorekortet →", action: onScorecard)
                .buttonStyle(.dd(.secondary, fullWidth: true))
        case .none:
            EmptyView()
        }
    }
}

/// Én spiller: navn, slag fått, resultat, og tallet med steppere når raden kan føres.
struct HullRadView: View {
    let row: HoleCard.Row
    let isPending: Bool
    let onStep: (Int, UUID) -> Void
    let onConfirm: (UUID) -> Void
    let onName: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Store tekststørrelser (V7): navnet over, stepperen under.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            info
            if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
            if row.editable {
                stepper
            } else {
                Text(row.saved.map(String.init) ?? "—")
                    .font(.ddStrokes)
                    .monospacedDigit()
                    .foregroundStyle(row.saved == nil ? Color.ddHairline : Color.ddForestInk)
                    .frame(minWidth: 46, alignment: .trailing)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, row.isMe ? 10 : 0)
        // Din rad har en svak gulltone, som i PWA-en.
        .background(row.isMe ? Color.ddYouRow : Color.clear, in: .rect(cornerRadius: 16))
        .padding(.horizontal, row.isMe ? -10 : 0)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onName) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(row.name)
                        .font(.ddName)
                        .foregroundStyle(Color.ddForestInk)
                        .lineLimit(1)
                    if row.isMe {
                        DDYouBadge()
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Scorekortet til \(row.name)")

            if row.editable || row.saved != nil {
                Text(row.isDefault ? "\(row.strokesReceived) slag fått · forvalgt par" : "\(row.strokesReceived) slag fått")
                    .font(.ddMonoSmall)
                    .foregroundStyle(Color.ddInkSecondary)
            }
            result
            if let calculation = row.calculation {
                Text(calculation)
                    .font(.ddMonoSmall)
                    .monospacedDigit()
                    .foregroundStyle(Color.ddInkSecondary)
            }
        }
    }

    @ViewBuilder
    private var result: some View {
        if let name = row.scoreName {
            HStack(spacing: 8) {
                if let points = row.points {
                    // «2 p · netto par» i scorefargen (planen K1).
                    ScoreChip(name: name, text: "\(points) p · netto \(name.label.lowercased())")
                } else {
                    ScoreChip(name: name)
                }
                if isPending && !row.editable {
                    Text("ikke lagret ennå").font(.ddCaption).ddWarningStyle()
                }
            }
        } else if !row.editable {
            Text("ikke lagret ennå")
                .font(.ddCaption)
                .foregroundStyle(Color.ddInkSecondary)
        }
    }

    private var stepper: some View {
        HStack(spacing: 6) {
            Button {
                onStep(-1, row.memberID)
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(DDStepperButtonStyle(kind: .minus))

            Button {
                onConfirm(row.memberID)
            } label: {
                DDStrokeValue(value: "\(row.value)", confirmed: row.confirmed)
            }
            .buttonStyle(.plain)

            Button {
                onStep(1, row.memberID)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(DDStepperButtonStyle(kind: .plus))
        }
        .sensoryFeedback(trigger: row.value) { old, new in new > old ? .increase : .decrease }
        // VoiceOver (V7): «Kåre, 4 slag», «2 poeng», og sveip opp/ned som + og −.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(StrokeAccessibility.label(row))
        .accessibilityValue(StrokeAccessibility.value(row))
        .accessibilityHint("Sveip opp eller ned for å endre.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onStep(1, row.memberID)
            case .decrement: onStep(-1, row.memberID)
            @unknown default: break
            }
        }
        .accessibilityAction { onConfirm(row.memberID) }
    }
}

/// Det VoiceOver leser på stepperen (planen V7).
nonisolated enum StrokeAccessibility {
    /// «Kåre, 4 slag».
    static func label(_ row: HoleCard.Row) -> String {
        "\(row.name), \(row.value) slag"
    }

    /// «2 poeng», «forvalgt par, 2 poeng» eller tomt i en match.
    static func value(_ row: HoleCard.Row) -> String {
        var parts: [String] = []
        if row.isDefault { parts.append("forvalgt par") }
        if let points = row.points { parts.append("\(points) poeng") }
        return parts.joined(separator: ", ")
    }
}

/// Eagle, Birdie, Par, Bogey, Dobbel, Blowup (fargene fra designsystemet).
struct ScoreChip: View {
    let name: ScoreName
    var text: String?

    var body: some View {
        DDChip(text ?? name.label, tone: name.tone, compact: true)
    }
}

extension HullkortView {
    /// Signaturen fra før bunnlinja (skjermprøver utenfor føringen). Lagringen står nå i `FoeringBunnlinje`.
    init(card: HoleCard, isPending: Bool, isSaving: Bool, error: String?, sync: SyncStatus? = nil,
         onStep: @escaping (Int, UUID) -> Void, onConfirm: @escaping (UUID) -> Void, onSave: @escaping () -> Void,
         onGoTo: @escaping (Int) -> Void, onScorecard: @escaping (UUID?) -> Void) {
        self.init(card: card, isPending: isPending, onStep: onStep, onConfirm: onConfirm, onScorecard: onScorecard)
    }
}
