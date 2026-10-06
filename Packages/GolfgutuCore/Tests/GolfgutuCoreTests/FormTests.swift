import Foundation
import Testing
@testable import GolfgutuCore

/// Konkurranseformer. Tall og tekster: Fixtures/former.json (KONKURRANSEFORMER dumpet fra db-nytt.js;
/// lagdeling/oppsettForAntall/formerSomPasser regnet ut av db-nytt.js, med sakene fra paamelding-test.js
/// og skjevt-lag-test.js kontrollert).
struct FormTests {
    struct Fil: Decodable {
        let spillerePerBaas: Int
        let formStandard: String
        let former: [Form]
        let formForRunde: [FFR]
        let lagdeling: [Lagdeling]
        let oppsettForAntall: [Oppsett]
        let formerSomPasser: [Forslag]
    }
    struct Form: Decodable {
        let id, navn: String
        let lag: Int
        let kort, regning: String
        let hcpAndel: Double?
        let stotte: String
        let taalerSkjevtLag: Bool
        let hjelp: String
    }
    struct FFR: Decodable { let gameType: String?; let id: String; let erLagform: Bool }
    struct Deling: Decodable { let sider: Int; let storrelser: [Int]; let matcher: Int }
    struct Lagdeling: Decodable { let antall: Int; let k: Int; let taalerSkjevt: Bool; let svar: Deling? }
    struct OppsettSvar: Decodable {
        let ok: Bool
        let hvorfor: String?
        let form: String?
        let trekant: Bool?
        let dueller: Int?
        let sider: Int?
        let matcher: Int?
        let storrelser: [Int]?
        let skjevt: Bool?
    }
    struct Oppsett: Decodable { let formId: String; let antall: Int; let svar: OppsettSvar }
    struct ForslagRad: Decodable { let id, navn, form: String; let skjevt, trekant: Bool }
    struct Forslag: Decodable { let antall: Int; let svar: [ForslagRad] }

    let fil: Fil

    init() throws {
        fil = try Fixture.load(Fil.self, "former")
    }

    @Test func registeretErLiktPWA() {
        #expect(CompetitionForm.defaultID == fil.formStandard)
        #expect(CompetitionForm.golfgutuMaxPerBay == fil.spillerePerBaas)
        #expect(CompetitionForm.all.count == fil.former.count)
        for (swift, js) in zip(CompetitionForm.all, fil.former) {
            #expect(swift.id == js.id)
            #expect(swift.name == js.navn, "\(js.id): navn")
            #expect(swift.teamSize == js.lag, "\(js.id): lag")
            #expect(swift.card.rawValue == js.kort, "\(js.id): kort")
            #expect(swift.scoring == js.regning, "\(js.id): regning")
            #expect(swift.allowance == js.hcpAndel, "\(js.id): hcpAndel")
            #expect(swift.support.rawValue == js.stotte, "\(js.id): stotte")
            #expect(swift.allowsUnevenTeams == js.taalerSkjevtLag, "\(js.id): taalerSkjevtLag")
            #expect(swift.help == js.hjelp, "\(js.id): hjelp")
        }
    }

    /// paamelding-test.js bruker konkurranseform(id).lag og .stotte; ukjent id gir standardformen.
    @Test func konkurranseform() {
        #expect(CompetitionForm.form(id: "scramble-4").teamSize == 4)
        #expect(CompetitionForm.form(id: "tull").id == "stableford")
        #expect(CompetitionForm.form(id: nil).id == "stableford")
    }

    /// Egen (ingen direkte PWA-test): formForRunde og erLagform, regnet ut av db-nytt.js.
    @Test func formForRundeOgErLagform() {
        for sak in fil.formForRunde {
            let r = Round(gameType: sak.gameType)
            #expect(r.form.id == sak.id, "gameType \(String(describing: sak.gameType))")
            #expect(r.isTeamForm == sak.erLagform, "gameType \(String(describing: sak.gameType))")
        }
    }

    /// Egen (ingen direkte PWA-test): lagdeling for 0–17 spillere, k = 1–5, regnet ut av db-nytt.js.
    @Test func lagdeling() {
        #expect(fil.lagdeling.count == 180)
        for sak in fil.lagdeling {
            let svar = CompetitionForm.teamSplit(players: sak.antall, teamSize: sak.k, allowsUneven: sak.taalerSkjevt)
            let navn = "lagdeling(\(sak.antall), \(sak.k), \(sak.taalerSkjevt))"
            if let f = sak.svar {
                #expect(svar == TeamSplit(sides: f.sider, sizes: f.storrelser, matches: f.matcher), "\(navn)")
            } else {
                #expect(svar == nil, "\(navn)")
            }
        }
    }

