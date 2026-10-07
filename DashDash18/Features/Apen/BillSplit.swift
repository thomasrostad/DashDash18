import Foundation

// «Del regningen» (docs/visjon-apen-app.md, besluttet 07.10.2026 punkt 5): felles utgifter som
// simulatorleie, greenfee, mat og premiepotten deles likt, og hver betaler med Vipps. Aldri
// veddemål eller spill: de gjøres opp i poeng (B10).
//
// Vipps har ingen offentlig lenke som fyller inn beløp og mottaker for en privat betaling
// (dype lenker med beløp krever en bedriftsavtale og lages av Vipps sitt API, og de varer i fem
// minutter). Appen åpner derfor Vipps-appen og viser beløpet og mottakeren, klart til å kopiere.

/// Hva det gjelder. Bare felles utgifter.
nonisolated enum BillPurpose: String, CaseIterable, Identifiable, Sendable {
    case simulator
    case greenfee
    case food
    case prizePot
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .simulator: "Simulatorleie"
        case .greenfee: "Greenfee"
        case .food: "Mat og drikke"
        case .prizePot: "Premiepott"
        case .other: "Annet"
        }
    }
}

/// Beløp i øre, så avrundingen blir eksakt.
nonisolated struct NOK: Comparable, Hashable, Sendable {
    let ore: Int

    static func < (a: NOK, b: NOK) -> Bool { a.ore < b.ore }

    /// Tekst som «1234,5», «1 234,50 kr», «245» eller «245,-». Godtar komma og punktum, og mellomrom
    /// som tusenskille. nil for tomt, negativt, mer enn to desimaler eller over 1 000 000 kr.
    init?(parsing raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for suffix in ["kr", ",-", ".-", "nok"] where text.hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }
        if text.hasPrefix("kr") { text = String(text.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        text = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
        text = text.replacingOccurrences(of: ",", with: ".")
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard !text.isEmpty, parts.count <= 2, let kroner = Int(parts[0].isEmpty ? "0" : String(parts[0])), kroner >= 0
        else { return nil }
        var ore = 0
        if parts.count == 2 {
            let decimals = parts[1]
            guard decimals.count <= 2, decimals.allSatisfy(\.isNumber) else { return nil }
            ore = Int(decimals.padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0
        }
        let total = kroner * 100 + ore
        guard total > 0, total <= 100_000_000 else { return nil }
        self.ore = total
    }

    init(ore: Int) { self.ore = ore }

    /// «1 234,50 kr», eller «245 kr» når det er hele kroner.
    var text: String {
        let kroner = ore / 100
        let rest = ore % 100
        let grouped = Self.grouped(kroner)
        return rest == 0 ? "\(grouped) kr" : "\(grouped),\(String(format: "%02d", rest)) kr"
    }

    /// Til å lime inn i Vipps: «1234,50» (uten tusenskille og «kr»).
    var plain: String {
        let rest = ore % 100
        return rest == 0 ? "\(ore / 100)" : "\(ore / 100),\(String(format: "%02d", rest))"
    }

    private static func grouped(_ value: Int) -> String {
        let digits = Array(String(value))
        var out = ""
        for (i, d) in digits.enumerated() {
            if i > 0, (digits.count - i) % 3 == 0 { out.append("\u{00A0}") }
            out.append(d)
        }
        return out
    }
}

/// Én som skal betale sin del.
nonisolated struct BillShare: Equatable, Identifiable, Sendable {
    let name: String
    let amount: NOK
    var id: String { name }
}

nonisolated enum BillSplit {
    /// Deler likt på alle som er med (også den som la ut). Øre som ikke går opp, fordeles én og én
    /// fra toppen, så summen alltid stemmer. Den som la ut, betaler ikke seg selv: hen er ikke i
    /// lista som kommer tilbake.
    static func shares(total: NOK, people: [String], payer: String?) -> [BillShare] {
        let names = unique(people)
        guard !names.isEmpty else { return [] }
        let base = total.ore / names.count
        let extra = total.ore % names.count
        return names.enumerated().compactMap { index, name in
            guard name != payer else { return nil }
            return BillShare(name: name, amount: NOK(ore: base + (index < extra ? 1 : 0)))
        }
    }

    /// Hva hver betaler (det vanlige beløpet, uten ekstraøre).
    static func perPerson(total: NOK, count: Int) -> NOK? {
        guard count > 0 else { return nil }
        return NOK(ore: (total.ore + count - 1) / count)
    }

    /// Navnene i runden med deg først (du foreslås som den som la ut), resten i rundens rekkefølge.
    static func names(players: [UUID], names: [UUID: String], me: UUID?) -> [String] {
        let mine = players.filter { $0 == me }
        let others = players.filter { $0 != me }
        return unique((mine + others).compactMap { names[$0] })
    }

    /// Navnene uten tomme og uten duplikater (samme navn med andre store/små bokstaver telles én gang).
    static func unique(_ people: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in people {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { continue }
            out.append(name)
        }
        return out
    }
}

/// Mottakeren i Vipps: navn og mobilnummer.
nonisolated enum VippsRecipient {
    /// Norsk mobilnummer med 8 sifre (4xx xx xxx eller 9xx xx xxx), med eller uten +47.
    static func normalizedPhone(_ raw: String) -> String? {
        var digits = raw.filter(\.isNumber)
        if digits.count == 10, digits.hasPrefix("47") { digits = String(digits.dropFirst(2)) }
        if digits.count == 12, digits.hasPrefix("0047") { digits = String(digits.dropFirst(4)) }
        guard digits.count == 8, let first = digits.first, first == "4" || first == "9" else { return nil }
        return digits
    }

    /// «987 65 432».
    static func formatted(_ phone: String) -> String {
        guard phone.count == 8 else { return phone }
        let d = Array(phone)
        return "\(String(d[0..<3])) \(String(d[3..<5])) \(String(d[5..<8]))"
    }
}

nonisolated enum VippsLink {
    /// Åpner Vipps-appen (forsiden). Vipps har ingen offentlig lenke med beløp for privatpersoner.
    static let app = URL(string: "vipps://")!
    /// Vipps i App Store, når appen ikke er installert.
    static let appStore = URL(string: "https://apps.apple.com/no/app/vipps/id984380185")!

    /// Teksten som kopieres og deles: hvem, hva og hvor mye.
    static func requestText(share: BillShare, recipientName: String, phone: String?, purpose: BillPurpose, note: String = "") -> String {
        let what = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? purpose.title : note.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = phone.map { "\(recipientName) (\(VippsRecipient.formatted($0)))" } ?? recipientName
        return "\(share.name): Vipps \(share.amount.text) til \(to) for \(what.lowercased())."
    }

    /// Hele oppgjøret som én melding, til tråden eller Meldinger.
    static func summary(shares: [BillShare], total: NOK, recipientName: String, phone: String?, purpose: BillPurpose, note: String = "") -> String {
        let what = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? purpose.title : note.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = phone.map { "\(recipientName), \(VippsRecipient.formatted($0))" } ?? recipientName
        var lines = ["\(what): \(total.text). Vipps til \(to):"]
        lines += shares.map { "• \($0.name): \($0.amount.text)" }
        return lines.joined(separator: "\n")
    }
}
