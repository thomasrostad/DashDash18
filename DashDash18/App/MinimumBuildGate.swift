import Supabase
import SwiftUI

/// Sperrer appen med «Oppdater Atten» når bygget er eldre enn `app_config.min_ios_build`
/// (sql/031). Leses etter innlogging og hver gang appen blir aktiv. Ikke bak flagg: tabellen finnes,
/// og kravet er 0 til vi setter det før trinn 4 (sql/034). Mangler raden, eller feiler lesingen,
/// slipper appen alltid gjennom.
///
/// Samme lesing gir det anbefalte bygget (`recommended_ios_build`, sql/068): er bygget eldre, spør
/// «Ny versjon av Atten» én gang per anbefalt bygg, og du kan fortsette. Og nødbryterne
/// (`ios_flags`, sql/068), som legges i `KillSwitch`. En feil endrer ingen av dem.
struct MinimumBuildGate<Content: View>: View {
    let client: SupabaseClient
    @ViewBuilder var content: Content
    @State private var required: Int?
    @State private var recommended: Int?
    @State private var showsSuggestion = false
    @AppStorage("suggestedBuildDismissed") private var dismissed = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    private let current = MinimumBuild.currentBuild()
    private let link = MinimumBuild.updateLink(for: AppEnvironment.current)

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
        .alert("Ny versjon av Atten", isPresented: $showsSuggestion) {
            Button("Oppdater") {
                dismissed = recommended ?? dismissed
                openURL(link.url)
            }
            Button("Senere", role: .cancel) { dismissed = recommended ?? dismissed }
        } message: {
            Text(link.suggestion)
        }
    }

    private func check() async {
        do {
            let config = try await TournamentCoreQueries.buildConfig(client: client)
            required = config.minimumBuild
            recommended = config.recommendedBuild
            KillSwitch.set(config.flags)
            if MinimumBuild.shouldSuggest(current: current, recommended: recommended, dismissed: dismissed) {
                showsSuggestion = true
            }
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
    var link = MinimumBuild.updateLink(for: AppEnvironment.current)

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
            Text(link.message)
                .font(.ddBody)
                .foregroundStyle(Color.ddInkSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            VStack(spacing: DDSpacing.m) {
                Button(link.title) { openURL(link.url) }
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
