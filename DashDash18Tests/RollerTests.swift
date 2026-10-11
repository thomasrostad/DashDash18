import Foundation
import Testing
@testable import DashDash18

private let club = UUID()

private func role(_ name: String, _ rights: [ClubRight] = [], owner: Bool = false, template: String? = nil,
                  sort: Int = 0) -> ClubRoleRow {
    ClubRoleRow(id: UUID(), clubID: club, name: name, rights: owner ? ClubRight.allCases.map(\.rawValue) : rights.map(\.rawValue),
                isOwner: owner, templateKey: owner ? "owner" : template, sortOrder: sort)
}

private let owner = role("Eier", owner: true)
private let organizer = role("Arrangør", ClubRight.allCases, template: "organizer", sort: 1)
private let treasurer = role("Kasserer", [.money], template: "treasurer", sort: 2)
private let committee = role("Sosialkomité", template: "committee", sort: 3)
private let banemester = role("Banemester", [.rounds], sort: 4)
private let porter = role("Dørvakt", [.members], sort: 5)

struct ClubRightsTests {
    @Test func eierHarAltOgStyrerRollene() {
        let rights = ClubRights(roles: [owner])
        #expect(rights.isOwner)
        #expect(rights.rights == Set(ClubRight.allCases))
        #expect(rights.canManageRoles)
        #expect(AdminArea.visible(for: rights) == Set(AdminArea.allCases))
    }

    @Test func eierrollensRettigheterStarFastSelvOmRadenSierNoeAnnet() {
        var row = owner
        row.rights = []
        #expect(row.rightSet == Set(ClubRight.allCases))
        #expect(ClubRights(roles: [row]).has(.money))
    }

    @Test func rettigheteneLeggesSammen() {
        let rights = ClubRights(roles: [treasurer, banemester])
        #expect(rights.rights == [.money, .rounds])
        #expect(!rights.isOwner)
        #expect(rights.hasAny)
    }

    @Test func sosialkomiteGirIngenting() {
        let rights = ClubRights(roles: [committee])
        #expect(!rights.hasAny)
        #expect(AdminArea.visible(for: rights).isEmpty)
    }

    @Test func ukjenteRettigheterHoppesOver() {
        var row = treasurer
        row.rights = ["money", "noe_nytt"]
        #expect(row.rightSet == [.money])
    }

    @Test func utenRollerGjelderFlaggene() {
        #expect(ClubRights.legacy(isOrganizer: true, isTreasurer: false).rights == Set(ClubRight.allCases))
        #expect(!ClubRights.legacy(isOrganizer: true, isTreasurer: false).isOwner)
        #expect(ClubRights.legacy(isOrganizer: false, isTreasurer: true).rights == [.money])
        #expect(!ClubRights.legacy(isOrganizer: false, isTreasurer: false).hasAny)
    }
}

struct AdminAreaTests {
    @Test func kassererSerBareRapporterVarslerOgKlubben() {
        #expect(AdminArea.visible(for: ClubRights(rights: [.money])) == [.reports, .notices, .club])
    }

    @Test func turneringerGirTurneringOgKveldene() {
        #expect(AdminArea.visible(for: ClubRights(rights: [.tournaments])) == [.tournaments, .timeline, .notices, .club])
    }

    @Test func runderGirBaneneArkivetOgKveldene() {
        #expect(AdminArea.visible(for: ClubRights(rights: [.rounds])) == [.rounds, .timeline, .notices, .club])
    }

    @Test func medlemmerGirTroppen() {
        #expect(AdminArea.visible(for: ClubRights(rights: [.members])) == [.roster, .notices, .club])
    }

    @Test func dagensArrangorSerAltUntattRollene() {
        let legacy = ClubRights.legacy(isOrganizer: true, isTreasurer: false)
        #expect(AdminArea.visible(for: legacy) == Set(AdminArea.allCases).subtracting([.roles]))
        let arrangor = ClubRights(roles: [organizer])
        #expect(AdminArea.visible(for: arrangor) == Set(AdminArea.allCases).subtracting([.roles]))
    }
}

struct ClubRoleGrantTests {
    @Test func bareEierGirEier() {
        #expect(ClubRights(roles: [owner]).canGrant(owner))
        #expect(!ClubRights(roles: [organizer]).canGrant(owner))
    }

    @Test func kreverMedlemmerOgEnDelmengde() {
        let porterRights = ClubRights(roles: [porter])
        #expect(porterRights.canGrant(committee))      // ingen rettigheter er en delmengde
        #expect(porterRights.canGrant(porter))
        #expect(!porterRights.canGrant(treasurer))     // har ikke money
        #expect(!porterRights.canGrant(organizer))

        let porterAndMoney = ClubRights(roles: [porter, treasurer])
        #expect(porterAndMoney.canGrant(treasurer))
        #expect(!porterAndMoney.canGrant(banemester))
    }

    @Test func utenMedlemmerKanDuIkkeGiNoe() {
        let money = ClubRights(roles: [treasurer])
        #expect(!money.canGrant(committee))
        #expect(!money.canGrant(treasurer))
    }

    @Test func arrangorGirAltUntattEier() {
        let rights = ClubRights(roles: [organizer])
        for r in [organizer, treasurer, committee, banemester, porter] {
            #expect(rights.canGrant(r))
        }
    }

