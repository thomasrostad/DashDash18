import Foundation

/// En i klubben, slik tråden trenger dem: id og navn.
nonisolated struct TradPerson: Equatable, Sendable, Identifiable {
    let id: UUID
    let name: String
}

/// @navn i tråden (PWA: `fornavnAv`, `nevneNavn`, `finnNevnte`, `nevnForslagHtml`, `settInnNevn`).
///
/// Du nevner noen med fornavnet. Deler to fornavnet, får begge første bokstav i etternavnet
/// bak («ThomasR»). E-postadresser nevner ingen, og avsenderen nevner ikke seg selv.
nonisolated struct MentionDirectory: Sendable {
    /// Et forslag mens du skriver @.
    struct Suggestion: Equatable, Sendable, Identifiable {
        let id: UUID
        let handle: String
        let name: String
    }

    /// I klubbens rekkefølge. Nevnte returneres i samme rekkefølge.
    let people: [TradPerson]
    private let handles: [UUID: String]

    /// Så mange forslag vises om gangen (som PWA-en).
    static let suggestionLimit = 6

    init(people: [TradPerson]) {
        self.people = people
        let firstNames = people.map { (id: $0.id, first: Self.firstName(of: $0.name)) }
        var handles: [UUID: String] = [:]
        for person in people {
            let first = Self.firstName(of: person.name)
            guard !first.isEmpty else { continue }
            let shared = firstNames.contains { $0.id != person.id && $0.first.lowercased() == first.lowercased() }
            let parts = Self.words(person.name)
            if !shared || parts.count < 2 {
                handles[person.id] = first
            } else {
                let last = Self.lettersOnly(parts[parts.count - 1], keepHyphen: false)
                handles[person.id] = first + (last.first.map { String($0).uppercased() } ?? "")
            }
        }
        self.handles = handles
    }

    /// Navnet personen nevnes med, eller nil når navnet ikke har bokstaver.
    func handle(for id: UUID) -> String? { handles[id] }

    /// De teksten nevner, uten avsenderen. Store og små bokstaver er likegyldige, og
    /// @navn midt i et ord (thomas@fink.no) nevner ingen.
    func mentions(in text: String, sender: UUID?) -> [UUID] {
        guard text.contains("@") else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return people.compactMap { person in
            guard person.id != sender, let handle = handles[person.id],
                  let pattern = Self.mentionPattern(handle),
                  pattern.firstMatch(in: text, range: range) != nil else { return nil }
            return person.id
        }
    }

    /// Navnene som passer når utkastet slutter på @ og noen bokstaver. Deg selv er ikke med.
    func suggestions(for draft: String, viewer: UUID) -> [Suggestion] {
        guard let typed = Self.trailingMention(in: draft) else { return [] }
        let start = typed.lowercased()
        return people.compactMap { person -> Suggestion? in
            guard person.id != viewer, let handle = handles[person.id],
                  handle.lowercased().hasPrefix(start) else { return nil }
            return Suggestion(id: person.id, handle: handle, name: person.name)
        }
        .prefix(Self.suggestionLimit)
        .map { $0 }
    }

    /// Bytter @-en på slutten av utkastet med det valgte navnet og et mellomrom.
    static func inserting(_ handle: String, into draft: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "@([\\p{L}-]*)$") else { return draft }
        let range = NSRange(draft.startIndex..., in: draft)
        guard let match = regex.firstMatch(in: draft, range: range),
              let found = Range(match.range, in: draft) else { return draft }
        return draft.replacingCharacters(in: found, with: "@" + handle + " ")
    }

    /// Bitene av teksten, med @navn for de nevnte merket. For uthevingen i boblene.
    func segments(of text: String, mentions: [UUID]) -> [(text: String, mention: UUID?)] {
        var marks: [(range: Range<String.Index>, id: UUID)] = []
        let all = NSRange(text.startIndex..., in: text)
        for id in mentions {
            guard let handle = handles[id], let pattern = Self.mentionPattern(handle) else { continue }
            for match in pattern.matches(in: text, range: all) {
                // Gruppe 1 er tegnet foran @ (eller ingenting); selve nevnet starter etter den.
                let lead = match.range(at: 1).length
                let ns = NSRange(location: match.range.location + lead, length: match.range.length - lead)
                if let r = Range(ns, in: text) { marks.append((r, id)) }
            }
        }
        marks.sort { $0.range.lowerBound < $1.range.lowerBound }
        var result: [(text: String, mention: UUID?)] = []
        var cursor = text.startIndex
        for mark in marks where mark.range.lowerBound >= cursor {
            if cursor < mark.range.lowerBound { result.append((String(text[cursor..<mark.range.lowerBound]), nil)) }
            result.append((String(text[mark.range]), mark.id))
            cursor = mark.range.upperBound
        }
        if cursor < text.endIndex { result.append((String(text[cursor...]), nil)) }
        return result
    }

    // MARK: Hjelpere

    /// `fornavnAv`: første ord, uten tegn som ikke er bokstaver eller bindestrek.
    static func firstName(of name: String) -> String {
        lettersOnly(words(name).first ?? "", keepHyphen: true)
    }

    private static func words(_ name: String) -> [String] {
        name.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
    }

    /// `\p{L}` (og `-`) per kodepunkt, som PWA-ens regex med u-flagg.
    private static func lettersOnly(_ word: String, keepHyphen: Bool) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in word.unicodeScalars where isLetter(scalar) || (keepHyphen && scalar == "-") {
            scalars.append(scalar)
        }
        return String(scalars)
    }

    private static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: true
        default: false
        }
    }

    /// `nevnMonster`: ikke midt i et ord. `0-9` som JavaScripts `\d`.
    private static func mentionPattern(_ handle: String) -> NSRegularExpression? {
        let escaped = NSRegularExpression.escapedPattern(for: handle)
        return try? NSRegularExpression(pattern: "(^|[^\\p{L}0-9])@" + escaped + "(?![\\p{L}0-9])",
                                        options: [.caseInsensitive])
    }

    /// Det som står etter en @ på slutten av utkastet (`(^|\s)@([\p{L}-]*)$`), eller nil.
    private static func trailingMention(in draft: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "(^|\\s)@([\\p{L}-]*)$") else { return nil }
        let range = NSRange(draft.startIndex..., in: draft)
        guard let match = regex.firstMatch(in: draft, range: range),
              let typed = Range(match.range(at: 2), in: draft) else { return nil }
        return String(draft[typed])
    }
}
