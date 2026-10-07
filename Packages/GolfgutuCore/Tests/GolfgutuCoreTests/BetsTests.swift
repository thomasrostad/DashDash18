import Foundation
import Testing
@testable import GolfgutuCore

/// Veddemål med poeng (fase 10). Tall: Fixtures/veddemaal.json, regnet ut av db-nytt.js og
/// app-nytt.js på scenarioene fra vilkaar-test.js, lockout-test.js, kveld-test.js,
/// status-del-test.js og poster-test.js («egen» = scenario uten PWA-test, svaret er fortsatt
/// PWA-ens). Kroner er poeng. Oppgjøret og feiingen kjøres med PWA-ens regler (`pwa`: to
/// desimaler, ingen automatisk annullering); Golfgutu-malen har hele poeng og annullerer delt.
struct BetsTests {
    /// Golfgutu-oppsettet med PWA-ens oppgjør og feiing (`Ruleset.BetRules.pwa`).
    static let pwa: Ruleset = {
        var r = Ruleset.golfgutu
        r.bets = .pwa
        return r
    }()

    struct Fil: Decodable {
        let utfall: [Utfall]
        let laasing: [Laasing]
        let forsteApneHull: [Apent]
        let lukking: [Lukking]
        let feiing: [Feiing]
        let maler: [Maler]
        let poster: [Poster]
        let netto: [Netto]
        let nettoing: [Nettoing]
        let status: [Status]
    }
    struct Utfall: Decodable {
        let navn, kilde: String
        let spillere: [Player]
        let runde: Round
        let innmeldinger: [SideClaim]
        let vilkaar: BetCondition
        let forventet: BetSide?
    }
    struct Laasing: Decodable {
        let navn: String
        let runde: Round?
        let veddemaal: Bet
        let forventet: Bool
    }
    struct Apent: Decodable {
        let navn: String
        let runde: Round
        let spillere: [String]
        let forventet: Int?
    }
    struct Lukking: Decodable {
        let navn: String
        let runde: Round
        let veddemaal: Bet
        let hull: Int
        let forventet: Bool
    }
    struct Skriving: Decodable { let id: String; let lukkes: Bool; let utfall: BetSide? }
    struct Feiing: Decodable {
        let navn: String
        let spillere: [Player]
        let runde: Round
        let hull: Int?
        let veddemaal: [Bet]
        let forventet: [Skriving]
    }
    struct Mal: Decodable {
        let mal: BetTemplate.Kind
        let vilkaar: BetCondition?
        let side: BetSide
        let tekst: String
        let tarInnsatser: Bool
    }
    struct Maler: Decodable {
        let navn: String
        let runde: Round?
        let meg: String
        let mot: String?
        let forventet: [Mal]
    }
    struct Post: Decodable { let fra, til: String; let poeng: Double }
    struct Poster: Decodable {
        let navn: String
        let veddemaal: Bet
        let forventet: [Post]
    }
    struct Netto: Decodable {
        let veddemaal: [Bet]
        let forventet: [String: Double]
        let rekkefolge: [String]
    }
    struct Linje: Decodable { let motpart: String; let poeng: Double }
    struct NettoUt: Decodable {
        let betaler, faar: [Linje]
        let nullPar: [String]
        let sumBetaler, sumFaar: Double
    }
    struct Nettoing: Decodable {
        let navn, meg: String
        let poster: [Post]
        let forventet: NettoUt
    }
    struct Status: Decodable {
        let navn: String
        let status: Bet.Status
        let resolution: BetSide?
        let tarInnsatser: Bool
        let forventet: BetPhase
    }

    let fil: Fil

    init() throws {
        fil = try Fixture.load(Fil.self, "veddemaal")
    }

    // MARK: vilkaar-test.js, kveld-test.js §5

    @Test func utfalletErSomPWA() {
        #expect(fil.utfall.count == 36)
        for sak in fil.utfall {
            let svar = Bets.outcome(sak.runde, condition: sak.vilkaar, roster: sak.spillere, claims: sak.innmeldinger)
            #expect(svar == sak.forventet, "\(sak.kilde): \(sak.navn)")
        }
    }

