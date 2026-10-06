import SwiftUI

/// Knappeklassene fra PWA-en (handoff «knappelogikken», 01.10.2026). Én fargeregel:
/// skoggrønn = hovedhandling, rust = kroner flytter seg, gull = LD/KP,
/// bark på blush = noe forsvinner. Rust er ikke lenkefarge.
enum DDButtonKind {
    /// `.hoved` (56): skjermens hovedhandling.
    case primary
    /// `.penger` (56): kroner flytter seg.
    case money
    /// `.sekundaer` (48): omriss.
    case secondary
    /// `.tekst` (44 trykkflate): lenke-aktig.
    case text
    /// `.fare` (48): noe forsvinner.
    case danger
    /// `.fare.endelig` (56): siste trinn i en bekreftelse.
    case dangerFinal
    /// `.gull` (48): longest drive og nærmest pinnen.
    case gold
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

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(font)
            .multilineTextAlignment(.center)
            .foregroundStyle(foreground(pressed: pressed))
            .padding(.horizontal, style.kind == .text ? 10 : (style.compact ? 14 : 22))
            .padding(.vertical, style.compact ? 6 : 10)
            .frame(minHeight: minHeight)
            .frame(maxWidth: style.fullWidth ? .infinity : nil)
            .background {
                Capsule().fill(background(pressed: pressed))
                if let border = border {
                    Capsule().strokeBorder(border, style: borderStroke)
                }
            }
            .shadow(color: shadow, radius: 10, y: 8)
            .contentShape(Capsule())
            .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }

    private var font: Font {
        switch style.kind {
        case .primary, .money, .dangerFinal: style.compact ? .ddButton : .ddButtonLarge
        case .text: .dd(.grotesk, size: 15, weight: .semibold, relativeTo: .body)
        default: style.compact ? .dd(.grotesk, size: 14, weight: .semibold, relativeTo: .subheadline) : .ddButton
        }
    }

    private var minHeight: CGFloat {
        if style.compact { return 44 }
        switch style.kind {
        case .primary, .money, .dangerFinal: return 56
        case .secondary, .danger, .gold: return 48
        case .text: return 44
        }
    }

    private func token(_ token: DDToken) -> Color { token.color }

    private func foreground(pressed: Bool) -> Color {
        if !isEnabled { return token(.buttonDisabledText) }
        if style.onDark {
            switch style.kind {
            case .primary: return .ddForest
            case .secondary, .text: return .ddOnDark
            default: break
            }
        }
        switch style.kind {
        case .primary: return token(.buttonPrimaryText)
        case .money: return token(.buttonMoneyText)
        case .secondary: return pressed ? token(.buttonOKText) : token(.buttonLine)
        case .text: return token(.buttonLine)
        case .danger: return token(.buttonDangerText)
        case .dangerFinal: return Color(uiColor: DDRGBA(0xFCE5DB).uiColor)
        case .gold: return token(.buttonGoldText)
        }
    }

    private func background(pressed: Bool) -> Color {
        if !isEnabled { return style.kind == .text ? .clear : token(.buttonDisabled) }
        if style.onDark {
            switch style.kind {
            case .primary: return .ddOnDark
            case .secondary: return pressed ? Color.ddOnDark.opacity(0.12) : .clear
            case .text: return pressed ? Color.ddOnDark.opacity(0.12) : .clear
            default: break
            }
        }
        switch style.kind {
        case .primary: return pressed ? token(.buttonPrimaryPressed) : token(.buttonPrimary)
        case .money: return pressed ? token(.buttonMoneyPressed) : token(.buttonMoney)
        case .secondary: return pressed ? token(.buttonOK) : .ddCard
        case .text: return pressed ? token(.buttonOK) : .clear
        case .danger: return pressed ? token(.buttonDangerPressed) : token(.buttonDanger)
        case .dangerFinal: return Color(uiColor: DDRGBA(pressed ? 0x4A1E05 : 0x612807).uiColor)
        case .gold: return pressed ? token(.buttonGoldPressed) : token(.buttonGold)
        }
    }

    private var border: Color? {
        if !isEnabled {
            // Sperret hovedknapp får stiplet kant, aldri gjennomsiktighet (style.css «tilstander»).
            return style.kind == .primary ? token(.buttonDisabledText) : nil
        }
        switch style.kind {
        case .secondary: return style.onDark ? Color.ddOnDark.opacity(0.55) : token(.buttonLine)
        default: return nil
        }
    }

    private var borderStroke: StrokeStyle {
        isEnabled ? StrokeStyle(lineWidth: 1.5) : StrokeStyle(lineWidth: 1, dash: [3, 3])
    }

    private var shadow: Color {
        guard isEnabled, !style.compact else { return .clear }
        switch style.kind {
        case .primary where !style.onDark: return Color(red: 28 / 255, green: 72 / 255, blue: 58 / 255).opacity(0.35)
        case .money: return Color(red: 191 / 255, green: 84 / 255, blue: 18 / 255).opacity(0.35)
        default: return .clear
        }
    }
}

extension ButtonStyle where Self == DDButtonStyle {
    /// Skoggrønn hovedknapp over hele bredden.
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

/// Valgknapp i en gruppe (`.gg-seg` / `.gg-segment`): pille som er fylt når den er valgt.
struct DDChoiceButtonStyle: ButtonStyle {
    let selected: Bool
    /// Fargen når valgt. Standard er skoggrønn.
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
        configuration.label
            .font(.dd(.grotesk, size: 14.5, weight: selected ? .semibold : .medium, relativeTo: .subheadline))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(background))
            .overlay(Capsule().strokeBorder(selected ? Color.clear : Color.ddHairline, lineWidth: 1))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.6)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var background: Color {
        guard selected else { return .ddCard }
        switch tint {
        case .forest: return DDToken.buttonPrimary.color
        case .lime: return .ddLimeBackground
        case .sun: return .ddSunBackground
        case .blush: return .ddBlushBackground
        }
    }

    private var foreground: Color {
        guard selected else { return .ddInkSecondary }
        switch tint {
        case .forest: return DDToken.buttonPrimaryText.color
        case .lime: return .ddLimeInk
        case .sun: return .ddSunInk
        case .blush: return .ddRustDark
        }
    }
}
