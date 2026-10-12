import Foundation

// «Del regningen» lagret (steg 10, sql/051): regningen og delene, status per del, hvem som kan gjøre
// hva, og at delen merkes sendt når du kommer tilbake fra Vipps. Rene typer, så de kan testes isolert.
// Nettverket ligger i `BillService`, skjermene i `BillSplitView` og `BillSettlementsView`.

/// En som er med på regningen: navnet, og profilen når hen har innlogging.
nonisolated struct BillPerson: Equatable, Sendable {
    let name: String
    let profileID: UUID?
}

/// Regningen fordelt: mottakerens egen del (0 når hen ikke deler) og de andres. Summen er alltid
/// hele beløpet (nullsum, som `bill_split_create` krever).
nonisolated struct BillPlan: Equatable, Sendable {
    let payeeShare: NOK
    let shares: [BillShare]

    var sum: Int { payeeShare.ore + shares.reduce(0) { $0 + $1.amount.ore } }
}

nonisolated extension BillSplit {
    /// Lik deling på alle som er med, også den som la ut (samme fordeling som `shares`). Mottakerens
    /// del står for seg, de andre i lista. Mottakeren trenger ikke være med på delingen.
    static func plan(total: NOK, people: [String], payer: String?) -> BillPlan {
        let names = unique(people)
        guard !names.isEmpty else { return BillPlan(payeeShare: NOK(ore: 0), shares: []) }
        let base = total.ore / names.count
        let extra = total.ore % names.count
        var payeeShare = 0
        var shares: [BillShare] = []
        for (index, name) in names.enumerated() {
            let amount = base + (index < extra ? 1 : 0)
            if name == payer { payeeShare = amount } else { shares.append(BillShare(name: name, amount: NOK(ore: amount))) }
        }
        return BillPlan(payeeShare: NOK(ore: payeeShare), shares: shares)
    }

    /// Tittelen på regningen: det som ble skrevet for «Annet», ellers formålet. Høyst 60 tegn.
    static func title(purpose: BillPurpose, note: String) -> String {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = purpose == .other && !trimmed.isEmpty ? trimmed : purpose.title
        return String(text.prefix(60))
    }

    /// Navnet slik serveren tar det: 1–40 tegn.
    static func storedName(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
    }
}

// MARK: - Status

/// `bill_split_shares.status` (generert i 051).
nonisolated enum BillShareStatus: String, Sendable, CaseIterable {
    /// Ikke betalt ennå.
    case open
    /// Merket sendt etter Vipps.
    case sent
    /// Mottakeren fikk den.
    case confirmed
    /// Mottakeren sier at den ikke kom.
    case disputed

    /// Ukjent eller manglende verdi (en nyere server) leses som `open`.
    init(raw: String?) {
        self = raw.flatMap(Self.init(rawValue:)) ?? .open
    }

    /// For mottakeren: hvor delen står.
    var payeeText: String {
        switch self {
        case .open: "Ikke betalt"
        case .sent: "Sendt. Sjekk Vipps"
        case .confirmed: "Fikk den"
        case .disputed: "Kom ikke"
        }
    }

    /// For den som skal betale.
    func debtorText(payee: String) -> String {
        switch self {
        case .open: "Ikke betalt"
        case .sent: "Sendt. Venter på \(payee)"
        case .confirmed: "Betalt"
        case .disputed: "\(payee) sier den ikke kom"
        }
    }

    /// Den som skal betale, kan (betale på nytt) med Vipps.
    var canPay: Bool { self == .open || self == .disputed }
    /// Mottakeren kan si «Fikk den» (også kontant, uten «sendt»).
    var canConfirm: Bool { self != .confirmed }
    /// Mottakeren kan si «Kom ikke» bare når delen er merket sendt.
    var canDispute: Bool { self == .sent }
}

// MARK: - Rader

/// En rad i `bill_splits`.
nonisolated struct BillSplitRow: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let clubID: UUID?
    let roundID: UUID?
    let createdBy: UUID?
    let payeeProfileID: UUID?
    let payeeName: String
    let payeeVipps: String?
    let title: String
    let totalOre: Int
    let createdAt: Date

    static let columns = "id, club_id, round_id, created_by, payee_profile_id, payee_name, payee_vipps, title, total_ore, created_at"

    enum CodingKeys: String, CodingKey {
        case id
        case clubID = "club_id"
        case roundID = "round_id"
        case createdBy = "created_by"
        case payeeProfileID = "payee_profile_id"
        case payeeName = "payee_name"
        case payeeVipps = "payee_vipps"
        case title
        case totalOre = "total_ore"
        case createdAt = "created_at"
    }
}