    /// Ferdighetskravet i ROADMAP: «birdie på hull 5» stenger når hull 4 er ført, og avgjøres
    /// riktig når hull 5 føres.
    @Test func birdiePaaHullFemStengerOgAvgjores() {
        let course = Course(id: "b", par: 36, courseRating: 36, slopeRating: 113,
                            holes: [4, 4, 3, 4, 5, 3, 4, 4, 5].enumerated().map { CourseHole(par: $0.element, si: $0.offset + 1) })
        var round = Round(id: "r1", holeCount: 9, course: course, hcpAllowance: 1, hcpExtern: true)
        let bet = Bet(id: "m", condition: BetCondition(kind: .birdie, round: "r1", hole: 4, player: "a"))
        round.holeScores = ["a": [0: 4, 1: 4, 2: 3]]
        #expect(Bets.acceptsStakes(bet, round: round))
        round.holeScores["a"]![3] = 4
        #expect(!Bets.acceptsStakes(bet, round: round))
        #expect(Bets.outcome(round, condition: bet.condition!, roster: []) == nil)
        round.holeScores["a"]![4] = 4
        #expect(Bets.outcome(round, condition: bet.condition!, roster: []) == .yes)
        #expect(Bets.sweep([bet], round: round, hole: 4, roster: []) == [BetUpdate(betID: "m", close: true, outcome: .yes)])
    }

    // MARK: lockout-test.js, kveld-test.js §3

    @Test func laasingenErSomPWA() {
        #expect(fil.laasing.count == 22)
        for sak in fil.laasing {
            #expect(Bets.acceptsStakes(sak.veddemaal, round: sak.runde) == sak.forventet, "\(sak.navn)")
        }
    }

    @Test func forsteApneHullErSomPWA() {
        #expect(fil.forsteApneHull.count == 14)
        for sak in fil.forsteApneHull {
            #expect(Bets.firstOpenHole(sak.runde, players: sak.spillere) == sak.forventet, "\(sak.navn)")
        }
        #expect(Bets.firstOpenHole(nil, players: ["a"]) == nil)
    }

    /// Forspranget er en regelverdi. To hull: også hullet etter det som spilles nå er stengt.
    @Test func forsprangetFraRegelsettet() {
        var rules = Ruleset.golfgutu
        rules.bets.lockAheadHoles = 2
        let round = Round(id: "r1", holeCount: 18, holeScores: ["a": [0: 4, 1: 4]])
        #expect(Bets.firstOpenHole(round, players: ["a"]) == 3)
        #expect(Bets.firstOpenHole(round, players: ["a"], rules: rules) == 4)
        let bet = Bet(condition: BetCondition(kind: .par, round: "r1", hole: 3, player: "a"))
        #expect(Bets.acceptsStakes(bet, round: round))
        #expect(!Bets.acceptsStakes(bet, round: round, rules: rules))
        // Før første slag er hull 1 åpent uansett forsprang.
        #expect(Bets.firstOpenHole(Round(id: "r1"), players: ["a"], rules: rules) == 0)
    }

    // MARK: Lukking og feiing (vilkaar-test.js)

    @Test func lukkingErSomPWA() {
        #expect(fil.lukking.count == 9)
        for sak in fil.lukking {
            #expect(Bets.shouldClose(sak.veddemaal, round: sak.runde, hole: sak.hull) == sak.forventet, "\(sak.navn)")
        }
    }

    @Test func feiingenSkriverDetSammeSomPWA() {
        #expect(fil.feiing.count == 8)
        for sak in fil.feiing {
            let svar = Bets.sweep(sak.veddemaal, round: sak.runde, hole: sak.hull, roster: sak.spillere, rules: Self.pwa)
            #expect(svar.map(\.betID) == sak.forventet.map(\.id), "\(sak.navn)")
            #expect(svar.map(\.close) == sak.forventet.map(\.lukkes), "\(sak.navn)")
            #expect(svar.map(\.outcome) == sak.forventet.map(\.utfall), "\(sak.navn)")
        }
    }

