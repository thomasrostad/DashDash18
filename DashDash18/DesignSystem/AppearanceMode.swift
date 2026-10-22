import SwiftUI

/// Utseende-valget under Deg → Utseende. «System» følger telefonen (standard). Lagres lokalt
/// med `@AppStorage(AppearanceMode.storageKey)` og settes på rota i `DashDash18App`. Tavla/TV
/// (mørk) og delekortet (lyst) tvinger sitt eget og påvirkes ikke.
nonisolated enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearanceMode"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Lys"
        case .dark: "Mørk"
        }
    }

    /// `nil` = følg systemet.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// Ukjent eller manglende lagret verdi gir «System».
    init(stored: String) {
        self = AppearanceMode(rawValue: stored) ?? .system
    }
}
