import SwiftUI
import WebKit

/// Arket som henter et Turnstile-token før koden sendes (`CaptchaFeature`). Oftest trenger du
/// ikke trykke på noe: arket lukker seg selv etter et sekund eller to. Vil Turnstile at du
/// trykker, vises ruta. Feil vises på norsk med «Prøv igjen».
struct CaptchaSheet: View {
    let siteKey: String
    /// Tokenet, klart for `signInWithOTP`. Arket lukkes av den som viser det.
    let onToken: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var phase: CaptchaPhase = .checking
    /// Nytt forsøk lager nettvisningen på nytt.
    @State private var attempt = 0

    /// Hvor lenge vi venter på Turnstile før vi gir opp (når den ikke venter på et trykk).
    private static let watchdog: Duration = .seconds(30)

    var body: some View {
        VStack(alignment: .leading, spacing: DDSpacing.m) {
            Text("Et øyeblikk")
                .font(.ddTitle)
                .foregroundStyle(Color.ddForestInk)
                .accessibilityAddTraits(.isHeader)
            Text(prompt)
                .font(.ddCallout)
                .foregroundStyle(Color.ddInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            TurnstileWebView(url: TurnstilePage.url(siteKey: siteKey)) { event in
                phase = phase.next(event)
                if case .done(let token) = phase { onToken(token) }
            }
            .id(attempt)
            .frame(height: 72)
            .frame(maxWidth: .infinity)
            .opacity(isFailed ? 0 : 1)
            .accessibilityLabel("Sjekk av innloggingen")
            if case .failed(let error) = phase {
                Label(error.message, systemImage: "exclamationmark.triangle")
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddError)
                Button("Prøv igjen") {
                    phase = .checking
                    attempt += 1
                }
                .buttonStyle(.ddPrimary)
            } else if phase == .checking {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            Button("Avbryt") { dismiss() }
                .buttonStyle(.ddText)
                .frame(maxWidth: .infinity)
        }
        .padding(DDSpacing.xxl)
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
        .task(id: attempt) {
            try? await Task.sleep(for: Self.watchdog)
            if phase == .checking { phase = .failed(.timedOut) }
        }
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    private var prompt: String {
        switch phase {
        case .interactive: "Trykk i ruta under, så sender vi koden."
        default: "Vi sjekker at det er en person som logger inn, før vi sender koden."
        }
    }
}

/// Nettvisningen med `https://dashdash18.com/captcha`. Bare den siden får lastes som hovedside;
/// lenker som åpner nye vinduer (Turnstiles «Personvern» og «Hjelp»), åpnes i Safari.
struct TurnstileWebView: UIViewRepresentable {
    let url: URL
    let onEvent: (TurnstileEvent) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onEvent: onEvent) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Ingen informasjonskapsler eller lagring igjen etter sjekken.
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: TurnstilePage.messageHandler)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onEvent = onEvent
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: TurnstilePage.messageHandler)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        var onEvent: (TurnstileEvent) -> Void

        init(onEvent: @escaping (TurnstileEvent) -> Void) {
            self.onEvent = onEvent
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            // Bare meldinger fra vår egen side, ikke fra rammer eller andre adresser.
            guard message.frameInfo.isMainFrame, TurnstilePage.isPageURL(message.frameInfo.request.url),
                  let event = TurnstileEvent(message: message.body) else { return }
            onEvent(event)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.targetFrame?.isMainFrame ?? false {
                return TurnstilePage.isPageURL(navigationAction.request.url) ? .allow : .cancel
            }
            // Turnstile-rammen (challenges.cloudflare.com) og det den laster selv.
            return navigationAction.request.url?.scheme == "https" || navigationAction.request.url?.scheme == "about"
                ? .allow : .cancel
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
            if navigationResponse.isForMainFrame,
               let http = navigationResponse.response as? HTTPURLResponse, http.statusCode != 200 {
                // F.eks. 404 før workeren er deployet, eller 400 med feil nøkkel.
                onEvent(.loadFailed(.pageUnavailable))
                return .cancel
            }
            return .allow
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            report(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            report(error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            onEvent(.loadFailed(.pageUnavailable))
        }

        /// `target="_blank"`: åpnes i Safari, ikke i arket.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url, url.scheme == "https" {
                UIApplication.shared.open(url)
            }
            return nil
        }

        private func report(_ error: any Error) {
            guard !CaptchaError.isCancellation(error) else { return }
            onEvent(.loadFailed(CaptchaError.from(navigationError: error)))
        }
    }
}

#Preview("Captcha-arket") {
    Color.ddCard
        .sheet(isPresented: .constant(true)) {
            // Cloudflares testnøkkel som alltid godtar.
            CaptchaSheet(siteKey: "1x00000000000000000000AA") { _ in }
        }
}
