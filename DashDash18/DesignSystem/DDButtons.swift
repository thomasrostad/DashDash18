import SwiftUI

/// Fire knappestiler (utbedringsplanen 1.3, 13.10.2026):
/// 1. hoved: gul kapsel, 56 pt, maks én per skjerm, nederst i tommelsonen,
/// 2. sekundær: lys skogflate med skogtekst,
/// 3. tekst: skogfarget tekst uten flate,
/// 4. destruktiv: rust-tekst på blush, alltid bak en bekreftelse.
/// De eldre klassene (penger, gull, endelig fare) tegnes som en av de fire, så hver farge har én betydning.
enum DDButtonKind {
    /// Skjermens hovedhandling, gul kapsel.
    case primary
    /// Kroner flytter seg. Tegnes som hovedknapp.
    case money
    /// Lys skogflate.
    case secondary
    /// Lenke-aktig, 44 pt trykkflate.
    case text
    /// Noe forsvinner: rust-tekst på blush.
    case danger
    /// Siste trinn i en bekreftelse. Som `danger`, men 56 pt.
    case dangerFinal
    /// Longest drive og nærmest pinnen. Tegnes som sekundær (gull er bare for «Deg», jakka og leder).
    case gold

    /// Stilen knappen faktisk tegnes med.
    var look: Look {
        switch self {
        case .primary, .money: .primary
        case .secondary, .gold: .secondary
        case .text: .text
        case .danger, .dangerFinal: .destructive
        }
    }

    enum Look { case primary, secondary, text, destructive }
}

struct DDButtonStyle: ButtonStyle {
    let kind: DDButtonKind
    /// Fyll hele bredden (`.block`).
    var fullWidth = false
    /// Mindre variant (`.sm`) for knapper i rader.
    var compact = false
    /// Ligger knappen på grønn flate (hero-kort, velkomst)?
    var onDark = false

    func makeBody(configuration: Configuration) -> some View {
        DDButtonBody(configuration: configuration, style: self)
    }
}

private struct DDButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let style: DDButtonStyle
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var look: DDButtonKind.Look { style.kind.look }

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(font)
            .multilineTextAlignment(.center)
            .foregroundStyle(foreground)
            .padding(.horizontal, look == .text ? 10 : (style.compact ? 14 : 22))
            .padding(.vertical, style.compact ? 6 : 10)
            .frame(minHeight: minHeight)
            .frame(maxWidth: style.fullWidth ? .infinity : nil)
            .background {
                Capsule().fill(background(pressed: pressed))
                if look == .secondary && style.onDark {
                    Capsule().strokeBorder(Color.ddOnDark.opacity(0.45), lineWidth: 1)
                }
            }
            .contentShape(Capsule())
            // Deaktivert: samme knapp, dempet. Aldri stiplet (planen 1.3).
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }

    private var font: Font {
        switch look {
        case .primary: style.compact ? .ddButton : .ddButtonLarge
        case .text: .dd(.sans, size: 16, weight: .semibold, relativeTo: .body)
        default: style.compact ? .dd(.sans, size: 15, weight: .semibold, relativeTo: .subheadline) : .ddButtonLarge
        }
    }

    private var minHeight: CGFloat {
        if style.compact { return 44 }
        switch style.kind {
        case .primary, .money, .dangerFinal: return 56
        case .secondary, .danger, .gold: return 50
        case .text: return 44
        }
    }

    private var foreground: Color {
        if style.onDark, look == .secondary || look == .text { return .ddOnDark }
        switch look {
        case .primary: return DDToken.buttonPrimaryText.color
        case .secondary, .text: return DDToken.buttonLine.color
        case .destructive: return DDToken.buttonDangerText.color
        }
    }

    private func background(pressed: Bool) -> Color {
        if style.onDark, look == .secondary || look == .text {
            return pressed ? Color.ddOnDark.opacity(0.2) : (look == .secondary ? Color.ddOnDark.opacity(0.1) : .clear)
        }
        switch look {
        case .primary: return pressed ? DDToken.buttonPrimaryPressed.color : DDToken.buttonPrimary.color
        case .secondary: return pressed ? DDToken.buttonSecondaryPressed.color : DDToken.buttonSecondary.color
        case .text: return pressed ? DDToken.buttonSecondary.color : .clear
        case .destructive: return pressed ? DDToken.buttonDangerPressed.color : DDToken.buttonDanger.color
        }
    }
}

extension ButtonStyle where Self == DDButtonStyle {
    /// Gul hovedknapp over hele bredden.
    static var ddPrimary: DDButtonStyle { DDButtonStyle(kind: .primary, fullWidth: true) }
    static var ddMoney: DDButtonStyle { DDButtonStyle(kind: .money, fullWidth: true) }
    static var ddSecondary: DDButtonStyle { DDButtonStyle(kind: .secondary) }
    static var ddText: DDButtonStyle { DDButtonStyle(kind: .text) }
    static var ddDanger: DDButtonStyle { DDButtonStyle(kind: .danger) }
    static var ddGold: DDButtonStyle { DDButtonStyle(kind: .gold) }

    static func dd(_ kind: DDButtonKind, fullWidth: Bool = false, compact: Bool = false,
                   onDark: Bool = false) -> DDButtonStyle {
        DDButtonStyle(kind: kind, fullWidth: fullWidth, compact: compact, onDark: onDark)
    }
}

/// Valgknapp i en gruppe (`.gg-seg` / `.gg-segment`): skog fylt med krem tekst og hake når den er valgt
/// (planen 1.3: valgt er aldri lime).
struct DDChoiceButtonStyle: ButtonStyle {
    let selected: Bool
    /// Fra før valgte knappen farge. Nå tegnes alle valgte likt; verdien beholdes for kallene.
    var tint: DDChoiceTint = .forest

    func makeBody(configuration: Configuration) -> some View {
        DDChoiceBody(configuration: configuration, selected: selected, tint: tint)
    }
}

enum DDChoiceTint {
    case forest, lime, sun, blush
}

private struct DDChoiceBody: View {
    let configuration: ButtonStyleConfiguration
    let selected: Bool
    let tint: DDChoiceTint
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(.footnote, weight: .bold))
                    .accessibilityHidden(true)
            }
            configuration.label
        }
            .font(.dd(.sans, size: 15, weight: selected ? .semibold : .medium, relativeTo: .subheadline))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(background))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var background: Color {
        selected ? .ddSelected : .ddChipFill
    }

    private var foreground: Color {
        selected ? .ddSelectedInk : .ddInk
    }
}

// MARK: - Verktøylinja

/// Bekreftelsen i verktøylinja («Lagre», «Lag», «Ferdig», «Send»): systemets fremhevede glass
/// tonet skog, med krem tekst (lys skog med mørk tekst i mørk modus). Gul er bare for skjermens
/// hovedknapp nederst (utbedringsplanen K3, 13.10.2026).
struct DDConfirmToolbarItem<Content: View>: ToolbarContent {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            content
                .buttonStyle(.glassProminent)
                .tint(Color.ddSelected)
                .foregroundStyle(Color.ddSelectedInk)
        }
    }
}

/// «Avbryt» og «Lukk» i verktøylinja: skogfarget tekst i systemets glass.
struct DDCancelToolbarItem<Content: View>: ToolbarContent {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            content.foregroundStyle(Color.ddForestInk)
        }
    }
}
