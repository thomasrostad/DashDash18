import Foundation

/// CAPTCHA (Cloudflare Turnstile) ved innlogging med e-postkode (1.0.1). På bare når appkonfigen
/// har en site key (`TurnstileSiteKey` i `Supabase-<Miljø>.plist`, se `AppConfig`).
///
/// Supabase Auth krever `captchaToken` på `/otp` (sende koden) når CAPTCHA er slått på, men ikke på
/// `/verify` (skrive inn koden) eller `/token` med `id_token` (Apple), `refresh_token` og `pkce`.
/// Derfor sendes tokenet bare med `signInWithOTP`.
nonisolated enum CaptchaFeature {
    static func isEnabled(siteKey: String?) -> Bool { siteKey != nil }

    /// Slik Cloudflare lager site key-er (`0x4AAAAAAA…`), og testnøklene (`1x0000…AA`).
    /// Samme regel som `normalizeSiteKey` i `web/atten-lenker/src/captcha.ts`.
    static func isValidSiteKey(_ key: String) -> Bool {
        key.wholeMatch(of: /[0-9A-Za-z_-]{20,100}/) != nil
    }
}

/// Siden med Turnstile-widgeten, servert av workeren `web/atten-lenker` (`/captcha`).
nonisolated enum TurnstilePage {
    static let host = "dashdash18.com"
    static let path = "/captcha"
    /// Navnet siden sender meldingene til (`window.webkit.messageHandlers.atten`).
    static let messageHandler = "atten"

    static func url(siteKey: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = [URLQueryItem(name: "sitekey", value: siteKey)]
        return components.url!
    }

    /// Bare selve siden får lastes som hovedside i nettvisningen.
    static func isPageURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme == "https" && url.host() == host && (url.path() == path || url.path() == path + "/")
    }
}

/// Det siden melder fra Turnstile, eller at siden ikke lot seg laste.
nonisolated enum TurnstileEvent: Equatable {
    case token(String)
    /// Turnstile vil at du trykker i ruta.
    case interactive
    /// Tokenet ble for gammelt før det ble brukt. Turnstile henter et nytt selv.
    case expired
    /// Du trykket ikke i ruta i tide.
    case timeout
    /// Feilkoden fra Turnstile (f.eks. `110200`), eller `load`/`render` fra siden.
    case error(String)
    /// Siden kom ikke fram (nett, 404, krasj i nettvisningen).
    case loadFailed(CaptchaError)

    /// Meldingen fra `postMessage`, f.eks. `{ type: "token", token: "…" }`.
    init?(message body: Any) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return nil }
        switch type {
        case "token":
            guard let token = dict["token"] as? String, !token.isEmpty else { return nil }
            self = .token(token)
        case "interactive": self = .interactive
        case "expired": self = .expired
        case "timeout": self = .timeout
        case "error": self = .error((dict["code"] as? String) ?? "")
        default: return nil
        }
    }
}

/// Hvor sjekken står.
nonisolated enum CaptchaPhase: Equatable {
    case checking
    case interactive
    case failed(CaptchaError)
    case done(token: String)

    /// Neste steg etter en melding fra siden. Et ferdig token endres ikke.
    func next(_ event: TurnstileEvent) -> CaptchaPhase {
        if case .done = self { return self }
        switch event {
        case .token(let token): return .done(token: token)
        case .interactive: return .interactive
        case .expired: return .checking
        case .timeout: return .failed(.timedOut)
        case .error(let code): return .failed(CaptchaError.from(turnstileCode: code))
        case .loadFailed(let error): return .failed(error)
        }
    }
}

/// Det brukeren får se når sjekken ikke går. Alle har «Prøv igjen» i arket.
nonisolated enum CaptchaError: Error, Equatable {
    case offline
    case pageUnavailable
    /// Feil site key eller domene i Cloudflare. Hjelper ikke å prøve igjen før det er rettet.
    case misconfigured
    case failed
    case timedOut

    var message: String {
        switch self {
        case .offline: "Ingen kontakt med nettet. Sjekk nettet og prøv igjen."
        case .pageUnavailable: "Sjekken kunne ikke lastes. Vent litt og prøv igjen."
        case .misconfigured: "Sjekken virker ikke akkurat nå. Prøv igjen senere, eller logg inn med Apple."
        case .failed: "Vi fikk ikke bekreftet at du er et menneske. Prøv igjen."
        case .timedOut: "Sjekken tok for lang tid. Prøv igjen."
        }
    }

    /// Feilkodene til Turnstile: 110xxx og 400xxx er oppsettet (nøkkel, domene), 200500 er at
    /// rammen ikke lastet, `load` er at skriptet ikke kom fram. Resten er at sjekken ikke gikk.
    static func from(turnstileCode code: String) -> CaptchaError {
        if code == "load" || code == "200500" { return .pageUnavailable }
        if code.hasPrefix("110") || code.hasPrefix("400") { return .misconfigured }
        return .failed
    }

    /// Feil fra nettvisningen mens siden lastes.
    static func from(navigationError error: any Error) -> CaptchaError {
        let ns = error as NSError
        guard ns.domain == NSURLErrorDomain else { return .pageUnavailable }
        switch ns.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut,
             NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed,
             NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff:
            return .offline
        default:
            return .pageUnavailable
        }
    }

    /// Avbrutt av oss selv (ny lasting, stoppet av `decidePolicyFor`): ingen feil å vise.
    static func isCancellation(_ error: any Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled { return true }
        // WebKitErrorFrameLoadInterruptedByPolicyChange
        return ns.domain == "WebKitErrorDomain" && ns.code == 102
    }
}
