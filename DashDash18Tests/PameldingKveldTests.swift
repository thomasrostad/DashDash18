import Foundation
import Testing
@testable import DashDash18

// Påmelding per kveld (steg 4, sql/045): «kommer» uten ventelista pluss bekreftede gjester,
// ventelista i rekkefølge, fristene og feilen DDB02.

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
private let club = id(999)
private let eventID = id(101)
private let t0 = Date(timeIntervalSince1970: 1_791_000_000)

private func member(_ n: Int, _ name: String) -> ClubMemberRow {
    ClubMemberRow(id: id(n), clubID: club, userID: UUID(), displayName: name, handicapIndex: nil, seedGroup: nil,
                  isOrganizer: false, isTreasurer: false, status: .active, avatarPath: nil)
}

private func signup(_ n: Int, _ status: SignupStatus, waiting: TimeInterval? = nil) -> SignupRow {
    SignupRow(eventID: eventID, memberID: id(n), clubID: club, status: status, comment: nil,
              waitlistedAt: waiting.map { t0.addingTimeInterval($0) })
}

private func guest(_ n: Int, _ name: String, by host: Int, waiting: TimeInterval? = nil) -> EventGuestRow {
    EventGuestRow(id: id(n), eventID: eventID, clubID: club, name: name, invitedBy: id(host),
                  waitlistedAt: waiting.map { t0.addingTimeInterval($0) })
}

private let roster = [member(1, "Anders"), member(2, "Bjørn"), member(3, "Cato"), member(4, "Dag"), member(5, "Erik")]

struct PameldingTellingTests {
    @Test func ventelistaTellerIkkeSomKommer() {
        let signups = [signup(1, .yes), signup(2, .yes, waiting: 10), signup(3, .maybe)]
        let summary = SignupSummary(members: roster, signups: signups)
        #expect(summary.yes.map(\.name) == ["Anders"])
        #expect(summary.waitlist.map(\.name) == ["Bjørn"])
        #expect(summary.coming == 1)
        #expect(summary.waitlistPlace(of: id(2)) == 1)
        #expect(summary.waitlistPlace(of: id(1)) == nil)
    }

    @Test func bekreftedeGjesterTellerMed() {
        let summary = SignupSummary(members: roster, signups: [signup(1, .yes)],
                                    guests: [guest(50, "Ola", by: 1), guest(51, "Kari", by: 1, waiting: 5)])
        #expect(summary.coming == 2)
        #expect(summary.guests.map(\.name) == ["Ola"])
        #expect(summary.guests.first?.detail == "gjest av Anders")
        #expect(summary.groups.first?.entries.map(\.name) == ["Anders", "Ola"])
    }

    @Test func ventelistaErMedlemmerOgGjesterEtterTid() {
        let summary = SignupSummary(members: roster,
                                    signups: [signup(2, .yes, waiting: 30), signup(3, .yes, waiting: 10)],
                                    guests: [guest(50, "Ola", by: 1, waiting: 20)])
        #expect(summary.waitlist.map(\.name) == ["Cato", "Ola", "Bjørn"])
        #expect(summary.waitlist.map(\.place) == [1, 2, 3])
        #expect(summary.waitlistPlace(of: id(2)) == 3)
        // Gjesten til Anders er ikke Anders sin plass.
        #expect(summary.waitlistPlace(of: id(1)) == nil)
        #expect(summary.waitlist[1].detail == "gjest av Anders · nr. 2 på ventelista")
    }

    @Test func ikkeSettOgIkkeSvartNaarDetErKjent() {
        let summary = SignupSummary(members: roster, signups: [signup(1, .yes)], seen: [id(2), id(1)])
        let titles = summary.groups.map(\.title)
        #expect(titles == ["Kommer", "Usikker", "Kommer ikke", "Ikke svart", "Ikke sett"])
        #expect(summary.notAnsweredSeen.map(\.name) == ["Bjørn"])
        #expect(summary.notSeen.map(\.name) == ["Cato", "Dag", "Erik"])
        #expect(Nudge.targets(summary).count == 4)
        // Uten «sett»: én gruppe som før.
        let before = SignupSummary(members: roster, signups: [signup(1, .yes)])
        #expect(before.groups.map(\.title) == ["Kommer", "Usikker", "Kommer ikke", "Ikke svart"])
        let waiting = SignupSummary(members: roster, signups: [signup(1, .yes, waiting: 1)])
        #expect(waiting.groups.map(\.title) == ["Kommer", "Venteliste", "Usikker", "Kommer ikke", "Ikke svart"])
    }

    @Test func purringenSierHvorMangeSomIkkeHarSett() {
        #expect(Nudge.unseenText(unseen: 0, of: 4) == nil)
        #expect(Nudge.unseenText(unseen: 2, of: 4) == "2 av dem har ikke sett kvelden ennå.")
        #expect(Nudge.unseenText(unseen: 3, of: 3) == "Ingen av dem har sett kvelden ennå.")
    }

