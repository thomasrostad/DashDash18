import Foundation
import Observation
import WatchConnectivity
import WatchKit

/// Runden på klokka: det telefonen sist sendte, og hullene klokka har sendt som telefonen ikke har
/// bekreftet ennå. Klokka regner ingenting selv (WatchRound.swift): tallene og tekstene kommer fra
/// hullkortet på telefonen, og hullene går i utboksen der.
@Observable
final class WatchModel {
    private(set) var round: WatchRound?
    /// Sendt fra klokka, ikke bekreftet av en nyere runde fra telefonen. Lagres, så de står også
    /// etter at klokkeappen er startet på nytt.
    private(set) var outgoing: [WatchOutgoing] = []
    /// Hullet som vises (rundens 0-baserte).
    private(set) var hole = 0
    /// Tall klokka har endret på hullet som vises, før det er sendt.
    private(set) var drafts: [UUID: Int] = [:]
    /// Raden Digital Crown endrer.
    var selected: UUID?

    private var delegate: WatchSessionDelegate?
    /// Hullet båsen sto på da runden sist kom: står klokka der, følger den med til neste.
    private var followedHole: Int?

    private static let roundKey = "watchRound"
    private static let outgoingKey = "watchOutgoing"

    func activate() {
        guard delegate == nil else { return }
        restore()
        guard WCSession.isSupported() else { return }
        let delegate = WatchSessionDelegate(
            received: { [weak self] round in Task { @MainActor in self?.receive(round) } },
            delivered: { [weak self] entry, at in Task { @MainActor in self?.delivered(entry, at: at) } }
        )
        self.delegate = delegate
        WCSession.default.delegate = delegate
        WCSession.default.activate()
    }

    // MARK: Hullet som vises

    var currentHole: WatchRound.Hole? {
        round?.holes.first { $0.index == hole }
    }

    /// Tallet som står: utkastet, ellers det klokka har sendt, ellers telefonens.
    func value(_ row: WatchRound.Row) -> Int {
        drafts[row.memberID] ?? round?.value(hole: hole, member: row.memberID, outgoing: outgoing) ?? row.value
    }

    /// Står på forvalget (par) uten at noen har tastet: vises dempet, som på telefonen.
    func isDefault(_ row: WatchRound.Row) -> Bool {
        row.editable && row.saved == nil && drafts[row.memberID] == nil && !isSent(row)
    }

    /// Hull klokka har sendt som ikke er kommet fram til telefonen.
    var waitingCount: Int {
        Set(outgoing.filter { $0.deliveredAt == nil }.map(\.entry.holeIndex)).count
    }

    func set(_ strokes: Int, for row: WatchRound.Row) {
        guard row.editable else { return }
        drafts[row.memberID] = row.clamp(strokes)
    }

    /// Alle radene klokka fører på hullet, er lagret eller sendt fra klokka.
    var isCurrentHoleDone: Bool {
        guard let current = currentHole else { return false }
        return current.rows.filter(\.editable).allSatisfy { $0.saved != nil || isSent($0) }
    }

    /// Knappen: «Lagre hull N», eller «Neste hull» når hullet er lagret og ingenting er endret.
    var primaryTitle: String {
        guard let current = currentHole else { return "" }
        return isCurrentHoleDone && drafts.isEmpty ? "Neste hull" : "Lagre hull \(current.number)"
    }

    func primaryAction() {
        if isCurrentHoleDone && drafts.isEmpty {
            go(to: hole + 1)
        } else {
            save()
        }
    }

    func go(to index: Int) {
        guard let round, round.holes.contains(where: { $0.index == index }) else { return }
        hole = index
        drafts = [:]
        selected = defaultSelection()
    }

