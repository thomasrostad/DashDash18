import Foundation

/// Invitasjonen til en klubb: koden (`clubs.join_code`) og lenken `dashdash://klubb/<KODE>`, etter
/// samme mønster som løse runder (`dashdash://runde/…`) og konkurranser (`dashdash://konkurranse/…`).
///
/// Koden tolkes som `JoinClubView` alltid har gjort (`ClubInput.normalizedJoinCode`): store bokstaver,
/// uten mellomrom og bindestrek, 6–16 bokstaver og tall. Eldre klubber har 10 tegn, nye 12 (sql/024).
nonisolated struct ClubInvite: Equatable, Hashable, Sendable {
    let code: String

    /// `dashdash://klubb/<KODE>`.
    static let host = "klubb"

    /// En kode som skrevet inn, eller nil når den ikke kan være en klubbkode.
    init?(code raw: String) {
        guard let code = ClubInput.normalizedJoinCode(raw) else { return nil }
        self.code = code
    }

    /// Koden fra en lenke: `dashdash://klubb/KODE` (også `dashdash://klubb?kode=KODE`) eller den
    /// universelle `https://dashdash18.com/klubb/KODE`.
    init?(url: URL) {
        let url = UniversalLink.appURL(url) ?? url
        guard url.scheme?.lowercased() == InviteCode.scheme, url.host()?.lowercased() == Self.host else { return nil }
        let fromPath = url.pathComponents.first { $0 != "/" }
        let fromQuery = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "kode" }?.value
        guard let raw = fromPath ?? fromQuery, let invite = ClubInvite(code: raw) else { return nil }
        self = invite
    }

    /// Det som limes inn eller skrives: lenken, koden, eller hele meldingen med lenken i
    /// («Bli med i X i Atten: dashdash://klubb/KODE · Koden er KODE»). Eldre meldinger
    /// («… Invitasjonskode: KODE») går også.
    static func parse(_ text: String) -> ClubInvite? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = trimmed.firstMatch(of: /(?i)dashdash:\/\/klubb[A-Za-z0-9\/?=&-]*/),
           let url = URL(string: String(match.output)) {
            return ClubInvite(url: url)
        }
        if let match = trimmed.firstMatch(of: /(?i)https:\/\/(?:www\.)?dashdash18\.com\/klubb\/[A-Za-z0-9-]+/),
           let url = URL(string: String(match.output)) {
            return ClubInvite(url: url)
        }
        if let invite = ClubInvite(code: trimmed) { return invite }
        // Bare koden etter et kjent stikkord: et vanlig ord som «Invitational» er også 6–16 bokstaver.
        if let match = trimmed.firstMatch(of: /(?i)(?:invitasjonskode:|koden er)\s*([A-Za-z0-9-]+)/) {
            return ClubInvite(code: String(match.output.1))
        }
        return nil
    }

    var url: URL { URL(string: "\(InviteCode.scheme)://\(Self.host)/\(code)")! }

    /// Lenken som deles: `https://dashdash18.com/klubb/KODE` med universelle lenker, ellers `url`.
    func shareURL(universal: Bool = UniversalLinksFeature.isEnabled) -> URL {
        universal ? UniversalLink.url(path: Self.host, code: code) : url
    }

    /// Teksten som deles: hva det er og lenken. Med https-lenken (universelle lenker) står koden i
    /// lenken og kan leses av der; med `dashdash://` står den også for seg, siden den lenken ikke kan
    /// trykkes overalt (09.10.2026: kortere tekst).
    func shareText(clubName: String, universal: Bool = UniversalLinksFeature.isEnabled) -> String {
        let link = shareURL(universal: universal).absoluteString
        return universal ? "Bli med i \(clubName) i Atten: \(link)"
                         : "Bli med i \(clubName) i Atten: \(link) · Koden er \(code)"
    }

    /// Hvor man får koden, til den som står uten.
    static let whereToGetIt = "Spør arrangøren om en invitasjon. Den ser ut som en lenke eller en kode på 10–12 tegn."

    /// Når det som er limt inn eller skrevet, ikke er en invitasjon.
    static let notAnInvite = "Fant ingen invitasjon. Lim inn lenken, eller skriv koden (10–12 bokstaver og tall)."

    // MARK: Arrangøren

    /// Hjem viser «Inviter spillere» til arrangøren så lenge troppen har færre aktive enn dette.
    /// Fire er én full ball (bås) i golf: med færre er det ikke en gjeng ennå, selv om en runde
    /// kan startes med to (`GettingStarted.minimumRoster`). Over det er kortet bare støy, og
    /// invitasjonen står uansett øverst på arrangørsiden og i Troppen.
    static let homeCardRosterLimit = 4

    static func showsHomeCard(isOrganizer: Bool, activeMembers: Int?, hasCode: Bool) -> Bool {
        guard isOrganizer, hasCode, let activeMembers else { return false }
        return activeMembers < homeCardRosterLimit
    }

    /// Underteksten på «Inviter spillere».
    static func organizerSubtitle(activeMembers: Int?) -> String {
        switch activeMembers {
        case nil: "Send lenken til gjengen. De som har appen, kommer rett inn."
        case 0, 1: "Bare deg i troppen så langt. Send lenken til gjengen."
        case let n?: "\(n) i troppen. Send lenken til resten av gjengen."
        }
    }
}

