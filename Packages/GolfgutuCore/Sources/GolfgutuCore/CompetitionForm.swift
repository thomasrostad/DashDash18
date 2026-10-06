import Foundation

/// En konkurranseform (`KONKURRANSEFORMER` i db-nytt.js).
public struct CompetitionForm: Codable, Hashable, Sendable, Identifiable {
    /// Hvordan scorekortet føres.
    public enum Card: String, Codable, Sendable {
        /// Hver mann har egen ball og eget hulltall («per spiller»).
        case perPlayer = "per spiller"
        /// Laget spiller én ball («per lag»).
        case perTeam = "per lag"
    }

    /// Hvor ferdig appen er med formen.
    public enum Support: String, Codable, Sendable {
        case full
        case partial = "delvis"
        case missing = "mangler"
    }

    public let id: String
    public let name: String
    /// Spillere per lag. 1 = individuell.
    public let teamSize: Int
    public let card: Card
    /// Hvordan runden regnes (`regning`), f.eks. `stableford`, `beste-netto`.
    public let scoring: String
    /// Anbefalt handicaptildeling (`hcpAndel`). `nil` der laget har ett handicap.
    public let allowance: Double?
    public let support: Support
    /// Tåler formen et lag med én mann mer (`taalerSkjevtLag`)?
    public let allowsUnevenTeams: Bool
    /// Hjelpeteksten (`hjelp`).
    public let help: String

    public init(id: String, name: String, teamSize: Int, card: Card, scoring: String, allowance: Double?,
                support: Support, allowsUnevenTeams: Bool = false, help: String) {
        self.id = id
        self.name = name
        self.teamSize = teamSize
        self.card = card
        self.scoring = scoring
        self.allowance = allowance
        self.support = support
        self.allowsUnevenTeams = allowsUnevenTeams
        self.help = help
    }
}

extension CompetitionForm {
    /// `FORM_STANDARD`.
    public static let defaultID = "stableford"

    /// `KONKURRANSEFORMER`, i samme rekkefølge og med samme tekster som db-nytt.js.
    public static let all: [CompetitionForm] = [
        CompetitionForm(id: "stableford", name: "Stableford (netto)", teamSize: 1, card: .perPlayer,
                        scoring: "stableford", allowance: 0.95, support: .full,
                        help: "Poeng per hull mot netto par. Standarden vår."),
        CompetitionForm(id: "stableford-brutto", name: "Stableford (brutto)", teamSize: 1, card: .perPlayer,
                        scoring: "stableford-brutto", allowance: 0, support: .partial,
                        help: "Som over, men uten handicap. Fordel for de laveste."),
        CompetitionForm(id: "slag-netto", name: "Slagspill (netto)", teamSize: 1, card: .perPlayer,
                        scoring: "slag-netto", allowance: 0.95, support: .partial,
                        help: "Sum slag minus handicap. Lavest vinner."),
        CompetitionForm(id: "slag-brutto", name: "Slagspill (brutto)", teamSize: 1, card: .perPlayer,
                        scoring: "slag-brutto", allowance: 0, support: .partial,
                        help: "Rene slag. Klubbmesterskapets form."),
        CompetitionForm(id: "par-bogey", name: "Par/bogey", teamSize: 1, card: .perPlayer,
                        scoring: "par-bogey", allowance: 0.95, support: .partial,
                        help: "Pluss, deling eller minus mot netto par på hvert hull."),
        CompetitionForm(id: "maks-score", name: "Maksimumscore", teamSize: 1, card: .perPlayer,
                        scoring: "maks-score", allowance: 0.95, support: .partial,
                        help: "Som slagspill, men med tak per hull. Holder tempoet oppe."),
        CompetitionForm(id: "match", name: "Matchspill (individuelt)", teamSize: 1, card: .perPlayer,
                        scoring: "match", allowance: 1.00, support: .full,
                        help: "Hull mot hull, én mot én. Krever oppsett av par."),
        CompetitionForm(id: "fourball", name: "Fourball (beste ball)", teamSize: 2, card: .perPlayer,
                        scoring: "beste-netto", allowance: nil, support: .full, allowsUnevenTeams: true,
                        help: "Begge spiller egen ball, beste netto per hull teller for laget. Laget har ett handicap: summen delt på to."),
        CompetitionForm(id: "fourball-4", name: "Beste ball (4-mann)", teamSize: 4, card: .perPlayer,
                        scoring: "beste-netto", allowance: 0.75, support: .full, allowsUnevenTeams: true,
                        help: "Som fourball, men fire på laget."),
        CompetitionForm(id: "sammenlagt-lag", name: "Sammenlagt lag", teamSize: 2, card: .perPlayer,
                        scoring: "sum-netto", allowance: nil, support: .full, allowsUnevenTeams: false,
                        help: "Begge sine runder legges sammen. Laget har ett handicap: summen delt på to."),
        CompetitionForm(id: "foursome", name: "Foursome", teamSize: 2, card: .perTeam,
                        scoring: "stableford", allowance: 0.50, support: .full, allowsUnevenTeams: false,
                        help: "Én ball, annenhvert slag. Laghandicap: summen delt på to."),
        CompetitionForm(id: "greensome", name: "Greensome", teamSize: 2, card: .perTeam,
                        scoring: "stableford", allowance: nil, support: .full, allowsUnevenTeams: false,
                        help: "Begge slår ut, dere velger én ball, så annenhvert slag. Laghandicap: summen delt på to."),
        CompetitionForm(id: "chapman", name: "Chapman / Pinehurst", teamSize: 2, card: .perTeam,
                        scoring: "stableford", allowance: nil, support: .full, allowsUnevenTeams: false,
                        help: "Begge slår ut, bytt ball til andreslaget, velg én, så annenhvert slag. Laghandicap: summen delt på to."),
        CompetitionForm(id: "scramble-2", name: "Scramble (2-mann)", teamSize: 2, card: .perTeam,
                        scoring: "stableford", allowance: nil, support: .full, allowsUnevenTeams: true,
                        help: "Alle slår, dere spiller videre fra den beste ballen. Laghandicap: summen delt på to."),
        CompetitionForm(id: "scramble-4", name: "Scramble (4-mann)", teamSize: 4, card: .perTeam,
                        scoring: "stableford", allowance: nil, support: .full, allowsUnevenTeams: true,
                        help: "Fire på laget. Tildeling 25/20/15/10 % av banehandicapene."),
        CompetitionForm(id: "skins", name: "Skins", teamSize: 1, card: .perPlayer,
                        scoring: "skins", allowance: 0.95, support: .missing,
                        help: "Hvert hull er en pott. Deling gjør at potten vokser til neste."),
    ]

    /// `konkurranseform`: formen med denne id-en, ellers standardformen.
    public static func form(id: String?) -> CompetitionForm {
        all.first { $0.id == id } ?? all.first { $0.id == defaultID }!
    }
}

extension Round {
    /// `formForRunde`: formen fra `gameType`, uten hensyn til store bokstaver. Ukjent eller tom → stableford.
    public var form: CompetitionForm {
        CompetitionForm.form(id: (gameType ?? "").lowercased())
    }
}
