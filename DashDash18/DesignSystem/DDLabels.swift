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
    /// Scoreskalaen (planen 1.2): egne verdier i mørk modus, ikke gjennomsiktige.
    case scoreEagle, scoreBirdie, scorePar, scoreBogey, scoreDouble, scoreZero
    /// Uvalgt chip.
    case chip

    var background: Color {
        switch self {
        case .lime: .ddLimeBackground
        case .sun: .ddSunBackground
        case .earth: .ddEarth
        case .earthDeep: .ddEarthDeep
        case .blush: .ddBlushBackground
        case .live: .ddLime
        case .blushDeep: .ddBlushDeep
        case .gold: .ddGold
        case .outlineRust: .clear
        case .onDark: Color.ddOnDark.opacity(0.12)
        case .scoreEagle: DDToken.scoreEagleBackground.color
        case .scoreBirdie: DDToken.scoreBirdieBackground.color
        case .scorePar: DDToken.scoreParBackground.color
        case .scoreBogey: DDToken.scoreBogeyBackground.color
        case .scoreDouble: DDToken.scoreDoubleBackground.color
        case .scoreZero: DDToken.scoreZeroBackground.color
        case .chip: .ddChipFill
        }
    }

    var foreground: Color {
        switch self {
        case .lime: .ddLimeInk
        case .sun: .ddSunInk
        case .earth: .ddRustDark
        case .live: .ddLimeOnAccent
        case .blush, .blushDeep: .ddBlushInk
        case .earthDeep: .ddInk
        case .gold: .ddGoldInk
        case .outlineRust: .ddRustText
        case .onDark: .ddOnDark
        case .scoreEagle: DDToken.scoreEagleInk.color
        case .scoreBirdie: DDToken.scoreBirdieInk.color
        case .scorePar: DDToken.scoreParInk.color
        case .scoreBogey: DDToken.scoreBogeyInk.color
        case .scoreDouble: DDToken.scoreDoubleInk.color
        case .scoreZero: DDToken.scoreZeroInk.color
        case .chip: .ddInk
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

/// Statuspille (`.gg-pill`): «Åpent», «Pågår», «Test», «Nærmest pinnen». Sans 13 medium på én linje
/// (planen 1.4: mono bare i seksjonsetiketter).
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
        .lineLimit(1)
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
        case .eagle: .scoreEagle
        case .birdie: .scoreBirdie
        case .par: .scorePar
        case .bogey: .scoreBogey
        case .dobbel: .scoreDouble
        case .blowup: .scoreZero
        }
    }
}

/// Formen rundt et slagtall (planen 1.2), regnet fra brutto mot par, så skalaen kan leses
/// uten farge (fargeblinde, sol på skjermen). Fargen kommer fra netto (`ScoreName`).
nonisolated enum ScoreShape: Equatable, Sendable {
    case doubleCircle, circle, plain, square, doubleSquare

    static func forGross(_ gross: Int, par: Int) -> ScoreShape {
        switch gross - par {
        case ...(-2): .doubleCircle
        case -1: .circle
        case 0: .plain
        case 1: .square
        default: .doubleSquare
        }
    }
}

/// Slagtallet med form og scorefarge. Brukes overalt der et resultat vises: scorekort, feed,
/// feiring, «Alle runder» og spillerprofil.
struct ScoreBadge: View {
    let strokes: Int
    let par: Int
    /// Netto-resultatet som gir fargen. Nil: formen alene, uten fyll.
    let name: ScoreName?
    var size: CGFloat = 34

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    private var shape: ScoreShape { .forGross(strokes, par: par) }

    var body: some View {
        let side = size * scale
        let tone = name?.tone
        Text("\(strokes)")
            .font(.dd(.sans, size: size * 0.5, weight: .semibold, relativeTo: .body))
            .monospacedDigit()
            .foregroundStyle(tone?.foreground ?? Color.ddInk)
            .frame(width: side, height: side)
            .background {
                outline(fill: tone?.background ?? .clear, stroke: tone?.foreground ?? Color.ddInk, side: side)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private func outline(fill: Color, stroke: Color, side: CGFloat) -> some View {
        let inset = max(3, side * 0.1)
        switch shape {
        case .doubleCircle:
            ZStack {
                Circle().fill(fill)
                Circle().strokeBorder(stroke, lineWidth: 1.5)
                Circle().strokeBorder(stroke, lineWidth: 1.5).padding(inset)
            }
        case .circle:
            ZStack {
                Circle().fill(fill)
                Circle().strokeBorder(stroke, lineWidth: 1.5)
            }
        case .plain:
            RoundedRectangle(cornerRadius: side * 0.22, style: .continuous).fill(fill)
        case .square:
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(fill)
                RoundedRectangle(cornerRadius: 4).strokeBorder(stroke, lineWidth: 1.5)
            }
        case .doubleSquare:
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(fill)
                RoundedRectangle(cornerRadius: 4).strokeBorder(stroke, lineWidth: 1.5)
                RoundedRectangle(cornerRadius: 2).strokeBorder(stroke, lineWidth: 1.5).padding(inset)
            }
        }
    }

    private var accessibilityText: String {
        let base = "\(strokes) slag"
        guard let name else { return base }
        return "\(base), \(name.label.lowercased())"
    }
}

/// «Deg»-merket: én form overalt (planen P6), gull-pille ved navnet.
struct DDYouBadge: View {
    var body: some View {
        Text("Deg")
            .font(.ddStatus)
            .foregroundStyle(Color.ddGoldInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.ddGold))
            .accessibilityLabel("deg")
    }
}

/// Poengtall i en farget rundel, som på scorekortet (`1` i blush, `4` i sol …). Tom = «–».
struct DDPointsBadge: View {
    let points: Int?
    let name: ScoreName?

    var body: some View {
        Text(points.map(String.init) ?? "–")
            .font(.dd(.sans, size: 15, weight: .semibold, relativeTo: .body))
            .monospacedDigit()
            .foregroundStyle(name?.tone.foreground ?? .ddInkSecondary)
            .frame(minWidth: 34, minHeight: 28)
            .padding(.horizontal, 4)
            .background(Capsule().fill(name?.tone.background ?? Color.ddChipFill))
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
    /// Portrettet når det finnes (`.gg-avatar.bilde`), ellers initialene.
    var image: UIImage? = nil

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Text(Self.initials(name))
                    .font(.dd(.sans, size: size * 0.4, weight: .semibold, relativeTo: .caption))
                    .foregroundStyle(Color.ddLimeInk)
                    .frame(width: size, height: size)
                    .background(Circle().fill(Color.ddLimeBackground))
            }
        }
        .accessibilityHidden(true)
    }

    nonisolated static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
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