    @Test func signupTextTellerUtenVentelistaOgMedGjester() {
        let signups = [signup(1, .yes), signup(2, .yes), signup(3, .yes, waiting: 1), signup(4, .maybe)]
        #expect(Tonight.signupText(signups, rosterCount: 5) == "2 av 5 kommer · 1 på venteliste · 1 usikker")
        #expect(Tonight.signupText(signups, guests: [guest(50, "Ola", by: 1), guest(51, "Kari", by: 2, waiting: 2)],
                                   rosterCount: 5)
                == "2 av 5 kommer + 1 gjest · 2 på venteliste · 1 usikker")
        #expect(Tonight.signupText([], guests: [], rosterCount: 5) == "Ingen har svart ennå · 5 i troppen")
    }

    @Test func rundenTarIkkeMedVentelista() {
        let (ids, source) = RoundParticipants.initial(roster: roster, signups: [signup(1, .yes), signup(2, .yes, waiting: 1)])
        #expect(ids == [id(1)])
        #expect(source == .signups)
        // Bare ventelista: ingen har plass, så alle står som med (som før).
        let (all, everyone) = RoundParticipants.initial(roster: roster, signups: [signup(2, .yes, waiting: 1)])
        #expect(all.count == roster.count)
        #expect(everyone == .everyone)
    }

    @Test func gammelRadUtenVentelistaLesesSomFoer() throws {
        let json = #"{"event_id":"00000000-0000-0000-0000-000000000101","member_id":"00000000-0000-0000-0000-000000000001","club_id":"00000000-0000-0000-0000-000000000999","status":"yes","comment":null}"#
        let row = try JSONDecoder().decode(SignupRow.self, from: Data(json.utf8))
        #expect(row.isConfirmed)
        #expect(!row.late)
    }
}

struct PameldingVisningTests {
    @Test func ventelisteTekst() {
        #expect(EveningSignupText.waitlist(place: 2) == "På venteliste (nr. 2)")
        #expect(EveningSignupText.waitlist(place: nil) == "På venteliste")
        #expect(EveningSignupText.capacity(coming: 14, max: 16, waitlist: 0) == "14 av 16 plasser")
        #expect(EveningSignupText.capacity(coming: 16, max: 16, waitlist: 2) == "16 av 16 plasser · 2 på venteliste")
        #expect(EveningSignupText.capacity(coming: 9, max: nil, waitlist: 0) == nil)
    }

    @Test func ventelistaBeholdesNaarDuSvarerKommerIgjen() {
        let saved = signup(9, .yes, waiting: 1)
        let pending = PendingAnswer(eventID: eventID, saved: saved, status: .yes, comment: nil, revision: 0)
        #expect(SignupUndo.displayed(saved: saved, pending: pending, memberID: id(9), clubID: club)?.isWaitlisted == true)
        let no = PendingAnswer(eventID: eventID, saved: saved, status: .no, comment: nil, revision: 0)
        #expect(SignupUndo.displayed(saved: saved, pending: no, memberID: id(9), clubID: club)?.waitlistedAt == nil)
        // I oversikten står du på ventelista til svaret er sendt.
        let rows = SignupUndo.signups([saved], pending: pending, memberID: id(9), clubID: club)
        #expect(rows.first?.isWaitlisted == true)
    }

    @Test func ingenPaameldingNaarSvaretHavnetPaaVentelista() {
        #expect(SignupNews.event(member: id(1), from: nil, to: .yes, eventDate: nil, waitlisted: true) == nil)
        #expect(SignupNews.event(member: id(1), from: nil, to: .yes, eventDate: nil)
                == .signup(member: id(1), status: .yes, eventDate: nil))
        // Fra ventelista (sendt inn som nil) til «Kommer ikke» er ingen nyhet.
        #expect(SignupNews.event(member: id(1), from: nil, to: .no, eventDate: nil) == nil)
    }

    @Test func loggLinjer() {
        let row = SignupLogRow(id: 1, eventID: eventID, memberID: id(1), guestName: nil, oldStatus: "yes",
                               newStatus: "no", changedAt: t0, note: "late")
        #expect(EveningSignupText.logLine(row) { $0 == id(1) ? "Anders" : nil } == "Anders: Kommer → Kommer ikke (etter fristen)")
        let guestRow = SignupLogRow(id: 2, eventID: eventID, memberID: id(1), guestName: "Ola", oldStatus: "none",
                                    newStatus: "waitlist", changedAt: t0, note: nil)
        #expect(EveningSignupText.logLine(guestRow) { _ in "Anders" } == "Ola (gjest av Anders): Ikke svart → Venteliste")
    }

    @Test func aktivitetFraServeren() {
        let names = [id(1): "Anders"]
        let promoted = ActivityText.display(.waitlistPromoted(member: id(1), guestName: nil, eventDate: "2026-10-08"),
                                            actor: nil) { names[$0] }
        #expect(promoted.text == "Du har fått plass torsdag 8. oktober")
        let guest = ActivityText.display(.waitlistPromoted(member: id(1), guestName: "Ola", eventDate: nil),
                                         actor: nil) { names[$0] }
        #expect(guest.text == "Ola har fått plass (gjesten din)")
        let dropped = ActivityText.display(.signupDropped(member: id(1), eventDate: "2026-10-08", late: true),
                                           actor: nil) { names[$0] }
        #expect(dropped.text == "Anders har meldt seg av torsdag 8. oktober etter fristen")
        #expect(ActivityEvent.signupDropped(member: id(1), eventDate: nil, late: false).category == .signup)
    }
}

