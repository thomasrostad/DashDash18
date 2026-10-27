import SwiftUI

/// Avstander og radier fra style.css (4/8-grid).
enum DDSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    /// Sideluft på skjermene.
    static let gutter: CGFloat = 20
    /// Mellom kort.
    static let cardGap: CGFloat = 10
    /// Største bredde på innholdet når skjermen er bred (iPhone Duo åpen). Som UIKits `readableContentGuide`.
    static let readableWidth: CGFloat = 672
}

/// Store, myke hjørner (golfee) i stedet for PWA-ens 16/20.
enum DDRadius {
    static let input: CGFloat = 16
    static let card: CGFloat = 24
    static let cardLarge: CGFloat = 30
    static let sheet: CGFloat = 32
    /// «Din rad» i tabeller og lister (gulltonen bak raden).
    static let row: CGFloat = 14
}

/// Korttyper: `.gg-card`, `.gg-card.pad-lg` og det grønne hero-kortet `.gg-green`.
enum DDCardStyle {
    case standard
    case large
    case hero
    /// Uten fyll og ramme, for tomtilstander (`ContentUnavailableView`).
    case empty
    /// Liquid Glass over bakgrunnen (flytende kort og kontroller).
    case glass
    /// Svart statistikk-kort med hvite tall (scorekort, match, «Bayen nå»), fra golfee.
    case stat
}

struct DDCardModifier: ViewModifier {
    let style: DDCardStyle
    let padding: CGFloat?
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .padding(padding ?? defaultPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(foreground)
            .background {
                switch style {
                case .glass:
                    Color.clear
                case .stat:
                    shape.fill(Color.ddStatCard)
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.22), radius: 18, y: 12)
                case .empty:
                    // Tomtilstand uten ramme (planen V13): stiplet kant er bare for tomme plasser man kan fylle.
                    Color.clear
                case .hero:
                    shape.fill(Color.ddHeroCard)
                        .shadow(color: shadowColor.opacity(colorScheme == .dark ? 0.7 : 0.6), radius: 15, y: 14)
                default:
                    shape.fill(Color.ddCard)
                        .overlay(shape.strokeBorder(Color.ddCardBorder, lineWidth: 1))
                        .shadow(color: shadowColor.opacity(colorScheme == .dark ? 0.5 : (style == .large ? 0.3 : 0.2)),
                                radius: style == .large ? 17 : 11, y: style == .large ? 10 : 6)
                }
            }
            .modifier(DDGlassIfNeeded(enabled: style == .glass, radius: radius))
    }

    private var foreground: Color {
        switch style {
        case .hero: .ddOnDark
        case .stat: .ddStatText
        default: .ddInk
        }
    }

    private var radius: CGFloat { style == .standard || style == .glass ? DDRadius.card : DDRadius.cardLarge }
    private var defaultPadding: CGFloat {
        switch style {
        case .standard, .empty, .glass: DDSpacing.l + 2
        case .large, .stat: 22
        case .hero: DDSpacing.xl
        }
    }
    private var shadowColor: Color { colorScheme == .dark ? .black : Color(red: 28 / 255, green: 72 / 255, blue: 58 / 255) }
}

extension View {
    /// Hvitt kort (krem-hvitt i mørk modus) med stor radius og myk skygge.
    func ddCard(_ style: DDCardStyle = .standard, padding: CGFloat? = nil) -> some View {
        modifier(DDCardModifier(style: style, padding: padding))
    }

    /// Kremet bakgrunn bak hele skjermen.
    func ddScreenBackground() -> some View {
        background(Color.ddBackground.ignoresSafeArea())
    }

    /// List og Form: krem bakgrunn bak radene i stedet for systemgrå.
    func ddListStyle() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.ddBackground.ignoresSafeArea())
    }

    /// Systemets navigasjonslinje med glass over krem bakgrunn (utbedringsplanen P1, K3, 7.3):
    /// ingen egen grønn flate bak linja, så tilbakeknapp, glass, «Reduser gjennomsiktighet» og
    /// «Øk kontrast» virker som i resten av iOS. Skogen brukes i hero-kortene i stedet.
    /// Store titler på fanenes rot, og de krymper ved rulling (`automatic`).
    func ddNavigationChrome() -> some View {
        containerBackground(Color.ddBackground, for: .navigation)
    }

    /// Lister og rullbart innhold holder seg til `DDSpacing.readableWidth` midt på når skjermen er
    /// bred (`regular`, iPhone Duo åpen). Settes én gang per fane; smal skjerm er urørt.
    func ddReadableWidth() -> some View {
        modifier(DDReadableWidthModifier())
    }

    /// Faste felt over og under lista (`safeAreaInset`) følger samme kolonne som innholdet.
    func ddReadableFrame() -> some View {
        modifier(DDReadableFrameModifier())
    }
}

extension EnvironmentValues {
    /// Bredden på kolonnen fra `ddReadableWidth()`, eller nil på smal skjerm.
    @Entry var ddReadableMaxWidth: CGFloat?
}

struct DDReadableFrameModifier: ViewModifier {
    @Environment(\.ddReadableMaxWidth) private var maxWidth

    func body(content: Content) -> some View {
        content.frame(maxWidth: maxWidth ?? .infinity)
    }
}

/// Margene til `ddReadableWidth()`. `nil` på smal skjerm, så listene beholder sine egne marger og
/// visningen ikke byttes ut (og mister rulleposisjonen) når telefonen brettes.
struct DDReadableWidthModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .contentMargins(.horizontal, margin, for: .scrollContent)
            .environment(\.ddReadableMaxWidth, margin == nil ? nil : DDSpacing.readableWidth)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private var margin: CGFloat? {
        guard sizeClass == .regular, width > DDSpacing.readableWidth else { return nil }
        return (width - DDSpacing.readableWidth) / 2
    }
}

/// Skillelinje i et kort (`.divider`).
struct DDDivider: View {
    var onDark = false

    var body: some View {
        Rectangle()
            .fill(onDark ? Color.ddOnDark.opacity(0.18) : Color.ddRule)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// Inndatafelt (`.gg-field input`): hvit flate, grå kant, radius 12, minst 48 høy.
struct DDFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.dd(.sans, size: 16, relativeTo: .body))
            .foregroundStyle(Color.ddInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 48)
            .background(Color.ddCard, in: .rect(cornerRadius: DDRadius.input))
            .overlay {
                RoundedRectangle(cornerRadius: DDRadius.input)
                    .strokeBorder(Color.ddHairline, lineWidth: 1)
            }
    }
}

extension View {
    func ddField() -> some View { modifier(DDFieldModifier()) }
}

/// Liquid Glass med samme radius som kortet.
private struct DDGlassIfNeeded: ViewModifier {
    let enabled: Bool
    let radius: CGFloat

    func body(content: Content) -> some View {
        if enabled {
            content.glassEffect(.regular, in: .rect(cornerRadius: radius))
        } else {
            content
        }
    }
}
