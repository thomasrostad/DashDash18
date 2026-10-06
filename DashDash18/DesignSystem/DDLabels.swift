import GolfgutuCore
import SwiftUI

extension View {
    /// Liten etikett i mono versaler med sporing (`.eyebrow`).
    func ddEyebrow(color: Color = .ddInkSecondary) -> some View {
        font(.ddEyebrow)
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

/// Seksjonsetikett over et kort (`.gg-section-label`), med valgfri lenke eller tall til høyre.
struct DDSectionLabel<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .ddEyebrow()
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 2)
    }
}

extension DDSectionLabel where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

/// Toner for piller og merker.
enum DDTone {
    case lime, sun, earth, blush, blushDeep, gold, live, outlineRust, onDark, earthDeep

    var background: Color {
        switch self {
        case .lime: .ddLimeBackground
        case .sun: .ddSunBackground
        case .earth: .ddEarth
        case .earthDeep: .ddEarthDeep
        case .blush, .live: .ddBlushBackground
        case .blushDeep: .ddBlushDeep
        case .gold: .ddGold
        case .outlineRust: .clear
        case .onDark: Color.ddOnDark.opacity(0.12)
        }
    }

    var foreground: Color {
        switch self {
        case .lime: .ddLimeInk
        case .sun: .ddSunInk
        case .earth, .live: .ddRustDark
        case .blush, .blushDeep: .ddBlushInk
        case .earthDeep: .ddInk
        case .gold: .ddGoldInk
        case .outlineRust: .ddRustText
        case .onDark: .ddOnDark
        }
    }

    var border: Color? {
        switch self {
        case .outlineRust: .ddRust
        case .onDark: Color.ddOnDark.opacity(0.28)
        default: nil
        }
    }
}

/// Liten pille i mono versaler (`.gg-pill`): ÅPENT, LIVE, TEST, LONGEST DRIVE …
struct DDPill: View {
    let text: String
    var tone: DDTone = .earth
    var systemImage: String?

    init(_ text: String, tone: DDTone = .earth, systemImage: String? = nil) {
        self.text = text
        self.tone = tone
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            Text(text)
        }
        .font(.ddPill)
        .tracking(1.1)
        .textCase(.uppercase)
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(tone.background))
        .overlay {
            if let border = tone.border {
                Capsule().strokeBorder(border, lineWidth: 1.5)
            }
        }
    }
}

/// Chip med tekst i grotesk (`.gg-chip`), f.eks. «Par? trykk tallet».
struct DDChip: View {
    let text: String
    var tone: DDTone = .earth
    var compact = false

    init(_ text: String, tone: DDTone = .earth, compact: Bool = false) {
        self.text = text
        self.tone = tone
        self.compact = compact
    }

    var body: some View {
        Text(text)
            .font(compact ? .dd(.sans, size: 11.5, weight: .semibold, relativeTo: .caption) : .ddChip)
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, compact ? 4 : 7)
            .background(Capsule().fill(tone.background))
    }
}

extension ScoreName {
    /// Fargen på score-merket (style.css `.gg-chip.eagle` osv.).
    var tone: DDTone {
        switch self {
        case .eagle: .sun
        case .birdie: .lime
        case .par: .earth
        case .bogey: .blush
        case .dobbel, .blowup: .blushDeep
        }
    }
}

/// Score-merke: Eagle, Birdie, Par, Bogey, Dobbel, Blowup.
struct DDScoreBadge: View {
    let name: ScoreName
    var compact = false

    var body: some View {
        DDChip(name.label, tone: name.tone, compact: compact)
    }
}

/// Poengtall i en farget rundel, som på scorekortet (`1` i blush, `4` i sol …). Tom = «–».
struct DDPointsBadge: View {
    let points: Int?
    let name: ScoreName?

    var body: some View {
        Text(points.map(String.init) ?? "–")
            .font(.dd(.mono, size: 15, weight: .semibold, relativeTo: .body))
            .foregroundStyle(name?.tone.foreground ?? .ddInkSecondary)
            .frame(minWidth: 34, minHeight: 28)
            .padding(.horizontal, 4)
            .background(Capsule().fill(name?.tone.background ?? Color.ddEarth.opacity(0.6)))
    }
}

/// Beige info-stripe (`.gg-earth`): «Du er markør i bås 1 · …».
struct DDInfoStripe<Content: View>: View {
    var tone: DDTone = .earth
    @ViewBuilder var content: Content

    init(tone: DDTone = .earth, @ViewBuilder content: () -> Content) {
        self.tone = tone
        self.content = content()
    }

    var body: some View {
        content
            .font(.ddCallout)
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tone.background, in: .rect(cornerRadius: DDRadius.input))
    }
}

extension DDInfoStripe where Content == Text {
    init(_ text: String, tone: DDTone = .earth) {
        self.init(tone: tone) { Text(text) }
    }
}

/// Rund avatar med initialer (`.gg-avatar`).
struct DDAvatar: View {
    let name: String
    var size: CGFloat = 30

    var body: some View {
        Text(Self.initials(name))
            .font(.dd(.sans, size: size * 0.4, weight: .semibold, relativeTo: .caption))
            .foregroundStyle(Color.ddLimeInk)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.ddLimeBackground))
            .accessibilityHidden(true)
    }

    nonisolated static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

/// Pulserende rust-prikk for «live» (`.gg-live-dot`). Stille hvis Reduser bevegelse er på.
struct DDLiveDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Color.ddRust)
            .frame(width: 8, height: 8)
            .background {
                if !reduceMotion {
                    Circle()
                        .fill(Color.ddRust)
                        .scaleEffect(pulsing ? 2.4 : 1)
                        .opacity(pulsing ? 0 : 0.9)
                        .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false), value: pulsing)
                }
            }
            .onAppear { pulsing = true }
            .accessibilityHidden(true)
    }
}

/// «RUNDEN PÅGÅR»-pille med prikk (`.gg-live`).
struct DDLivePill: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            DDLiveDot()
            Text(text)
                .font(.ddPill)
                .tracking(1.1)
                .textCase(.uppercase)
        }
        .foregroundStyle(Color.ddRustDark)
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.ddBlushBackground))
    }
}

/// Label med ikonet i skoggrønt foran teksten (detaljlinjer som tid, sted og komité).
struct DDIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon
                .foregroundStyle(Color.ddForestInk)
                .frame(width: 20)
            configuration.title
        }
    }
}