struct PameldingFristTests {
    let now = t0
    func settings(signup: TimeInterval? = nil, withdraw: TimeInterval? = nil) -> EveningSettingsRow {
        EveningSettingsRow(id: eventID, maxPlayers: nil, signupDeadline: signup.map { t0.addingTimeInterval($0) },
                           withdrawDeadline: withdraw.map { t0.addingTimeInterval($0) }, allowGuests: false)
    }

    @Test func utenFristerEllerUten045StopperIngenting() {
        #expect(!SignupDeadline.blocks(nil, current: nil, new: .yes, now: now, isOrganizer: false))
        #expect(!SignupDeadline.blocks(settings(), current: signup(1, .yes), new: .no, now: now, isOrganizer: false))
    }

    @Test func paameldingsfristen() {
        let passed = settings(signup: -60)
        #expect(SignupDeadline.blocks(passed, current: nil, new: .yes, now: now, isOrganizer: false))
        #expect(SignupDeadline.blocks(passed, current: signup(1, .maybe), new: .yes, now: now, isOrganizer: false))
        // Å svare nei eller usikker etter påmeldingsfristen går.
        #expect(!SignupDeadline.blocks(passed, current: nil, new: .no, now: now, isOrganizer: false))
        // Arrangøren kan alltid.
        #expect(!SignupDeadline.blocks(passed, current: nil, new: .yes, now: now, isOrganizer: true))
        #expect(!SignupDeadline.blocks(settings(signup: 60), current: nil, new: .yes, now: now, isOrganizer: false))
    }

    @Test func avmeldingsfristenGjelderBareBekreftede() {
        let passed = settings(withdraw: -60)
        #expect(SignupDeadline.blocks(passed, current: signup(1, .yes), new: .no, now: now, isOrganizer: false))
        #expect(SignupDeadline.blocks(passed, current: signup(1, .yes), new: .maybe, now: now, isOrganizer: false))
        #expect(!SignupDeadline.blocks(passed, current: signup(1, .yes, waiting: 1), new: .no, now: now, isOrganizer: false))
        #expect(!SignupDeadline.blocks(passed, current: signup(1, .maybe), new: .no, now: now, isOrganizer: false))
    }

    @Test func gjestFrister() {
        #expect(SignupDeadline.blocksGuest(settings(signup: -1), adding: true, waitlisted: false, now: now, isOrganizer: false))
        #expect(!SignupDeadline.blocksGuest(settings(withdraw: -1), adding: false, waitlisted: true, now: now, isOrganizer: false))
        #expect(SignupDeadline.blocksGuest(settings(withdraw: -1), adding: false, waitlisted: false, now: now, isOrganizer: false))
    }

    @Test func ddb02BlirFristteksten() {
        let error = DataError.from(sqlState: "DDB02", message: "Fristen er ute. Kontakt arrangøren.")
        #expect(error == .invalid("Fristen er ute. Kontakt arrangøren."))
        #expect(EveningSignupText.answerError(error) == "Fristen er ute. Kontakt arrangøren.")
        #expect(EveningSignupText.answerError(.offline)
                == "Klarte ikke å lagre svaret. Ingen kontakt med serveren. Sjekk nettet og prøv igjen.")
        #expect(DataError.from(sqlState: "54000", message: "Grensen er nådd") == .invalid("Grensen er nådd"))
    }

    @Test func manglendeFunksjonGirReserven() {
        #expect(EveningSignupService.isMissing(code: "PGRST202"))
        #expect(EveningSignupService.isMissing(code: "42703"))
        #expect(!EveningSignupService.isMissing(code: "DDB02"))
        #expect(!EveningSignupService.isMissing(code: nil))
    }
}

struct PameldingInnstillingTests {
    @Test func altErAvSomStandard() {
        let draft = EveningRulesDraft(nil, eventDate: EveningDates.date(from: "2026-10-15")!)
        #expect(draft.settings(id: eventID) == .off(eventID))
        #expect(EveningDates.dateString(from: draft.signupDeadline) == "2026-10-14")
    }

    @Test func detSomErPaaLagres() {
        var draft = EveningRulesDraft()
        draft.hasMax = true
        draft.maxPlayers = 900
        draft.allowGuests = true
        let saved = draft.settings(id: eventID)
        #expect(saved.maxPlayers == 500)
        #expect(saved.allowGuests)
        #expect(saved.signupDeadline == nil)
        let back = EveningRulesDraft(saved, eventDate: .now)
        #expect(back.hasMax && back.maxPlayers == 500 && back.allowGuests && !back.hasSignupDeadline)
    }

    @Test func gjestenavn() throws {
        #expect(try GuestInput.clean("  Ola   Nordmann ").get() == "Ola Nordmann")
        #expect((try? GuestInput.clean("   ").get()) == nil)
        #expect((try? GuestInput.clean(String(repeating: "a", count: 61)).get()) == nil)
    }
}