/// Hva som skjer med en klubbinvitasjon fra en lenke, etter hvor brukeren står.
nonisolated enum ClubInviteFlow {
    enum Step: Equatable, Sendable {
        /// Ikke innlogget: koden huskes til innloggingen er ferdig.
        case waitForSignIn
        /// Klubbene hentes (eller hentingen feilet): vent, så ingen blir spurt to ganger.
        case waitForClubs
        /// Uten klubb: rett til «Bli med» med koden fylt inn.
        case join
        /// Med i andre klubber: spør «Bli med i X?» først, bytt til klubben etterpå.
        case confirmJoin
        /// Allerede med (aktiv eller venter): si fra, og bytt til klubben om den er aktiv.
        case alreadyMember(Membership)
    }

    static func step(isSignedIn: Bool, club: ClubState, memberships: [Membership], invite: ClubInvite) -> Step {
        guard isSignedIn else { return .waitForSignIn }
        switch club {
        case .loading, .failed: return .waitForClubs
        case .noClub, .pending, .active: break
        }
        if let mine = memberships.first(where: {
            $0.status != .archived && $0.club.joinCode.flatMap(ClubInput.normalizedJoinCode) == invite.code
        }) {
            return .alreadyMember(mine)
        }
        // Arkivert er ikke med: «Bli med» viser at arrangøren må gjenopprette deg.
        let isInAClub = memberships.contains { $0.status != .archived }
        return isInAClub ? .confirmJoin : .join
    }

    /// Teksten når du allerede er med.
    static func alreadyMemberText(_ membership: Membership) -> String {
        switch membership.status {
        case .pending: "Du har bedt om å bli med i \(membership.club.name). Arrangøren må godkjenne deg."
        case .active, .archived: "Du er allerede med i \(membership.club.name)."
        }
    }

    /// Teksten etter at du har blitt med fra en lenke mens du var med i en annen klubb.
    static func joinedText(clubName: String, status: MemberStatus) -> String {
        switch status {
        case .active: "Du er med i \(clubName)."
        case .pending, .archived: "Du har bedt om å bli med i \(clubName). Arrangøren må godkjenne deg før klubben dukker opp."
        }
    }
}

/// Koden fra en lenke, lagret på telefonen til innloggingen er ferdig (også om appen lukkes
/// mens du henter e-postkoden). Gammel kode glemmes etter en dag.
nonisolated struct PendingClubInviteStore {
    var defaults: UserDefaults = .standard
    static let key = "klubbinvitasjon"
    static let maxAge: TimeInterval = 24 * 3600

    private struct Saved: Codable {
        let code: String
        let savedAt: Date
    }

    func save(_ invite: ClubInvite, now: Date = .now) {
        guard let data = try? JSONEncoder().encode(Saved(code: invite.code, savedAt: now)) else { return }
        defaults.set(data, forKey: Self.key)
    }

    func load(now: Date = .now) -> ClubInvite? {
        guard let data = defaults.data(forKey: Self.key),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return nil }
        guard now.timeIntervalSince(saved.savedAt) < Self.maxAge else {
            clear()
            return nil
        }
        return ClubInvite(code: saved.code)
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
