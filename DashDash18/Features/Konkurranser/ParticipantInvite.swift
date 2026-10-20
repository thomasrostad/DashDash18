import Foundation

// Deltakerinvitasjonen (sql/060): arrangøren av en klubbturnering limer inn lista over deltakere
// (`add_competition_participants`) og deler turneringens lenke. Den som åpner lenken, velger navnet
// sitt blant de ledige (`claim_competition_invite` med `p_member_id`) eller meldes på som ny deltaker.
// Ren logikk uten nettverk og SwiftUI.

/// «Legg til deltakere»: lista arrangøren limer inn, som i Troppens «Legg til mange», med valgfritt
/// NGF-nummer i egen kolonne. Deltakere kan hete det samme som et medlem (sql/059).
nonisolated enum ParticipantImport {
    /// Høyst så mange om gangen (`add_competition_participants`).
    static let maxLines = 300

    /// Kan du legge inn deltakere? Arrangøren av en klubbturnering med påmelding som ikke er ferdig.
    static func canAdd(_ c: CompetitionRow, access: CompetitionAccess) -> Bool {
        c.clubID != nil && c.entry == .listed && [.league, .cup, .fun].contains(c.kind)
            && c.status != .finished && access.isAdmin(c)
    }

    /// Linjene i lista. `entered`: navnene som er påmeldt fra før (de legges ikke inn på nytt).
    /// Samme navn to ganger i lista er samme person, med mindre NGF-numrene er ulike.
    static func parse(_ text: String, entered: [String]) -> [TroppImportLine] {
        let enteredKeys = Set(entered.map(TroppRules.nameKey))
        var accepted: [(key: String, ngf: String?)] = []
        return text.split(whereSeparator: \.isNewline).prefix(maxLines).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            let columns = TroppImport.columns(line)
            let ngf = columns.ngf.isEmpty ? nil : String(columns.ngf.prefix(20))
            guard let name = ClubInput.normalizedName(columns.name) else {
                return TroppImportLine(text: line, name: columns.name, handicapIndex: nil,
                                       problem: .invalid("Mangler navn, eller navnet er over 40 tegn"))
            }
            let handicap: Double?
            switch ClubInput.handicapIndex(columns.handicap) {
            case .success(let index): handicap = index
            case .failure(let error):
                return TroppImportLine(text: line, name: name, handicapIndex: nil, problem: .invalid(error.message))
            }
            let key = TroppRules.nameKey(name)
            let problem: TroppImportLine.Problem?
            if enteredKeys.contains(key) {
                problem = .exists
            } else if accepted.contains(where: { $0.key == key && ($0.ngf == nil || ngf == nil || $0.ngf == ngf) }) {
                problem = .repeated
            } else {
                problem = nil
                accepted.append((key, ngf))
            }
            return TroppImportLine(text: line, name: name, handicapIndex: handicap, problem: problem, ngfNumber: ngf)
        }
    }

    static func valid(_ lines: [TroppImportLine]) -> [TroppImportLine] {
        lines.filter { $0.problem == nil }
    }

    /// Teksten under navnet: hvorfor linja ikke legges inn.
    static func message(_ line: TroppImportLine) -> String? {
        line.problem == .exists ? "Er påmeldt fra før" : line.message
    }

    /// `p_entries` til `add_competition_participants`: linjene som kan legges inn.
    static func entries(_ lines: [TroppImportLine]) -> [Entry] {
        valid(lines).map { Entry(displayName: $0.name, handicapIndex: $0.handicapIndex, ngfNumber: $0.ngfNumber) }
    }

    /// «12 lagt til». Null: alle var der fra før (samme NGF-nummer i klubben, eller påmeldt).
    static func addedText(_ count: Int) -> String {
        count == 0 ? "Ingen nye. Alle var påmeldt fra før." : "\(count) lagt til"
    }

    /// Én deltaker til `add_competition_participants`.
    struct Entry: Encodable, Equatable, Sendable {
        let displayName: String
        let handicapIndex: Double?
        let ngfNumber: String?

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case handicapIndex = "handicap_index"
            case ngfNumber = "ngf_number"
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(displayName, forKey: .displayName)
            try c.encodeIfPresent(handicapIndex, forKey: .handicapIndex)
            try c.encodeIfPresent(ngfNumber, forKey: .ngfNumber)
        }
    }
}

/// «Er du en av disse?»: søk i de ledige navnene når lista er lang.
nonisolated enum OpenNameSearch {
    /// Fra så mange navn vises søkefeltet.
    static let searchFrom = 12

    static func showsSearch(_ names: [CompetitionInvitePreview.OpenName]) -> Bool {
        names.count >= searchFrom
    }

    /// Navnene som har alle ordene i søket (uten hensyn til store bokstaver og aksenter).
    static func filter(_ names: [CompetitionInvitePreview.OpenName], query: String) -> [CompetitionInvitePreview.OpenName] {
        let words = normalize(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return names }
        return names.filter { name in
            let text = normalize(name.displayName)
            return words.allSatisfy { text.contains($0) }
        }
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "nb_NO"))
    }
}
