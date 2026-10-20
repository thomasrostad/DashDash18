import Foundation
import Supabase

/// Feilsporing med MetricKit (fase 17, lanseringssjekken 7.1). Krever `sql/064_feilrapporter.sql`.
/// Uten 064 feiler sendingen, radene blir liggende i køen på telefonen, og appen virker som før.
nonisolated enum DiagnosticsFeature {
    static let isEnabled = true
}

/// Hva MetricKit meldte. Samme verdier som `kind` i `public.app_diagnostics`.
nonisolated enum DiagnosticKind: String, Codable, Sendable, CaseIterable {
    case crash
    case hang
    case cpu
    case disk
    case launch

    /// Lista i `MXDiagnosticPayload.jsonRepresentation()` som har diagnosene av denne typen.
    var payloadKey: String {
        switch self {
        case .crash: "crashDiagnostics"
        case .hang: "hangDiagnostics"
        case .cpu: "cpuExceptionDiagnostics"
        case .disk: "diskWriteExceptionDiagnostics"
        case .launch: "appLaunchDiagnostics"
        }
    }
}

/// Én rad til `submit_diagnostics` (sql/064). Ingen persondata: serveren setter `user_id`
/// selv fra innloggingen.
nonisolated struct DiagnosticRecord: Codable, Sendable, Equatable, Identifiable {
    /// Bare for køen på telefonen (hvilke rader som er sendt). Serveren lager sin egen id.
    var id: UUID
    var kind: DiagnosticKind
    /// Kort oppsummering: unntak eller signal og øverste ramme i appen, høyst 300 tegn.
    var signature: String?
    var appVersion: String?
    var build: String?
    var osVersion: String?
    var deviceModel: String?
    /// Apples JSON med bare denne ene diagnosen (samme form som `MXDiagnosticPayload`).
    var payload: AnyJSON
    /// `test` eller `prod` (`AppEnvironment`).
    var environment: String

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case signature
        case appVersion = "app_version"
        case build
        case osVersion = "os_version"
        case deviceModel = "device_model"
        case payload
        case environment
    }
}