    @Test func oppsettForAntall() {
        for sak in fil.oppsettForAntall {
            let s = CompetitionForm.setup(formID: sak.formId, players: sak.antall)
            let navn = "oppsettForAntall('\(sak.formId)', \(sak.antall))"
            let f = sak.svar
            #expect(s.isOK == f.ok, "\(navn): ok")
            #expect(s.reason == f.hvorfor, "\(navn): hvorfor")
            #expect(s.text == f.form, "\(navn): form")
            switch s {
            case .individual(let duels, let triangle, _):
                #expect(duels == f.dueller && triangle == f.trekant, "\(navn)")
            case .teams(let split, let uneven, _):
                #expect(split.sides == f.sider && split.matches == f.matcher && split.sizes == f.storrelser, "\(navn)")
                #expect(uneven == f.skjevt, "\(navn): skjevt")
            case .impossible:
                break
            }
        }
    }

    /// paamelding-test.js, bokstavelig.
    @Test func paameldingSaker() {
        #expect(CompetitionForm.setup(formID: "stableford", players: 11).text == "4 dueller og én trekant")
        #expect(CompetitionForm.setup(formID: "stableford", players: 11).isTriangle)
        #expect(CompetitionForm.setup(formID: "stableford", players: 12).text == "6 dueller")
        #expect(!CompetitionForm.setup(formID: "stableford", players: 12).isTriangle)
        #expect(CompetitionForm.setup(formID: "stableford", players: 3).text == "én trekant")
        #expect(!CompetitionForm.setup(formID: "stableford", players: 1).isOK)
        #expect(CompetitionForm.setup(formID: "scramble-2", players: 11).text == "4 lag (3+3+3+2) · 2 matcher")
        #expect(CompetitionForm.setup(formID: "scramble-2", players: 11).isUneven)
        #expect(!CompetitionForm.setup(formID: "scramble-2", players: 12).isUneven)
        #expect(!CompetitionForm.setup(formID: "foursome", players: 11).isOK)
        #expect(CompetitionForm.setup(formID: "foursome", players: 12).isOK)
        #expect(!CompetitionForm.setup(formID: "scramble-4", players: 9).isOK)
        #expect(CompetitionForm.setup(formID: "scramble-4", players: 16).isOK)
        #expect(CompetitionForm.setup(formID: "scramble-4", players: 3).reason?.contains("går ikke opp i et likt antall lag på 4") == true)

        let elleve = CompetitionForm.suggestions(players: 11).map(\.id)
        #expect(elleve.contains("stableford") && elleve.contains("scramble-2"))
        #expect(!elleve.contains("foursome"))
        let sju = CompetitionForm.suggestions(players: 7)
        #expect(!sju.isEmpty && sju.allSatisfy { CompetitionForm.form(id: $0.id).teamSize == 1 })
        #expect(CompetitionForm.suggestions(players: 12).allSatisfy { CompetitionForm.form(id: $0.id).support == .full })
    }

    /// skjevt-lag-test.js: fourball tar lag opp til en full bås; foursome krever like lag;
    /// ingen form gir lag større enn en bås.
    @Test func skjevtLag() {
        let fourball = CompetitionForm.form(id: "fourball")
        #expect(fourball.allowsUnevenTeams)
        #expect(!CompetitionForm.form(id: "foursome").allowsUnevenTeams)
        #expect(!CompetitionForm.form(id: "greensome").allowsUnevenTeams)
        #expect(CompetitionForm.teamSplit(players: 5, teamSize: 2, allowsUneven: true) == TeamSplit(sides: 2, sizes: [3, 2], matches: 1))
        #expect(CompetitionForm.teamSplit(players: 5, teamSize: 2, allowsUneven: false) == nil)
        #expect(CompetitionForm.teamSplit(players: 9, teamSize: 4, allowsUneven: true) == nil)
    }

    @Test func formerSomPasser() {
        for sak in fil.formerSomPasser {
            let svar = CompetitionForm.suggestions(players: sak.antall)
            #expect(svar.map(\.id) == sak.svar.map(\.id), "formerSomPasser(\(sak.antall))")
            for (s, f) in zip(svar, sak.svar) {
                #expect(s.name == f.navn && s.text == f.form && s.uneven == f.skjevt && s.triangle == f.trekant,
                        "formerSomPasser(\(sak.antall)): \(f.id)")
            }
        }
    }

    /// Egen: maks per bås kommer fra regelsettet. Utledet fra lagdeling(): maks = min(k eller k+1, bås);
    /// er maks < k går det aldri; ellers velges flest sider med sider·k ≤ antall ≤ sider·maks.
    @Test func maksPerBaasFraRegelsett() {
        #expect(!CompetitionForm.setup(formID: "scramble-4", players: 16, maxPerBay: 3).isOK)
        #expect(CompetitionForm.teamSplit(players: 5, teamSize: 2, allowsUneven: true, maxPerBay: 2) == nil)
        #expect(CompetitionForm.teamSplit(players: 9, teamSize: 4, allowsUneven: true, maxPerBay: 5)
                == TeamSplit(sides: 2, sizes: [5, 4], matches: 1))
    }
}