    // MARK: Malene (lockout-test.js §5, kveld-test.js §4)

    @Test func maleneErSomPWA() {
        #expect(fil.maler.count == 12)
        for sak in fil.maler {
            let maler = Bets.templates(round: sak.runde, me: sak.meg, against: sak.mot)
            #expect(maler.map(\.kind) == sak.forventet.map(\.mal), "\(sak.navn)")
            #expect(maler.map(\.condition) == sak.forventet.map(\.vilkaar), "\(sak.navn)")
            #expect(maler.map(\.side) == sak.forventet.map(\.side), "\(sak.navn)")
            // Det appen tilbyr, slipper gjennom sperra.
            for (mal, ventet) in zip(maler, sak.forventet) {
                let bet = Bet(condition: mal.condition)
                #expect(Bets.acceptsStakes(bet, round: sak.runde) == ventet.tarInnsatser, "\(sak.navn): \(ventet.tekst)")
                #expect(ventet.tarInnsatser, "\(sak.navn): \(ventet.tekst)")
            }
        }
    }

    // MARK: Oppgjøret (poster-test.js)

    @Test func overforingeneErSomVeddemaalPoster() {
        #expect(fil.poster.count == 8)
        for sak in fil.poster {
            let svar = Bets.transfers(sak.veddemaal, rules: Self.pwa)
            #expect(svar == sak.forventet.map { BetTransfer(from: $0.fra, to: $0.til, points: $0.poeng) }, "\(sak.navn)")
            // Summen av netto over alle spillere er 0.
            var perSpiller: [String: Double] = [:]
            for t in svar {
                perSpiller[t.from, default: 0] -= t.points
                perSpiller[t.to, default: 0] += t.points
            }
            #expect(abs(perSpiller.values.reduce(0, +)) < 0.001, "\(sak.navn)")
        }
    }

    /// marketNetFor runder ikke; med to desimaler er hvert veddemål høyst en hundredel unna.
    @Test func nettoPerSpillerErSomMarketNetFor() throws {
        let sak = try #require(fil.netto.first)
        for (pid, ventet) in sak.forventet {
            #expect(abs(Bets.net(for: pid, in: sak.veddemaal, rules: Self.pwa) - ventet) < 0.01, "\(pid)")
        }
        #expect(Bets.net(for: "t", in: sak.veddemaal, rules: Self.pwa) == -116.67)
        // Nullsum.
        #expect(abs(sak.forventet.keys.reduce(0) { $0 + Bets.net(for: $1, in: sak.veddemaal, rules: Self.pwa) }) < 1e-9)
        // Tabellen uten bank sorterer som marketLeaderboardNytt.
        let spillere = sak.forventet.keys.sorted().map { Player(id: $0, name: $0) }
        let tabell = Bets.table(players: spillere, bets: sak.veddemaal, rules: Self.pwa)
        #expect(tabell.map(\.playerID) == sak.rekkefolge)
        #expect(tabell.allSatisfy { $0.balance == nil && $0.available == nil })
    }

