import SwiftUI

/// Rund stepper på hullkortet (`.gg-stepper`): minus i omriss, pluss fylt grønn.
struct DDStepperButtonStyle: ButtonStyle {
    enum Kind { case minus, plus }
    let kind: Kind
    /// 56 på enkelt hullkort, 48 i båsrader (`.gg-stepper.sm`).
    var size: CGFloat = 48

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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.system(size: size * 0.4, weight: .regular))
            .foregroundStyle(kind == .plus ? Color.ddOnDark : Color.ddForestInk)
            .frame(width: size, height: size)
            .background {
                switch kind {
                case .minus:
                    Circle().fill(pressed ? DDToken.buttonOK.color : Color.ddCard)
                    Circle().strokeBorder(Color.ddForestInk, lineWidth: 1.5)
                case .plus:
                    // Mørk modus: fortsatt skoggrønn flate (style.css `:root.mork .gg-stepper.plus`).
                    Circle().fill(pressed ? Color.ddForestDeep : plusFill)
                }
            }
            .contentShape(Circle())
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(pressed && !reduceMotion ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }

    private var plusFill: Color {
        colorScheme == .dark ? Color(uiColor: DDRGBA(0x1C483A).uiColor) : .ddForest
    }
}

/// Slagtallet på hullkortet. Før bekreftelse står det dempet i en stiplet rust-boks (par-forslag).
struct DDStrokeValue: View {
    let value: String
    let confirmed: Bool
    var size: CGFloat = 32

    var body: some View {
        Text(value)
            .font(.dd(.mono, size: size, weight: .medium, relativeTo: .title))
            .monospacedDigit()
            .tracking(-0.5)
            .foregroundStyle(confirmed ? Color.ddForestInk : Color.ddInkSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(minWidth: 46, minHeight: size + 16)
            .padding(.horizontal, 2)
            .overlay {
                if !confirmed {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.ddRust, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
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

/// Merket «LONGEST DRIVE» / «NÆRMEST PINNEN» øverst på hullkortet (`.gg-ldtag`).
struct DDSidePrizeTag: View {
    enum Kind { case longestDrive, closestToPin }
    let kind: Kind

    var body: some View {
        switch kind {
        case .longestDrive:
            DDPill("Longest drive", tone: .gold, systemImage: "ruler")
        case .closestToPin:
            DDPill("Nærmest pinnen", tone: .earthDeep, systemImage: "scope")
        }
    }
}
