import SwiftUI

/// Rund stepper på hullkortet (`HoleStepper` i planen 1.5): minus i omriss, pluss fylt skog
/// (lys skog i mørk modus). 52 pt som standard, og vokser med Dynamic Type.
struct DDStepperButtonStyle: ButtonStyle {
    enum Kind { case minus, plus }
    let kind: Kind
    var size: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        DDStepperBody(configuration: configuration, kind: kind, size: size)
    }
}

private struct DDStepperBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: DDStepperButtonStyle.Kind
    let size: CGFloat
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var scale: CGFloat = 1

    var body: some View {
        let pressed = configuration.isPressed
        let side = max(44, size * min(scale, 1.4))
        configuration.label
            .font(.system(size: side * 0.4, weight: .medium))
            .foregroundStyle(kind == .plus ? Color.ddCard : Color.ddForestInk)
            .frame(width: side, height: side)
            .background {
                switch kind {
                case .minus:
                    Circle().fill(pressed ? DDToken.buttonSecondary.color : Color.ddCard)
                    Circle().strokeBorder(Color.ddForestInk, lineWidth: 1.5)
                case .plus:
                    Circle().fill(DDToken.buttonLine.color.opacity(pressed ? 0.8 : 1))
                }
            }
            .contentShape(Circle())
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(pressed && !reduceMotion ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
}

/// Slagtallet på hullkortet. Forvalgt par som ikke er rørt, står dempet (planen K1);
/// et tall markøren har satt, står i full styrke med scoreformen.
struct DDStrokeValue: View {
    let value: String
    /// Rørt eller lagret. Urørt forvalg vises dempet.
    let confirmed: Bool
    var size: CGFloat = 40

    var body: some View {
        Text(value)
            .font(.dd(.sans, size: size, weight: .medium, relativeTo: .title))
            .monospacedDigit()
            .foregroundStyle(confirmed ? Color.ddForestInk : Color.ddInkSecondary)
            .contentTransition(.numericText())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(minWidth: 46, minHeight: 52)
            .padding(.horizontal, 2)
    }
}

/// Én hullprikk (`.gg-holedots`): en loddrett strek. Beige = ikke ført, grønn = ført,
/// rust og høyere = hullet du ser på. Prikk under: longest drive (rust) eller nærmest pinnen (gull).
struct DDHoleTick: View {
    enum Progress { case upcoming, partial, played }
    enum Marker { case none, longestDrive, closestToPin }

    let state: Progress
    var isCurrent = false
    var marker: Marker = .none
    /// Lagret lokalt, ikke sendt ennå.
    var isPending = false
    /// Båsens hull når du ser på et annet.
    var isBayHole = false

    var body: some View {
        VStack(spacing: 3) {
            Circle()
                .fill(isBayHole ? Color.ddForestInk : .clear)
                .frame(width: 4, height: 4)
            ZStack(alignment: .bottom) {
                Capsule().fill(isCurrent ? Color.ddRust : (state == .played ? Color.ddForestInk : Color.ddEarthDeep))
                if state == .partial && !isCurrent {
                    Capsule().fill(Color.ddForestInk).frame(height: 8)
                }
            }
            .frame(width: isCurrent ? 7 : 5, height: isCurrent ? 22 : 16)
            .overlay {
                if isPending {
                    Capsule().strokeBorder(Color.ddRust, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .padding(-2)
                }
            }
            Circle()
                .fill(markerColor)
                .frame(width: 4, height: 4)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .top)
        .contentShape(.rect)
    }

    private var markerColor: Color {
        switch marker {
        case .none: .clear
        case .longestDrive: .ddRust
        case .closestToPin: .ddGold
        }
    }
}

/// Hullbrikke på 44 × 44 pt i hullvelgeren (utbedringsplanen V15). Nåværende er fylt som valgt,
/// førte har chip-bakgrunn, kommende har strek, og hull i køen har rust stiplet kant.
/// Gull-prikk: sidepremie. Strek under: båsens hull.
struct DDHoleChip: View {
    enum Style: Equatable { case current, saved, partial, upcoming }

    let number: Int
    let style: Style
    var isPending = false
    var hasSidePrize = false
    var isBayHole = false
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 44

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Text("\(number)")
            .font(.dd(.sans, size: 17, weight: style == .current ? .semibold : .medium, relativeTo: .body))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(foreground)
            .frame(width: max(44, side), height: max(44, side))
            .background {
                switch style {
                case .current: shape.fill(Color.ddSelected)
                case .saved: shape.fill(Color.ddChipFill)
                case .partial:
                    shape.fill(Color.ddChipFill)
                    shape.strokeBorder(Color.ddForestInk, lineWidth: 1.5)
                case .upcoming: shape.strokeBorder(Color.ddInkSecondary.opacity(0.6), lineWidth: 1)
                }
            }
            .overlay {
                if isPending {
                    shape.strokeBorder(Color.ddRust, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                }
            }
            .overlay(alignment: .topTrailing) {
                if hasSidePrize {
                    Circle()
                        .fill(Color.ddGold)
                        .frame(width: 8, height: 8)
                        .padding(5)
                }
            }
            .overlay(alignment: .bottom) {
                if isBayHole {
                    Capsule()
                        .fill(Color.ddForestInk)
                        .frame(width: 18, height: 3)
                        .offset(y: 7)
                }
            }
            .contentShape(shape)
    }

    private var foreground: Color {
        switch style {
        case .current: .ddSelectedInk
        case .saved, .partial: .ddInk
        case .upcoming: .ddInkSecondary
        }
    }
}

/// Merket «LONGEST DRIVE» / «NÆRMEST PINNEN» øverst på hullkortet (`.gg-ldtag`).
struct DDSidePrizeTag: View {
    enum Kind { case longestDrive, closestToPin }
    let kind: Kind

    var body: some View {
        switch kind {
        case .longestDrive:
            DDPill("Longest drive", tone: .gold, systemImage: "ruler")
        case .closestToPin:
            DDPill("Nærmest pinnen", tone: .gold, systemImage: "scope")
        }
    }
}
