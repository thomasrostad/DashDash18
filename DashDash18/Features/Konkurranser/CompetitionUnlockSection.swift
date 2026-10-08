import SwiftUI

/// Låst konkurranse på konkurransesiden (besluttet 08.10.2026). Den som styrer den, får én knapp:
/// betalingsveggen for akkurat denne, eller «Bruk kjøpet ditt» når et kjøp står ubrukt. De andre
/// ser en kort tekst. Hva som vises, avgjøres av `CompetitionLock`.
struct CompetitionUnlockSection: View {
    let notice: CompetitionLockNotice
    var isWorking = false
    var error: String?
    let onUnlock: () -> Void

    var body: some View {
        switch notice {
        case .hidden:
            EmptyView()
        case .waitForOrganizer:
            DDInfoStripe(tone: .sun) {
                Label {
                    Text(LocalizedStringKey("**\(notice.title ?? "")**. \(notice.message ?? "")"))
                } icon: {
                    Image(systemName: "lock")
                }
            }
            .accessibilityElement(children: .combine)
        case .purchase, .useCredit:
            ownerCard
        }
    }

    private var ownerCard: some View {
        VStack(alignment: .leading, spacing: DDSpacing.m) {
            Label {
                Text(notice.title ?? "")
                    .font(.ddBodyEmphasis)
                    .foregroundStyle(Color.ddInk)
            } icon: {
                Image(systemName: "lock.fill")
                    .foregroundStyle(Color.ddForestInk)
            }
            .accessibilityAddTraits(.isHeader)
            Text(notice.message ?? "")
                .font(.ddCallout)
                .foregroundStyle(Color.ddInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onUnlock) {
                if isWorking {
                    ProgressView()
                } else {
                    Text(notice.buttonTitle ?? "")
                }
            }
            .buttonStyle(.dd(notice == .purchase ? .money : .primary, fullWidth: true))
            .disabled(isWorking)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddError)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ddCard()
    }
}