    /// «Lagre hull N»: alle radene klokka fører, med tallene som står (urørte som par, som på
    /// telefonen). Telefonen legger hullet i utboksen. Klokka går videre til neste hull.
    func save() {
        guard let round, let current = currentHole else { return }
        let scores = current.rows.filter(\.editable).map { WatchHoleEntry.Score(memberID: $0.memberID, strokes: value($0)) }
        guard !scores.isEmpty else { return }
        let entry = WatchHoleEntry(roundID: round.roundID, holeIndex: hole, scores: scores, recordedAt: .now)
        outgoing.append(WatchOutgoing(entry: entry))
        persist()
        if WCSession.isSupported(), let payload = WatchMessage.payload(entry, key: WatchMessage.hole) {
            WCSession.default.transferUserInfo(payload)
        }
        WKInterfaceDevice.current().play(.success)
        let next = hole + 1
        go(to: round.holes.contains { $0.index == next } ? next : hole)
    }

    // MARK: Fra telefonen

    private func receive(_ round: WatchRound?) {
        let previous = self.round
        self.round = round
        outgoing = WatchRound.keeping(outgoing, round: round)
        persist()
        guard let round else { return }
        if previous?.roundID != round.roundID {
            go(to: round.currentHole)
        } else if hole == followedHole, drafts.isEmpty {
            go(to: round.currentHole)
        }
        followedHole = round.currentHole
        if selected == nil || currentHole?.rows.contains(where: { $0.memberID == selected }) != true {
            selected = defaultSelection()
        }
    }

    private func delivered(_ entry: WatchHoleEntry, at date: Date) {
        // Tiden går via millisekunder i meldingen, så den sammenlignes med en liten margin.
        guard let i = outgoing.firstIndex(where: {
            $0.entry.roundID == entry.roundID && $0.entry.holeIndex == entry.holeIndex
                && $0.entry.scores == entry.scores
                && abs($0.entry.recordedAt.timeIntervalSince(entry.recordedAt)) < 0.01
        }) else { return }
        outgoing[i].deliveredAt = date
        persist()
    }

    private func isSent(_ row: WatchRound.Row) -> Bool {
        outgoing.contains { $0.entry.holeIndex == hole && $0.entry.scores.contains { $0.memberID == row.memberID } }
    }

    /// Din egen rad når du fører den, ellers den første klokka kan føre.
    private func defaultSelection() -> UUID? {
        let editable = currentHole?.rows.filter(\.editable) ?? []
        return (editable.first { $0.isMe } ?? editable.first)?.memberID
    }

    // MARK: Lagring

    private func restore() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.outgoingKey),
           let saved = try? JSONDecoder().decode([WatchOutgoing].self, from: data) {
            outgoing = saved
        }
        if let data = defaults.data(forKey: Self.roundKey),
           let saved = try? JSONDecoder().decode(WatchRound.self, from: data) {
            receive(saved)
        }
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(try? JSONEncoder().encode(outgoing), forKey: Self.outgoingKey)
        defaults.set(round.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.roundKey)
    }
}

/// WatchConnectivity kaller på en egen kø. Meldingen pakkes ut her, og bare verdier sendes videre.
private nonisolated final class WatchSessionDelegate: NSObject, WCSessionDelegate {
    private let received: @Sendable (WatchRound?) -> Void
    private let delivered: @Sendable (WatchHoleEntry, Date) -> Void

    init(received: @escaping @Sendable (WatchRound?) -> Void,
         delivered: @escaping @Sendable (WatchHoleEntry, Date) -> Void) {
        self.received = received
        self.delivered = delivered
    }

    /// Runden som kom mens klokkeappen var lukket, ligger i den siste konteksten.
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?) {
        guard state == .activated, !session.receivedApplicationContext.isEmpty else { return }
        received(WatchMessage.value(WatchRound.self, key: WatchMessage.round, in: session.receivedApplicationContext))
    }

    /// Tom kontekst: ingen runde (låst, eller logget ut på telefonen).
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        received(WatchMessage.value(WatchRound.self, key: WatchMessage.round, in: applicationContext))
    }

    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: (any Error)?) {
        guard error == nil,
              let entry = WatchMessage.value(WatchHoleEntry.self, key: WatchMessage.hole, in: userInfoTransfer.userInfo)
        else { return }
        delivered(entry, .now)
    }
}
