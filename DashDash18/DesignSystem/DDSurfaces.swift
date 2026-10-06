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
}

enum DDRadius {
    static let input: CGFloat = 12
    static let card: CGFloat = 16
    static let cardLarge: CGFloat = 20
    static let sheet: CGFloat = 22
}

/// Korttyper: `.gg-card`, `.gg-card.pad-lg` og det grønne hero-kortet `.gg-green`.
enum DDCardStyle {
    case standard
    case large
    case hero
    /// Stiplet ramme uten fyll (`.gg-empty`), for tomtilstander.
    case empty
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
            .foregroundStyle(style == .hero ? Color.ddOnDark : Color.ddInk)
            .background {
                switch style {
                case .empty:
                    shape.strokeBorder(Color.ddRuleCream, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
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
    }

    private var radius: CGFloat { style == .standard ? DDRadius.card : DDRadius.cardLarge }
    private var defaultPadding: CGFloat {
        switch style {
        case .standard, .empty: DDSpacing.l
        case .large: 22
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

    /// Radene i en seksjon får kortfargen (hvit i lys, #132B23 i mørk).
    func ddRowBackground() -> some View {
        listRowBackground(Color.ddCard)
    }

    /// Grønn navigasjonslinje med krem tekst, som headeren i PWA-en.
    func ddNavigationChrome() -> some View {
        toolbarBackground(Color.ddForest, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
            .font(.dd(.grotesk, size: 16, relativeTo: .body))
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
