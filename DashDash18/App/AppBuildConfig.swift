import Foundation
import Supabase
import Synchronization

/// En rad i `app_config` (sql/031).
nonisolated struct AppConfigRow: Decodable, Sendable {
    let key: String
    let value: AnyJSON?
}

/// Det appen leser fra `app_config` etter innlogging: minste bygg (031), anbefalt bygg og
/// nødbrytere (068). En rad som mangler eller ikke kan leses, virker ikke.
nonisolated struct AppBuildConfig: Equatable, Sendable {
    static let keys = ["min_ios_build", "recommended_ios_build", "ios_flags"]

    var minimumBuild: Int?
    var recommendedBuild: Int?
    /// `ios_flags`: `{"social": false}`. Bare sanne og usanne verdier tas med.
    var flags: [String: Bool] = [:]

    init(minimumBuild: Int? = nil, recommendedBuild: Int? = nil, flags: [String: Bool] = [:]) {
        self.minimumBuild = minimumBuild
        self.recommendedBuild = recommendedBuild
        self.flags = flags
    }

    init(rows: [AppConfigRow]) {
        for row in rows {
            switch row.key {
            case "min_ios_build": minimumBuild = Self.build(row.value)
            case "recommended_ios_build": recommendedBuild = Self.build(row.value)
            case "ios_flags": flags = row.value?.objectValue?.compactMapValues(\.boolValue) ?? [:]
            default: break
            }
        }
    }

    private static func build(_ value: AnyJSON?) -> Int? {
        guard let value else { return nil }
        return (try? value.decode(as: MinimumBuildValue.self))?.build
    }
}

/// Nødbrytere fra serveren (`app_config.ios_flags`, sql/068). `{"social": false}` slår av Sosialt
/// uten nytt bygg. Bare av, aldri på: det som er av i bygget, kan ikke slås på herfra (App Review
/// 2.3.1 forbyr skjulte funksjoner). Svaret huskes til neste oppstart, så en avslått funksjon
/// forblir av også uten nett. Settes av `MinimumBuildGate` etter innlogging og når appen blir aktiv.
nonisolated enum KillSwitch {
    private static let key = "killSwitches068"
    private static let state = Mutex<[String: Bool]>(
        (UserDefaults.standard.dictionary(forKey: key) as? [String: Bool]) ?? [:])

    /// Er funksjonen slått av fra serveren?
    static func isOff(_ name: String) -> Bool { state.withLock { $0[name] == false } }

    static func set(_ flags: [String: Bool]) {
        state.withLock { $0 = flags }
        UserDefaults.standard.set(flags, forKey: key)
    }
}
