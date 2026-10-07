import Foundation
import Security
import UserNotifications

// Rydding av det appen har lagret på telefonen (sikkerhetsrevisjonen, docs/sikkerhet-app.md).
//
// - Ved utlogging: widgetene, Live Activity, varslene i varselsenteret og bildene i minnet viser
//   ikke lenger den forrige innloggingens data.
// - Ved sletting av konto: i tillegg hullene i utboksen og innstillingene som hører til kontoen.
// - Ved ny installasjon: en innlogging som ligger igjen i nøkkelringen fra en tidligere
//   installasjon, brukes ikke.

/// Hva som ryddes. Ren logikk, så den kan testes uten telefonens lagre.
nonisolated enum LocalDataReset {
    /// Nøkler i `UserDefaults` som ikke hører til én bestemt innlogging, men som sier noe om
    /// klubber og kjøp (valgt klubb, sist lest i tråden og Varsler, ventende kjøp).
    static let sharedAccountPrefixes = ["medlemskap.", "trad.lastSeen.", "varsler.sistSett.", "valgtKlubb", "ventendeKjop"]

    /// Nøklene som skal bort når kontoen `userID` er slettet: alt med kontoens id i navnet
    /// (uansett store eller små bokstaver), og det som er felles for klubber og kjøp.
    static func accountKeys(in keys: some Sequence<String>, userID: UUID) -> [String] {
        let id = userID.uuidString.lowercased()
        return keys.filter { key in
            key.lowercased().contains(id) || sharedAccountPrefixes.contains { key.hasPrefix($0) }
        }
        .sorted()
    }

    /// Fjerner kontoens nøkler fra `defaults`. Gir nøklene som ble fjernet.
    @discardableResult
    static func removeAccountData(userID: UUID, defaults: UserDefaults = .standard) -> [String] {
        let keys = accountKeys(in: defaults.dictionaryRepresentation().keys, userID: userID)
        keys.forEach(defaults.removeObject(forKey:))
        return keys
    }
}

/// Det som må ryddes på telefonen når ingen er logget inn lenger (utlogging, sletting av konto,
/// eller en økt som ikke kunne fornyes).
enum SignedOutCleanup {
    static func run() {
        // Widgetene viste neste kveld og topp 3 for klubben til den som logget ut.
        WidgetSnapshotStore.shared.clear()
        // Live Activity på låseskjermen viser runden og navnet.
        RoundActivityController.shared.endAll()
        // Varsler som er levert, står ellers i varselsenteret med meldinger fra tråden.
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        center.setBadgeCount(0)
        // Bildene fra tråden og portrettene som ligger i minnet.
        TradImageStore.shared.removeAll()
    }
}

/// Nøkkelringen overlever at appen slettes. Uten denne vakten ville en ny installasjon logget
/// inn igjen med økten fra den forrige (f.eks. etter at telefonen er gitt videre uten tilbakestilling,
/// eller når noen sletter appen for å «logge ut»). `UserDefaults` slettes sammen med appen, så en
/// tom `UserDefaults` uten merket betyr ny installasjon.
nonisolated enum FreshInstallGuard {
    static let markerKey = "installasjonSett"
    /// Tjenesten supabase-swift lagrer økten under (`KeychainLocalStorage`).
    static let keychainService = "supabase.gotrue.swift"

    enum Decision: Equatable {
        /// Merket finnes: ingenting å gjøre.
        case known
        /// Appen er oppdatert fra en versjon uten merket: behold økten, sett merket.
        case upgraded
        /// Ny installasjon: fjern økten fra nøkkelringen, sett merket.
        case freshInstall
    }

    /// `appDefaults` er appens egne verdier (`persistentDomain`), ikke de globale.
    static func decide(appDefaults: [String: Any]?) -> Decision {
        let values = appDefaults ?? [:]
        if values[markerKey] != nil { return .known }
        return values.isEmpty ? .freshInstall : .upgraded
    }

    /// Kjøres før Supabase-klienten lages, så den gamle økten aldri leses.
    static func run(defaults: UserDefaults = .standard,
                    domain: String? = Bundle.main.bundleIdentifier,
                    clearSession: () -> Void = clearKeychainSession) {
        let decision = decide(appDefaults: domain.flatMap(defaults.persistentDomain(forName:)))
        if decision == .freshInstall { clearSession() }
        if decision != .known { defaults.set(true, forKey: markerKey) }
    }

    /// Sletter supabase-swift sine poster i nøkkelringen (økten og PKCE-verifikatoren).
    static func clearKeychainSession() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
