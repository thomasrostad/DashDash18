import Supabase
import SwiftUI

/// Sperrer appen med «Oppdater Atten» når bygget er eldre enn `app_config.min_ios_build`
/// (sql/031). Leses etter innlogging og hver gang appen blir aktiv. Ikke bak flagg: tabellen finnes,
/// og kravet er 0 til vi setter det før trinn 4 (sql/034). Mangler raden, eller feiler lesingen,
/// slipper appen alltid gjennom.
struct MinimumBuildGate<Content: View>: View {
    let client: SupabaseClient
    @ViewBuilder var content: Content
    @State private var required: Int?
    @Environment(\.scenePhase) private var scenePhase
    private let current = MinimumBuild.currentBuild()

    var body: some View {
        Group {
            if MinimumBuild.isOutdated(current: current, required: required) {
                UpdateRequiredView(current: current, required: required) { await check() }
            } else {
                content
            }
        }
        .task { await check() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await check() } }
        }
    }

    private func check() async {
        do {
            required = try await TournamentCoreQueries.minimumBuild(client: client)
        } catch is CancellationError {
        } catch {
            required = nil  // en feil sperrer aldri
        }
    }
}

/// «Oppdater Atten»: bygget er for gammelt til å bruke databasen.
struct UpdateRequiredView: View {
    let current: Int?
    let required: Int?
    var retry: () async -> Void = {}

    @Environment(\.openURL) private var openURL
    @State private var isChecking = false

    var body: some View {
        VStack(spacing: DDSpacing.l) {
            Spacer()
            Image(systemName: "arrow.down.app")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(Color.ddForestInk)
                .accessibilityHidden(true)
            Text("Oppdater Atten")
                .font(.ddTitle)
                .multilineTextAlignment(.center)
            Text("Denne utgaven av appen er for gammel til å brukes lenger. Hent den nyeste i TestFlight eller App Store, så er du i gang igjen. Ingenting av det du har ført, går tapt.")
                .font(.ddBody)
                .foregroundStyle(Color.ddInkSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            VStack(spacing: DDSpacing.m) {
                Button("Åpne TestFlight") {
                    if let url = URL(string: "itms-beta://") { openURL(url) }
                }
                .buttonStyle(.dd(.primary, fullWidth: true))
                Button(isChecking ? "Sjekker …" : "Jeg har oppdatert") {
                    isChecking = true
                    Task {
                        await retry()
                        isChecking = false
                    }
                }
                .buttonStyle(.dd(.secondary, fullWidth: true))
                .disabled(isChecking)
                if let current, let required {
                    Text("Bygg \(current) · krever \(required) eller nyere")
                        .font(.ddCaption)
                        .foregroundStyle(Color.ddInkSecondary)
                }
            }
        }
        .padding(.horizontal, DDSpacing.gutter)
        .padding(.vertical, DDSpacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ddScreenBackground()
    }
}

#Preview {
    UpdateRequiredView(current: 41, required: 57)
}
