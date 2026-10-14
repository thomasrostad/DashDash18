import SwiftUI

/// Reaksjonsbrikke: emoji og antall. Din egen er valgt (skog med krem tekst, planen 1.3: lime er
/// bare live), de andres jordfarget. Brikken er 36 pt høy, trykkflaten 44 pt (planen P4).
struct DDReactionChip: View {
    let emoji: String
    let count: Int
    var isMine = false

    var body: some View {
        HStack(spacing: 4) {
            Text(emoji)
            Text("\(count)")
                .font(.ddChip)
                .monospacedDigit()
        }
        .foregroundStyle(isMine ? Color.ddSelectedInk : Color.ddInk)
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .background(Capsule().fill(isMine ? Color.ddSelected : Color.ddEarth))
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// «Legg til reaksjon»: rund knapp på 44 pt med smilefjes og pluss (planen P4).
struct DDAddReactionLabel: View {
    var body: some View {
        Image(systemName: "face.smiling")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Color.ddForestInk)
            .overlay(alignment: .topTrailing) {
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(Color.ddForestInk)
                    .offset(x: 5, y: -3)
            }
            .frame(width: 44, height: 44)
            .background(Circle().fill(Color.ddChipFill))
            .contentShape(Circle())
    }
}

/// Ikon i en rund jordfarget flis foran en linje (varsler, aktivitet), som `.gg-varsel-ikon`.
struct DDIconTile: View {
    let systemImage: String
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(Color.ddForestInk)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.ddEarth))
            .accessibilityHidden(true)
    }
}

/// Rust-prikk for ulest.
struct DDUnreadDot: View {
    var body: some View {
        Circle()
            .fill(Color.ddRust)
            .frame(width: 9, height: 9)
    }
}

/// Tallmerke på bjella og faner: rust med krem tekst (samme par som pengeknappen, 4,5:1+).
struct DDCountBadge: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.dd(.sans, size: 11, weight: .bold, relativeTo: .caption2))
            .monospacedDigit()
            .foregroundStyle(DDToken.buttonMoneyText.color)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(Capsule().fill(DDToken.buttonMoney.color))
    }
}

/// Meldingsboble: dine i skoggrønt med krem tekst, de andres på kort. Hjørnet mot avsenderen er lite.
struct DDBubbleModifier: ViewModifier {
    let mine: Bool

    func body(content: Content) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 20,
            bottomLeadingRadius: mine ? 20 : 6,
            bottomTrailingRadius: mine ? 6 : 20,
            topTrailingRadius: 20,
            style: .continuous
        )
        content
            .font(.ddBody)
            .foregroundStyle(mine ? Color.ddOnDark : Color.ddInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                if mine {
                    shape.fill(Color.ddForest)
                } else {
                    shape.fill(Color.ddCard)
                        .overlay(shape.strokeBorder(Color.ddCardBorder, lineWidth: 1))
                }
            }
    }
}

extension View {
    func ddBubble(mine: Bool) -> some View {
        modifier(DDBubbleModifier(mine: mine))
    }
}

/// Sendeknapp i skrivefeltet: gul rundel med pil (golfee-hovedhandlingen).
struct DDSendButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DDSendBody(configuration: configuration)
    }
}

private struct DDSendBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(isEnabled ? DDToken.buttonPrimaryText.color : DDToken.buttonDisabledText.color)
            .frame(width: 44, height: 44)
            .background(Circle().fill(isEnabled
                ? (configuration.isPressed ? DDToken.buttonPrimaryPressed.color : DDToken.buttonPrimary.color)
                : DDToken.buttonDisabled.color))
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview("Sosialt") {
    VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 6) {
            DDReactionChip(emoji: "🔥", count: 2, isMine: true)
            DDReactionChip(emoji: "👍", count: 1)
            DDAddReactionLabel()
            DDUnreadDot()
            DDCountBadge("3")
            DDIconTile(systemImage: "flag.fill")
        }
        Text("Blir litt sen, starter dere uten meg?").ddBubble(mine: false)
        HStack {
            Spacer()
            Text("Vi venter ved båsen 👍").ddBubble(mine: true)
        }
        Button {} label: { Image(systemName: "arrow.up") }
            .buttonStyle(DDSendButtonStyle())
    }
    .padding(DDSpacing.gutter)
    .ddScreenBackground()
}
