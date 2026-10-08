import Foundation

// En låst konkurranse (besluttet 08.10.2026): en liga eller cup som krever kjøp, men der kjøpet
// ikke ble koblet til den (kjøpet gikk gjennom, men koblingen feilet, eller den ble laget uten
// kjøp). Konkurransesiden viser da en betalingsknapp for den som styrer den, og en kort tekst for
// de andre. Ren logikk; visningen ligger i `CompetitionUnlockSection`.

/// Hva konkurransesiden viser om kjøpet.
nonisolated enum CompetitionLockNotice: Equatable, Sendable {
    /// Ulåst, gratis, ikke avgjort ennå, eller kjøp er av: ingenting.
    case hidden
    /// Du styrer den og har ingen ledig kreditt: åpne betalingsveggen for akkurat denne.
    case purchase
    /// Du styrer den og har et kjøp som ikke er brukt: koble det (`assign_purchase`), uten nytt kjøp.
    case useCredit
    /// Du er med, men styrer den ikke: arrangøren (klubb) eller eieren (privat) må låse den opp.
    case waitForOrganizer(isClub: Bool)

    var title: String? {
        self == .hidden ? nil : "Ikke låst opp ennå"
    }

    var message: String? {
        switch self {
        case .hidden:
            nil
        case .purchase:
            "Liga og cup låses opp med et kjøp i appen, og det er ikke koblet noe kjøp til denne. "
                + "Har du betalt uten at det ble registrert, trykker du «Gjenopprett kjøp» på neste side."
        case .useCredit:
            "Du har et kjøp som ikke er brukt på noen turnering. Bruk det her, så er turneringen låst opp. "
                + "Du betaler ikke på nytt."
        case .waitForOrganizer(let isClub):
            "\(isClub ? "Arrangøren" : "Eieren") må låse den opp med et kjøp i appen."
        }
    }

    var buttonTitle: String? {
        switch self {
        case .purchase: "Lås opp turneringen"
        case .useCredit: "Bruk kjøpet ditt"
        case .hidden, .waitForOrganizer: nil
        }
    }
}

nonisolated enum CompetitionLock {
    /// Regelen. `serverUnlocked` er svaret fra `competition_is_unlocked` (fasit), nil før det har
    /// kommet eller uten nett. Da brukes kjøpene appen har hentet, men bare til å si «ulåst»: RLS
    /// viser ikke deltakerne eierens kjøp, så et lokalt «låst» er aldri nok til å vise noe.
    static func notice(requiresPurchase: Bool, isFinished: Bool, isAdmin: Bool, isClub: Bool,
                       serverUnlocked: Bool?, localUnlocked: Bool, hasOwnCredit: Bool,
                       enabled: Bool = PurchaseFeature.isEnabled) -> CompetitionLockNotice {
        guard enabled, requiresPurchase, !isFinished else { return .hidden }
        let unlocked = serverUnlocked ?? (localUnlocked ? true : nil)
        guard unlocked == false else { return .hidden }
        guard isAdmin else { return .waitForOrganizer(isClub: isClub) }
        return hasOwnCredit ? .useCredit : .purchase
    }

    /// For en konkurranse sett fra deg. «Styrer» er `is_competition_admin` (arrangør i klubben,
    /// eller eieren av en privat), samme regel som `assign_purchase` og `record_purchase` i sql/023.
    static func notice(for c: CompetitionRow, access: CompetitionAccess, serverUnlocked: Bool?,
                       entitlements: [EntitlementRow], enabled: Bool = PurchaseFeature.isEnabled,
                       now: Date = .now) -> CompetitionLockNotice {
        let info = CompetitionPurchaseInfo(id: c.id, requiresPurchase: c.requiresPurchase, entitlementID: c.entitlementID,
                                           ownerID: c.ownerID, clubID: c.clubID)
        return notice(requiresPurchase: c.requiresPurchase, isFinished: c.status == .finished,
                      isAdmin: access.isAdmin(c), isClub: c.clubID != nil, serverUnlocked: serverUnlocked,
                      localUnlocked: CompetitionUnlock.isUnlocked(info, entitlements: entitlements, now: now),
                      hasOwnCredit: CompetitionUnlock.unusedCredit(in: entitlements, owner: access.profileID) != nil,
                      enabled: enabled)
    }
}
