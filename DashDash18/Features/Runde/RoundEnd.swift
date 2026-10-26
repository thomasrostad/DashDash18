import Foundation
import GolfgutuCore

// «Ferdig? Avslutt runden» i føringen: når kortet er ført ferdig, får den som kan avslutte runden
// (eieren av en løs runde, arrangøren av en klubbrunde) en tydelig knapp. Spillere ser at kortet er
// ferdig. Ren logikk over `RoundGame`, uten nettverk og SwiftUI (RundeAvslutningTests).

/// Det den som kan avslutte, får se og bekrefte.
nonisolated struct RoundEndOffer: Equatable, Sendable {
    /// Løs runde (`finish_loose_round`): invitasjonen slutter også å virke.
    let isLoose: Bool
    /// Hull som mangler på kortet ditt (0 når alt er ført, eller når du ikke spiller).
    let myMissingHoles: Int
    /// Grupper som ikke er ferdige: flighter/båser, og spillere uten gruppe hver for seg.
    let unfinishedGroups: Int
    let unfinishedPlayers: Int
    let groupTerm: GroupTerm

    /// Noen har ikke ført alle hullene. Da kommer en ekstra bekreftelse.
    var hasUnfinished: Bool { unfinishedGroups + unfinishedPlayers > 0 }

    static let buttonTitle = "Ferdig? Avslutt runden"
    static let menuTitle = "Avslutt runden …"
    static let confirmTitle = "Avslutte runden?"
    static let confirmButton = "Avslutt runden"
    static let extraButton = "Avslutt likevel"

    /// «2 flighter er ikke ferdige», «1 spiller er ikke ferdig», «1 bås og 2 spillere er ikke ferdige».
    var unfinishedText: String? {
        var parts: [String] = []
        if unfinishedGroups > 0 { parts.append(groupTerm.count(unfinishedGroups)) }
        if unfinishedPlayers > 0 { parts.append(unfinishedPlayers == 1 ? "1 spiller" : "\(unfinishedPlayers) spillere") }
        guard !parts.isEmpty else { return nil }
        let one = unfinishedGroups + unfinishedPlayers == 1
        return parts.joined(separator: " og ") + (one ? " er ikke ferdig" : " er ikke ferdige")
    }

    /// Linja over knappen.
    var statusText: String {
        var parts: [String] = []
        if myMissingHoles > 0 {
            parts.append(myMissingHoles == 1 ? "1 hull mangler på kortet ditt." : "\(myMissingHoles) hull mangler på kortet ditt.")
        }
        if let unfinishedText {
            parts.append(unfinishedText + ".")
        } else if myMissingHoles == 0 {
            parts.append("Alle hullene er ført.")
        }
        return parts.joined(separator: " ")
    }

    /// Hva som skjer når runden avsluttes.
    var confirmMessage: String {
        var text = "Runden låses, og resultatet står. Ingen kan føre mer."
        if isLoose { text += " Invitasjonen slutter å virke." }
        if hasUnfinished || myMissingHoles > 0 { text = statusText + " " + text }
        return text
    }

    /// Den ekstra bekreftelsen når noen ikke er ferdige. nil: ingen.
    var extraConfirm: (title: String, message: String)? {
        guard let unfinishedText else { return nil }
        return (unfinishedText, "Hullene de ikke har ført, står tomme i resultatet. Vil du avslutte runden likevel?")
    }
}

/// Det føringen viser når kortet er ført ferdig.
nonisolated enum RoundEndPrompt: Equatable, Sendable {
    /// «Ferdig? Avslutt runden» for den som kan avslutte.
    case offer(RoundEndOffer)
    /// Spilleren: «Kortet ditt er ferdig». Den som kan avslutte, gjør det.
    case cardDone(isLoose: Bool)

    static let cardDoneTitle = "Kortet ditt er ferdig"

    var cardDoneText: String {
        guard case .cardDone(let isLoose) = self else { return "" }
        return isLoose
            ? "Alle hullene er ført. Den som startet runden, avslutter den."
            : "Alle hullene er ført. Arrangøren avslutter runden."
    }
}

nonisolated extension RoundGame {
    /// Hullene som teller (avkortet runde: til og med kuttet).
    private var endCountingHoles: Int { max(1, min(holeCount, Truncation.countingHoles(round))) }

    /// Spilleren har ført alle tellende hull.
    private func hasFinished(_ member: UUID) -> Bool {
        let s = scores(member)
        return (0..<endCountingHoles).allSatisfy { s[$0] != nil }
    }

    /// Alle tellende hull er ført for kortet ditt. Usant når du ikke har et kort (arrangøren ser på).
    func isCardFinished(for viewer: Viewer) -> Bool {
        let card = cardPlayers(for: viewer)
        return !card.isEmpty && (0..<endCountingHoles).allSatisfy { isComplete(hole: $0, for: card) }
    }

    /// Avslutningen for den som kan avslutte (også fra ⋯-menyen, før kortet er ferdig).
    /// nil når runden ikke går, eller du ikke kan avslutte.
    func endOffer(viewer: Viewer, canEnd: Bool, isLoose: Bool) -> RoundEndOffer? {
        guard canEnd, status == .active else { return nil }
        let card = cardPlayers(for: viewer)
        let counting = endCountingHoles
        let myMissing = card.isEmpty ? 0 : (0..<counting).filter { !isComplete(hole: $0, for: card) }.count
        var groups = 0
        for bay in bays.values where !bay.players.allSatisfy(hasFinished) { groups += 1 }
        let withoutGroup = snapshot.players.filter { p in p.bayNo.map { $0 < 1 } ?? true }.map(\.memberID)
        let players = withoutGroup.filter { !hasFinished($0) }.count
        return RoundEndOffer(isLoose: isLoose, myMissingHoles: myMissing, unfinishedGroups: groups,
                             unfinishedPlayers: players, groupTerm: groupTerm)
    }

    /// Det føringen viser nederst: når alle hullene på kortet ditt er ført, eller du står på siste
    /// tellende hull og det er ført. Spiller du ikke (arrangøren ser på): når minst én er ferdig.
    /// nil før par er bekreftet, mens hull ligger i kø, og når runden ikke går.
    /// Med låst kort etter levering (`play.lockSubmittedCards`) viser «Lever kortet» seg for spillerne
    /// i stedet (`cardSubmission`).
    func endPrompt(viewer: Viewer, canEnd: Bool, isLoose: Bool, pending: Set<Int>, currentHole: Int,
                   cardLockAvailable: Bool = CardLockFeature.isAvailable) -> RoundEndPrompt? {
        guard status == .active, snapshot.round.parConfirmedAt != nil, pending.isEmpty else { return nil }
        let card = cardPlayers(for: viewer)
        let last = endCountingHoles - 1
        let triggered: Bool
        let allDone: Bool
        if card.isEmpty {
            allDone = false
            triggered = canEnd && snapshot.players.contains { hasFinished($0.memberID) }
        } else {
            allDone = (0...last).allSatisfy { isComplete(hole: $0, for: card) }
            triggered = allDone || (currentHole >= last && isComplete(hole: last, for: card))
        }
        guard triggered else { return nil }
        if let offer = endOffer(viewer: viewer, canEnd: canEnd, isLoose: isLoose) { return .offer(offer) }
        if cardLockAvailable && rules.play.lockSubmittedCards { return nil }
        return allDone ? .cardDone(isLoose: isLoose) : nil
    }
}