    /// «Poengene i veddemålstabellen stemmer med regnestykket»: netto per spiller er summen av
    /// overføringene, med høyst én hundredel avvik per overføring (avrundingen i veddemaalPoster).
    @Test func tabellenStemmerMedOverforingene() throws {
        let sak = try #require(fil.netto.first)
        let overforinger = sak.veddemaal.flatMap { Bets.transfers($0, rules: Self.pwa) }
        for pid in sak.forventet.keys {
            let fraOverforinger = overforinger.reduce(0.0) { s, t in
                s + (t.to == pid ? t.points : 0) - (t.from == pid ? t.points : 0)
            }
            #expect(abs(fraOverforinger - Bets.net(for: pid, in: sak.veddemaal, rules: Self.pwa))
                    <= 0.01 * Double(overforinger.count), "\(pid)")
        }
    }

    @Test func nettoingErSomSkyldOversikt() {
        #expect(fil.nettoing.count == 4)
        for sak in fil.nettoing {
            let o = Bets.netting(sak.poster.map { BetTransfer(from: $0.fra, to: $0.til, points: $0.poeng) }, for: sak.meg)
            #expect(o.gives.map(\.counterpart) == sak.forventet.betaler.map(\.motpart), "\(sak.navn)")
            #expect(o.gives.map(\.points) == sak.forventet.betaler.map(\.poeng), "\(sak.navn)")
            #expect(o.receives.map(\.counterpart) == sak.forventet.faar.map(\.motpart), "\(sak.navn)")
            #expect(o.receives.map(\.points) == sak.forventet.faar.map(\.poeng), "\(sak.navn)")
            #expect(o.even == sak.forventet.nullPar, "\(sak.navn)")
            #expect(o.totalGives == sak.forventet.sumBetaler, "\(sak.navn)")
            #expect(o.totalReceives == sak.forventet.sumFaar, "\(sak.navn)")
        }
    }

    // MARK: Statuspillen (status-del-test.js)

    @Test func statuspillenHarEnBetydning() {
        for sak in fil.status {
            let bet = Bet(status: sak.status, resolution: sak.resolution)
            #expect(Bets.phase(bet, acceptsStakes: sak.tarInnsatser) == sak.forventet, "\(sak.navn)")
        }
        #expect(Bets.phase(Bet(status: .void), acceptsStakes: false) == .void)
    }

    // MARK: Egne: annullert, poengbanken og innsatsen

    /// Annullert (utvidelse): ingen overføringer, alle står på null, og det tar ingen innsatser.
    @Test func annullertGirInnsatsenTilbake() {
        let bet = Bet(status: .void, resolution: nil, stakes: [
            BetStake(playerID: "a", side: .yes, points: 100), BetStake(playerID: "b", side: .no, points: 50),
        ])
        #expect(Bets.transfers(bet).isEmpty)
        #expect(Bets.net(for: "a", in: [bet]) == 0)
        #expect(Bets.atStake(for: "a", in: [bet]) == 0)
        #expect(!Bets.acceptsStakes(bet, round: nil))
    }

    /// Poengbanken (utvidelse): saldo = start + netto, ledig = saldo − det som står i åpne.
    /// Tall utledet fra formelen: a vant 50 fra b (100 mot 50, JA vant), og har 70 i et åpent.
    @Test func poengbanken() {
        let avgjort = Bet(id: "1", status: .resolved, resolution: .yes, stakes: [
            BetStake(playerID: "a", side: .yes, points: 100), BetStake(playerID: "b", side: .no, points: 50),
        ])
        let aapent = Bet(id: "2", stakes: [BetStake(playerID: "a", side: .no, points: 70)])
        let bets = [avgjort, aapent]
        #expect(Bets.net(for: "a", in: bets) == 50)
        #expect(Bets.net(for: "b", in: bets) == -50)
        #expect(Bets.atStake(for: "a", in: bets) == 70)
        #expect(Bets.balance(for: "a", in: bets) == 1050)
        #expect(Bets.available(for: "a", in: bets) == 980)
        #expect(Bets.balance(for: "b", in: bets) == 950)
        let tabell = Bets.table(players: [Player(id: "b", name: "Bjørn"), Player(id: "a", name: "Anders"),
                                          Player(id: "c", name: "Cato")], bets: bets)
        #expect(tabell.map(\.playerID) == ["a", "c", "b"])
        #expect(tabell[0].bets == 2 && tabell[0].won == 1)
        #expect(tabell[1].balance == 1000 && tabell[1].bets == 0)
        #expect(tabell[2].won == 0)
        // Likt: norsk navnesortering, Æ før Ø før Å.
        let likt = Bets.table(players: [Player(id: "x", name: "Åse"), Player(id: "y", name: "Øyvind"),
                                        Player(id: "z", name: "Ærlig")], bets: [])
        #expect(likt.map(\.name) == ["Ærlig", "Øyvind", "Åse"])
    }

    /// Sjekken av en innsats (utvidelse): tak summert, én side, ledige poeng, stengt.
    @Test func innsatsenSjekkes() {
        let round = Round(id: "r1", holeCount: 18, holeScores: ["a": [0: 4]])
        let bet = Bet(id: "m", condition: BetCondition(kind: .par, round: "r1", hole: 10, player: "a"),
                      stakes: [BetStake(playerID: "me", side: .no, points: 150)])
        func sjekk(_ side: BetSide, _ points: Int, bets: [Bet]? = nil, rules: Ruleset = .golfgutu) -> StakeProblem? {
            Bets.stakeProblem(bet, playerID: "me", side: side, points: points, round: round, bets: bets ?? [bet], rules: rules)
        }
        #expect(sjekk(.no, 50) == nil)
        #expect(sjekk(.no, 51) == .overCap(max: 200, already: 150))
        #expect(sjekk(.yes, 10) == .otherSide(.no))
        #expect(sjekk(.no, 0) == .invalidAmount)
        #expect(Bets.stakeProblem(bet, playerID: "ny", side: .yes, points: 201, round: round, bets: [bet]) == .overCap(max: 200, already: 0))
        // Banken: 1000 − 150 i dette − 820 i et annet åpent = 30 ledig.
        let annet = Bet(id: "x", stakes: [BetStake(playerID: "me", side: .yes, points: 820)])
        #expect(sjekk(.no, 50, bets: [bet, annet]) == .insufficient(available: 30))
        #expect(sjekk(.no, 30, bets: [bet, annet]) == nil)
        var ingenBank = Ruleset.golfgutu
        ingenBank.bets.startingPoints = nil
        #expect(sjekk(.no, 50, bets: [bet, annet], rules: ingenBank) == nil)
        // Stengt: hull 2 er ført, hull 3 spilles; veddemål på hull 3 tas ikke imot.
        let stengt = Bet(condition: BetCondition(kind: .par, round: "r1", hole: 1, player: "a"))
        #expect(Bets.stakeProblem(stengt, playerID: "me", side: .yes, points: 50, round: round, bets: []) == .closed)
    }

    @Test func posisjonOgHvemDetGjelder() {
        let bet = Bet(against: "b", stakes: [BetStake(playerID: "me", side: .no, points: 50),
                                             BetStake(playerID: "me", side: .no, points: 30)])
        #expect(bet.position(of: "me")?.side == .no)
        #expect(bet.position(of: "me")?.points == 80)
        #expect(bet.position(of: "c") == nil)
        #expect(bet.isAbout("b"))
        #expect(Bet(condition: BetCondition(kind: .hole, round: "r", hole: 1, a: "x", b: "y")).isAbout("y"))
        #expect(!bet.isAbout("me"))
    }

    // MARK: Regelsettet

    @Test func regelsettetForVeddemaal() throws {
        let g = Ruleset.golfgutu.bets
        // VEDDEMAAL_FORSPRANG = 1, VEDD_TAK = 200, VEDD_BELOP = [50, 100, 200], arket åpner på 100.
        #expect(g.lockAheadHoles == 1)
        #expect(g.maxStakePerBet == 200)
        #expect(g.stakeOptions == [50, 100, 200])
        #expect(g.defaultStake == 100)
        #expect(g.startingPoints == 1000)
        // Brukerens valg 07.10.2026: hele poeng og automatisk annullering av delt.
        #expect(g.payoutDecimals == 0)
        #expect(g.voidTies)
        #expect(Ruleset.golfgutu.validate().isEmpty)
        #expect(Self.pwa.validate().isEmpty)

        let egne = try JSONDecoder().decode(Ruleset.self, from: Data("""
        {"version": 2, "bets": {"lockAheadHoles": 2, "startingPoints": null}}
        """.utf8))
        #expect(egne.bets.lockAheadHoles == 2)
        #expect(egne.bets.startingPoints == nil)
        #expect(egne.bets.maxStakePerBet == 200)
        #expect(egne.bets.payoutDecimals == 0 && egne.bets.voidTies)
        let pwaJSON = try JSONDecoder().decode(Ruleset.self, from: Data(
            #"{"version": 2, "bets": {"payoutDecimals": 2, "voidTies": false}}"#.utf8))
        #expect(pwaJSON.bets.payoutDecimals == 2 && !pwaJSON.bets.voidTies)
        let rundtur = try JSONDecoder().decode(Ruleset.self, from: JSONEncoder().encode(egne))
        #expect(rundtur == egne)
        let uten = try JSONDecoder().decode(Ruleset.self, from: Data(#"{"version": 2}"#.utf8))
        #expect(uten.bets == g)

        func felt(_ endre: (inout Ruleset) -> Void) -> [String] {
            var r = Ruleset.golfgutu
            endre(&r)
            return r.validate().map(\.field)
        }
        #expect(felt { $0.bets.lockAheadHoles = 0 } == ["bets.lockAheadHoles"])
        #expect(felt { $0.bets.maxStakePerBet = 0 }.contains("bets.maxStakePerBet"))
        #expect(felt { $0.bets.stakeOptions = [50, 300] } == ["bets.stakeOptions"])
        #expect(felt { $0.bets.defaultStake = 250 } == ["bets.defaultStake"])
        #expect(felt { $0.bets.startingPoints = -1 } == ["bets.startingPoints"])
        #expect(felt { $0.bets.startingPoints = nil }.isEmpty)
        #expect(felt { $0.bets.payoutDecimals = 3 } == ["bets.payoutDecimals"])
        #expect(felt { $0.bets.payoutDecimals = -1 } == ["bets.payoutDecimals"])
    }

    // MARK: Besluttet 07.10.2026: hele poeng, automatisk annullering, arrangør uten innsats

    /// 100 delt på tre vinnere med like innsatser: 33 hver, og poenget som ble til overs går til
    /// største innsats (likt: laveste id). Summen er null.
    @Test func helePoengFordelerResten() {
        let bet = Bet(status: .resolved, resolution: .yes, stakes: [
            BetStake(playerID: "c", side: .yes, points: 50), BetStake(playerID: "a", side: .yes, points: 50),
            BetStake(playerID: "b", side: .yes, points: 50), BetStake(playerID: "x", side: .no, points: 100),
        ])
        #expect(Bets.payouts(bet) == ["a": 34, "b": 33, "c": 33, "x": -100])
        #expect(Bets.net(for: "a", in: [bet]) == 34)
        // To desimaler: 33,34 / 33,33 / 33,33.
        #expect(Bets.payouts(bet, rules: Self.pwa) == ["a": 33.34, "b": 33.33, "c": 33.33, "x": -100])
        // Overføringene rundes hver for seg, som veddemaalPoster.
        #expect(Bets.transfers(bet).map(\.points) == [33, 33, 33])
    }

    /// For mye etter avrundingen: 60/30/10 mot 55 gir 33 + 16,5 + 5,5. floor(x + 0.5) gir 33, 17
    /// og 6 = 56, og poenget for mye tas fra største innsats.
    @Test func helePoengTarOverskuddetFraStorsteInnsats() {
        let bet = Bet(status: .resolved, resolution: .no, stakes: [
            BetStake(playerID: "b", side: .no, points: 30), BetStake(playerID: "a", side: .no, points: 60),
            BetStake(playerID: "c", side: .no, points: 10), BetStake(playerID: "x", side: .yes, points: 55),
        ])
        #expect(Bets.payouts(bet) == ["a": 32, "b": 17, "c": 6, "x": -55])
        // Flere innsatser fra samme spiller summeres før avrundingen.
        let delt = Bet(status: .resolved, resolution: .no, stakes: [
            BetStake(playerID: "a", side: .no, points: 20), BetStake(playerID: "b", side: .no, points: 30),
            BetStake(playerID: "a", side: .no, points: 40), BetStake(playerID: "c", side: .no, points: 10),
            BetStake(playerID: "x", side: .yes, points: 55),
        ])
        #expect(Bets.payouts(delt) == Bets.payouts(bet))
    }

    /// Nord og sør: over mange veddemål (deterministisk generert) er hvert oppgjør hele poeng,
    /// summen i hvert veddemål er null, hver gevinst er høyst halvannet poeng fra den eksakte, og
    /// summen av netto over alle spillere i sesongen er null.
    @Test func helePoengSkaperEllerFjernerIngenPoeng() {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next(_ n: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(n))
        }
        let players = (0..<9).map { "p\($0)" }
        var bets: [Bet] = []
        for i in 0..<400 {
            var stakes: [BetStake] = []
            for p in players where next(3) > 0 {
                stakes.append(BetStake(playerID: p, side: next(2) == 0 ? .yes : .no, points: Double(1 + next(200))))
            }
            let status: Bet.Status = i % 10 == 0 ? .void : .resolved
            bets.append(Bet(id: "\(i)", status: status, resolution: status == .resolved ? (next(2) == 0 ? .yes : .no) : nil,
                            stakes: stakes))
        }
        for bet in bets {
            let p = Bets.payouts(bet)
            #expect(p.values.allSatisfy { $0 == $0.rounded() }, "\(bet.id ?? "")")
            #expect(p.values.reduce(0, +) == 0, "\(bet.id ?? "")")
            guard let res = bet.resolution, !p.isEmpty else { continue }
            let win = bet.pool(res), lose = bet.pool(res.opposite)
            for (pid, x) in p where x >= 0 {
                let exact = bet.position(of: pid)!.points * lose / win
                #expect(abs(x - exact) <= 1.5, "\(bet.id ?? ""): \(pid)")
            }
        }
        #expect(players.reduce(0) { $0 + Bets.net(for: $1, in: bets) } == 0)
        let tabell = Bets.table(players: players.map { Player(id: $0, name: $0) }, bets: bets)
        #expect(tabell.reduce(0) { $0 + ($1.balance ?? 0) } == Double(1000 * players.count))
    }

    /// Delt hull: ukjent for PWA-en (arrangøren tar det), annullert av feiingen i Golfgutu-malen.
    @Test func deltHullAnnulleresAutomatisk() {
        let course = Course(id: "b", par: 36, courseRating: 36, slopeRating: 113,
                            holes: [4, 4, 3, 4, 5, 3, 4, 4, 5].enumerated().map { CourseHole(par: $0.element, si: $0.offset + 1) })
        var round = Round(id: "r1", holeCount: 9, course: course, hcpAllowance: 1, hcpExtern: true)
        let duell = Bet(id: "d", condition: BetCondition(kind: .hole, round: "r1", hole: 2, a: "a", b: "b"))
        round.holeScores = ["a": [0: 4, 1: 4, 2: 3], "b": [0: 5, 1: 4]]
        #expect(Bets.verdict(round, condition: duell.condition!, roster: []) == nil)
        round.holeScores["b"]![2] = 3
        #expect(Bets.outcome(round, condition: duell.condition!, roster: []) == nil)
        #expect(Bets.verdict(round, condition: duell.condition!, roster: []) == .void)
        #expect(Bets.verdict(round, condition: duell.condition!, roster: [], rules: Self.pwa) == nil)
        #expect(Bets.sweep([duell], round: round, hole: 2, roster: []) == [BetUpdate(betID: "d", close: true, verdict: .void)])
        #expect(Bets.sweep([duell], round: round, hole: 2, roster: [], rules: Self.pwa)
                == [BetUpdate(betID: "d", close: true, outcome: nil)])
        // Ikke delt: avgjøres som før.
        round.holeScores["b"]![2] = 4
        #expect(Bets.verdict(round, condition: duell.condition!, roster: []) == .yes)
        #expect(Bets.sweep([duell], round: round, hole: 2, roster: []).first?.outcome == .yes)
    }

    /// Den som avgjør, vedder ikke: arrangøren med innsats kan ikke avgjøre for hånd.
    @Test func arrangorenMedInnsatsAvgjorIkke() {
        let bet = Bet(stakes: [BetStake(playerID: "arr", side: .yes, points: 50), BetStake(playerID: "b", side: .no, points: 50)])
        #expect(!Bets.canResolve(bet, by: "arr"))
        #expect(Bets.canResolve(bet, by: "arr2"))
        #expect(!Bets.canResolve(Bet(status: .void), by: "arr2"))
        #expect(!Bets.canResolve(Bet(status: .resolved, resolution: .yes), by: "arr2"))
    }
}