/// En rad i `bill_split_shares`.
nonisolated struct BillShareRow: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let splitID: UUID
    let profileID: UUID?
    let name: String
    let amountOre: Int
    let isPayee: Bool
    let statusRaw: String?
    let createdAt: Date?

    var status: BillShareStatus { BillShareStatus(raw: statusRaw) }
    var amount: NOK { NOK(ore: amountOre) }

    static let columns = "id, split_id, profile_id, name, amount_ore, is_payee, status, created_at"

    enum CodingKeys: String, CodingKey {
        case id
        case splitID = "split_id"
        case profileID = "profile_id"
        case name
        case amountOre = "amount_ore"
        case isPayee = "is_payee"
        case statusRaw = "status"
        case createdAt = "created_at"
    }
}

/// En regning med delene, sett fra den innloggede.
nonisolated struct BillSettlement: Equatable, Identifiable, Sendable {
    let split: BillSplitRow
    /// Alle delene, også mottakerens egen.
    let shares: [BillShareRow]

    var id: UUID { split.id }

    /// Delene som skal betales (uten mottakerens egen), i rekkefølgen de ble laget.
    var owed: [BillShareRow] { shares.filter { !$0.isPayee } }

    /// Du får pengene: mottakeren, eller den som laget regningen når mottakeren ikke har innlogging.
    func isPayee(_ me: UUID) -> Bool {
        split.payeeProfileID == me || (split.payeeProfileID == nil && split.createdBy == me)
    }

    /// Din del, når du skal betale.
    func myShare(_ me: UUID) -> BillShareRow? {
        owed.first { $0.profileID == me }
    }

    /// Bare den som laget den, og bare før noen del (utenom mottakerens) er bekreftet.
    func canDelete(_ me: UUID) -> Bool {
        split.createdBy == me && !owed.contains { $0.status == .confirmed }
    }

    /// Alle har betalt (mottakeren har bekreftet hver del).
    var isSettled: Bool { owed.allSatisfy { $0.status == .confirmed } }

    /// «2 av 3 betalt».
    var progressText: String {
        "\(owed.filter { $0.status == .confirmed }.count) av \(owed.count) betalt"
    }

    /// Regningene med delene sine, nyeste først.
    static func group(splits: [BillSplitRow], shares: [BillShareRow]) -> [BillSettlement] {
        let bySplit = Dictionary(grouping: shares, by: \.splitID)
        return splits.sorted { $0.createdAt > $1.createdAt }.map { split in
            let mine = (bySplit[split.id] ?? []).sorted { a, b in
                if a.isPayee != b.isPayee { return a.isPayee }
                return (a.createdAt ?? .distantPast) < (b.createdAt ?? .distantPast)
            }
            return BillSettlement(split: split, shares: mine)
        }
    }
}

// MARK: - Tilbake fra Vipps

/// Hvor appen er: aktiv, inaktiv (et øyeblikk, for eksempel under en systemdialog) eller i bakgrunnen.
nonisolated enum AppPhase: Sendable {
    case active
    case inactive
    case background
}

/// Delen merkes sendt når du kommer tilbake fra Vipps: «Betal med Vipps» for en del, appen går i
/// bakgrunnen (Vipps åpnes), og når den blir aktiv igjen, er delen klar til `bill_share_mark_sent`.
/// Et kort «inaktiv» uten bakgrunn (en dialog) teller ikke som at du var i Vipps.
nonisolated struct VippsReturnTracker: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case idle
        /// Vipps er bedt åpnet for delen; appen har ikke gått i bakgrunnen ennå.
        case opening(UUID)
        /// Appen gikk i bakgrunnen mens Vipps åpnet.
        case away(UUID)
    }

    private(set) var state: State = .idle

    /// «Betal med Vipps» for delen.
    mutating func opened(share: UUID) {
        state = .opening(share)
    }

    /// Vipps (og reservene) kunne ikke åpnes.
    mutating func openFailed() {
        state = .idle
    }

    /// Ny fase. Gir delen som skal merkes sendt når du kommer tilbake fra Vipps, ellers nil.
    mutating func phaseChanged(to phase: AppPhase) -> UUID? {
        switch (state, phase) {
        case let (.opening(share), .background):
            state = .away(share)
            return nil
        case let (.away(share), .active):
            state = .idle
            return share
        default:
            return nil
        }
    }
}

// MARK: - Kalender

/// Lenken til kalenderabonnementet (sql/051 og Workeren): `webcal://dashdash18.com/kalender/<token>.ics`.
nonisolated enum CalendarLink {
    static let host = "dashdash18.com"

    /// Tokenet er 32 tegn base32 (a–z, 2–7). Alt annet gir nil.
    static func isValidToken(_ token: String) -> Bool {
        token.count == 32 && token.allSatisfy { ("a"..."z").contains($0) || ("2"..."7").contains($0) }
    }

    /// Åpner Kalender-appen med «Abonner».
    static func subscribeURL(token: String) -> URL? {
        url(scheme: "webcal", token: token)
    }

    /// Til å kopiere: virker i Google Kalender, Outlook og nettleseren.
    static func webURL(token: String) -> URL? {
        url(scheme: "https", token: token)
    }

    private static func url(scheme: String, token: String) -> URL? {
        guard isValidToken(token) else { return nil }
        return URL(string: "\(scheme)://\(host)/kalender/\(token).ics")
    }
}
