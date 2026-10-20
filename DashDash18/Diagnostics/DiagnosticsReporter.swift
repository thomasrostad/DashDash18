import Foundation
import MetricKit
import Supabase

/// Sender rader til serveren. Byttes ut i testene.
protocol DiagnosticsSending: Sendable {
    /// Gir antall rader serveren la inn.
    func send(_ records: [DiagnosticRecord]) async throws -> Int
}

nonisolated private struct SubmitDiagnosticsParams: Encodable, Sendable {
    let p_items: [DiagnosticRecord]
}

/// `submit_diagnostics` (sql/064). Bare for den som er innlogget.
nonisolated struct SupabaseDiagnosticsSender: DiagnosticsSending {
    let client: SupabaseClient

    func send(_ records: [DiagnosticRecord]) async throws -> Int {
        try await client.rpc("submit_diagnostics", params: SubmitDiagnosticsParams(p_items: records)).execute().value
    }
}

/// Tar imot fra MetricKit. MetricKit kaller fra en bakgrunnstråd, så denne er ikke på
/// MainActor: den henter bare ut JSON-en og gir den videre.
nonisolated final class MetricKitSubscriber: NSObject, MXMetricManagerSubscriber, Sendable {
    private let handler: @Sendable ([Data]) -> Void

    init(handler: @escaping @Sendable ([Data]) -> Void) {
        self.handler = handler
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        handler(payloads.map { $0.jsonRepresentation() })
    }
}

/// Feilsporing (fase 17): krasj, heng, CPU, disk og treg oppstart fra MetricKit.
///
/// - Diagnosene blir rader (`DiagnosticsMapping`) og legges i køen på telefonen (`DiagnosticsQueue`).
/// - Køen sendes med `submit_diagnostics` når noen er innlogget: ved oppstart, når appen blir
///   aktiv og når det kommer nye diagnoser. Rader fjernes bare når serveren har tatt imot dem.
/// - Feiler sendingen (f.eks. uten 064 eller uten nett), blir radene liggende. Ingen feilmelding.
/// - Gjør ingenting når `DiagnosticsFeature` er av.
final class DiagnosticsReporter {
    static let batchSize = 20

    private let queue: DiagnosticsQueue
    private let sender: any DiagnosticsSending
    private let environment: AppEnvironment
    private let appBinaryName: String
    private var subscriber: MetricKitSubscriber?
    private var userID: UUID?
    private var isSending = false

    init(sender: any DiagnosticsSending,
         queue: DiagnosticsQueue = DiagnosticsQueue(),
         environment: AppEnvironment = .current,
         appBinaryName: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String ?? "DashDash18") {
        self.sender = sender
        self.queue = queue
        self.environment = environment
        self.appBinaryName = appBinaryName
    }

    /// Abonnerer på MetricKit. Kalles én gang ved oppstart, så diagnosene fra forrige kjøring kommer.
    func subscribe() {
        guard DiagnosticsFeature.isEnabled, subscriber == nil else { return }
        let subscriber = MetricKitSubscriber { [weak self] payloads in
            Task { @MainActor in await self?.receive(payloadJSON: payloads) }
        }
        self.subscriber = subscriber
        MXMetricManager.shared.add(subscriber)
    }

    /// Etter innlogging: send det som ligger i køen.
    func start(userID: UUID) async {
        guard DiagnosticsFeature.isEnabled else { return }
        self.userID = userID
        await flush()
    }

    func stop() {
        userID = nil
    }

    /// JSON fra `MXDiagnosticPayload.jsonRepresentation()`: inn i køen, og send hvis noen er innlogget.
    func receive(payloadJSON payloads: [Data]) async {
        guard DiagnosticsFeature.isEnabled else { return }
        let records = payloads.flatMap {
            DiagnosticsMapping.records(payloadJSON: $0, appBinaryName: appBinaryName, environment: environment)
        }
        await queue.append(records)
        await flush()
    }

    /// Sender køen i bolker på `batchSize`. Stopper ved første feil; resten venter til neste gang.
    func flush() async {
        guard DiagnosticsFeature.isEnabled, userID != nil, !isSending else { return }
        isSending = true
        defer { isSending = false }
        let pending = await queue.load()
        for start in stride(from: 0, to: pending.count, by: Self.batchSize) {
            let batch = Array(pending[start..<min(start + Self.batchSize, pending.count)])
            do {
                let inserted = try await sender.send(batch)
                // Sjekk svaret (CLAUDE.md): bare et fullt ja tømmer bolken.
                guard inserted == batch.count else { return }
                await queue.remove(ids: Set(batch.map(\.id)))
            } catch {
                return
            }
            guard userID != nil else { return }
        }
    }
}