    @Test func overforEierskap() {
        let me = UUID()
        let other = ClubMemberRow(id: UUID(), clubID: club, userID: UUID(), displayName: "Kari", handicapIndex: nil,
                                  seedGroup: nil, isOrganizer: false, isTreasurer: false, status: .active, avatarPath: nil)
        let ownerRights = ClubRights(roles: [owner])
        #expect(ClubRoleInput.canTransferOwnership(viewer: ownerRights, to: other, me: me, memberIsOwner: false))
        #expect(!ClubRoleInput.canTransferOwnership(viewer: ownerRights, to: other, me: me, memberIsOwner: true))
        #expect(!ClubRoleInput.canTransferOwnership(viewer: ClubRights(roles: [organizer]), to: other, me: me,
                                                    memberIsOwner: false))
        var noLogin = other
        noLogin.userID = nil
        #expect(!ClubRoleInput.canTransferOwnership(viewer: ownerRights, to: noLogin, me: me, memberIsOwner: false))
        #expect(!ClubRoleInput.canTransferOwnership(viewer: ownerRights, to: other, me: other.id, memberIsOwner: false))
    }
}

struct ClubRoleOrderTests {
    @Test func eierForstSaMaleneSaEgne() {
        let shuffled = [porter, committee, owner, banemester, treasurer, organizer]
        #expect(ClubRoleOrder.sorted(shuffled).map(\.name) == ["Eier", "Arrangør", "Kasserer", "Sosialkomité", "Banemester", "Dørvakt"])
    }

    @Test func egneRollerEtterMalerSelvMedLavereSortOrder() {
        let early = role("Alfa", sort: -5)
        #expect(ClubRoleOrder.sorted([early, organizer]).map(\.name) == ["Arrangør", "Alfa"])
    }

    @Test func navnValideres() {
        let roles = [owner, organizer]
        #expect(ClubRoleInput.validate(name: "  Banemester ", roles: roles, editing: nil) == .success("Banemester"))
        #expect(ClubRoleInput.validate(name: "arrangør", roles: roles, editing: nil)
            == .failure(.invalid("Klubben har alt en rolle som heter «arrangør».")))
        #expect(ClubRoleInput.validate(name: "Arrangør", roles: roles, editing: organizer.id) == .success("Arrangør"))
        #expect(ClubRoleInput.validate(name: "   ", roles: roles, editing: nil) == .failure(.invalid("Rollen må ha et navn (1–40 tegn).")))
        #expect(ClubRoleInput.validate(name: String(repeating: "a", count: 41), roles: roles, editing: nil)
            == .failure(.invalid("Rollen må ha et navn (1–40 tegn).")))
    }

    @Test func rettigheteneSendesIFastRekkefolge() {
        #expect(ClubRoleInput.rightsParameter([.money, .tournaments]) == ["tournaments", "money"])
    }

    @Test func rollerPerKlubb() {
        let me = UUID()
        let other = UUID()
        let mine = [ClubMemberRoleRow(clubID: club, memberID: me, roleID: treasurer.id),
                    ClubMemberRoleRow(clubID: club, memberID: other, roleID: owner.id)]
        let access = ClubRoleAccess.byClub(roles: [owner, treasurer, organizer], mine: mine, memberIDs: [me])
        #expect(access[club]?.myRoleIDs == [treasurer.id])
        #expect(access[club]?.rights == ClubRights(rights: [.money]))
        #expect(access[club]?.roles.first?.isOwner == true)
    }

    @Test func dekoderRaden() throws {
        let json = """
        {"id":"\(UUID().uuidString)","club_id":"\(club.uuidString)","name":"Kasserer","rights":["money"],
         "is_owner":false,"template_key":"treasurer","sort_order":2}
        """
        let row = try JSONDecoder().decode(ClubRoleRow.self, from: Data(json.utf8))
        #expect(row.rightSet == [.money])
        #expect(row.isTemplate)
    }
}

struct EnhetsregisteretTests {
    @Test func normalisererNummeret() {
        #expect(Enhetsregisteret.normalized("923 609 016") == "923609016")
        #expect(Enhetsregisteret.normalized("923\u{00A0}609\u{00A0}016") == "923609016")
        #expect(Enhetsregisteret.normalized("12345") == nil)
        #expect(Enhetsregisteret.normalized("92360901A") == nil)
        #expect(Enhetsregisteret.normalized("9236090160") == nil)
    }

    @Test func lagresSomNullNarTomt() {
        #expect(Enhetsregisteret.storedValue("  ") == .success(nil))
        #expect(Enhetsregisteret.storedValue("923609016") == .success("923609016"))
        #expect(Enhetsregisteret.storedValue("123") == .failure(.invalidNumber))
    }

    @Test func lenken() {
        #expect(Enhetsregisteret.url(for: "923609016").absoluteString
            == "https://data.brreg.no/enhetsregisteret/api/enheter/923609016")
    }

    @Test func leserNavnet() {
        let body = #"{"organisasjonsnummer":"923609016","navn":"EQUINOR ASA","organisasjonsform":{"kode":"ASA"}}"#
        #expect(Enhetsregisteret.parse(status: 200, data: Data(body.utf8)) == .success("EQUINOR ASA"))
    }

    @Test func feilene() {
        #expect(Enhetsregisteret.parse(status: 404, data: Data()) == .failure(.notFound))
        #expect(Enhetsregisteret.parse(status: 400, data: Data(#"{"feilmelding":"Ugyldig"}"#.utf8)) == .failure(.invalidNumber))
        #expect(Enhetsregisteret.parse(status: 410, data: Data()) == .failure(.deleted))
        #expect(Enhetsregisteret.parse(status: 500, data: Data()) == .failure(.failed))
        #expect(Enhetsregisteret.parse(status: 200, data: Data("{}".utf8)) == .failure(.failed))
        #expect(Enhetsregisteret.parse(status: 200, data: Data("ikke json".utf8)) == .failure(.failed))
        #expect(Enhetsregisteret.LookupError.notFound.message == "Fant ingen enhet med det nummeret.")
    }
}
