import Foundation
import Supabase
import Testing
@testable import DashDash18

/// Fixturen `DiagnosticsFixture.json`: en `MXDiagnosticPayload.jsonRepresentation()` i Apples
/// format med to krasj og ett heng.
enum DiagnosticsFixture {
    private final class BundleToken {}

    static func data() throws -> Data {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "DiagnosticsFixture", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    static func record(_ n: Int, kind: DiagnosticKind = .crash) -> DiagnosticRecord {
        DiagnosticRecord(id: UUID(), kind: kind, signature: "s\(n)", appVersion: "1.0", build: "\(n)",
                         osVersion: nil, deviceModel: nil, payload: .object([:]), environment: "test")
    }
}

struct DiagnosticsMappingTests {
    private func records() throws -> [DiagnosticRecord] {
        DiagnosticsMapping.records(payloadJSON: try DiagnosticsFixture.data(), appBinaryName: "DashDash18",
                                   environment: .prod)
    }

    @Test func enRadPerDiagnose() throws {
        let rows = try records()
        #expect(rows.map(\.kind) == [.crash, .crash, .hang])
        #expect(Set(rows.map(\.id)).count == 3)
        #expect(rows.allSatisfy { $0.environment == "prod" })
    }

    @Test func krasjMedSignalOgAppRamme() throws {
        let crash = try records()[0]
        // Tråden med skylda, og den øverste rammen fra appen (ikke libswiftCore over den).
        #expect(crash.signature == "EXC_BAD_ACCESS (SIGSEGV) · DashDash18+0x1a2b")
        #expect(crash.appVersion == "1.0")
        #expect(crash.build == "42")
        #expect(crash.osVersion == "iPhone OS 26.0.1 (23A355)")
        #expect(crash.deviceModel == "iPhone17,1")
    }

    @Test func objectiveCUnntakUtenAppRamme() throws {
        let crash = try records()[1]
        // Ingen ramme fra appen: den øverste rammen brukes.
        #expect(crash.signature == "NSRangeException · EXC_CRASH (SIGABRT) · CoreFoundation+0x800")
    }

    @Test func hengMedVarighet() throws {
        let hang = try records()[2]
        #expect(hang.signature == "hang 3 sec · DashDash18+0xff")
        #expect(hang.appVersion == "1.0.1")
        #expect(hang.build == "43")
        #expect(hang.deviceModel == "iPhone18,2")
    }

    @Test func payloadHarBareDenEneDiagnosen() throws {
        let hang = try records()[2]
        let object = try #require(hang.payload.objectValue)
        #expect(object["timeStampBegin"]?.stringValue == "2026-10-19 00:00:00")
        #expect(object["hangDiagnostics"]?.arrayValue?.count == 1)
        #expect(object["crashDiagnostics"] == nil)
        let meta = object["hangDiagnostics"]?.arrayValue?.first?.objectValue?["diagnosticMetaData"]?.objectValue
        #expect(meta?["hangDuration"]?.stringValue == "3 sec")
    }

    @Test func ugyldigJSONGirIngenRader() {
        #expect(DiagnosticsMapping.records(payloadJSON: Data("ikke json".utf8), appBinaryName: "DashDash18",
                                           environment: .test).isEmpty)
        #expect(DiagnosticsMapping.records(payloadJSON: Data("[]".utf8), appBinaryName: "DashDash18",
                                           environment: .test).isEmpty)
    }

    @Test func signaturKuttesTil300Tegn() {
        let long = String(repeating: "x", count: 500)
        let cut = DiagnosticsMapping.truncate(long, to: 300)
        #expect(cut.count == 300)
        #expect(cut.hasSuffix("…"))
        #expect(DiagnosticsMapping.truncate("kort", to: 300) == "kort")
        #expect(DiagnosticsMapping.truncate(String(repeating: "y", count: 300), to: 300).count == 300)

        let diagnostic: JSONObject = [
            "diagnosticMetaData": .object(["objectiveCexceptionReason": .object(["exceptionName": .string(long)])]),
        ]
        let signature = DiagnosticsMapping.signature(kind: .crash, diagnostic: diagnostic, appBinaryName: "DashDash18")
        #expect(signature.count == DiagnosticsMapping.signatureLimit)
        #expect(signature.hasSuffix("…"))
    }

    @Test func forStorPayloadMisterKallstakken() {
        let frames: [AnyJSON] = (0..<4000).map { i in
            .object(["binaryName": .string("DashDash18"), "offsetIntoBinaryTextSegment": .integer(i),
                     "binaryUUID": .string(UUID().uuidString)])
        }
        let diagnostic: JSONObject = [
            "callStackTree": .object(["callStacks": .array([.object(["threadAttributed": .bool(true),
                                                                     "callStackRootFrames": .array(frames)])])]),
            "diagnosticMetaData": .object(["hangDuration": .string("9 sec")]),
        ]
        let payload = DiagnosticsMapping.payload(kind: .hang, diagnostic: diagnostic, root: [:])
        #expect(DiagnosticsMapping.byteCount(payload) <= DiagnosticsMapping.payloadLimit)
        let kept = payload.objectValue?["hangDiagnostics"]?.arrayValue?.first?.objectValue
        #expect(kept?["callStackTree"]?.objectValue?["truncated"] == .bool(true))
        #expect(kept?["diagnosticMetaData"]?.objectValue?["hangDuration"] == .string("9 sec"))
    }

    @Test func radenSendesMedServerensFeltnavn() throws {
        let record = DiagnosticsFixture.record(1)
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        #expect(Set(object.keys).isSuperset(of: ["kind", "signature", "app_version", "build", "payload", "environment"]))
        #expect(object["kind"] as? String == "crash")
    }
}

struct DiagnosticsQueueTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "Feilrapporter-\(UUID().uuidString).json")
    }

    @Test func eldsteKastesOverGrensen() {
        let old = (0..<48).map { DiagnosticsFixture.record($0) }
        let new = (48..<55).map { DiagnosticsFixture.record($0) }
        let result = DiagnosticsQueue.appending(new, to: old, limit: 50)
        #expect(result.count == 50)
        #expect(result.first?.build == "5")
        #expect(result.last?.build == "54")
    }

    @Test func sammeIdLeggesIkkeInnToGanger() {
        let record = DiagnosticsFixture.record(1)
        #expect(DiagnosticsQueue.appending([record], to: [record], limit: 50).count == 1)
    }

    @Test func lagresIFilOgFjernes() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let queue = DiagnosticsQueue(fileURL: url, limit: 3)
        let records = (0..<5).map { DiagnosticsFixture.record($0) }
        await queue.append(records)
        #expect(await queue.load().map(\.build) == ["2", "3", "4"])
        // En ny kø på samme fil leser det som ble lagret.
        #expect(await DiagnosticsQueue(fileURL: url).load().count == 3)
        await queue.remove(ids: [records[3].id])
        #expect(await queue.load().map(\.build) == ["2", "4"])
        await queue.remove(ids: Set(records.map(\.id)))
        #expect(await queue.load().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path()))
    }

    @Test func manglendeEllerØdelagtFilGirTomKø() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(await DiagnosticsQueue(fileURL: url).load().isEmpty)
        try Data("tull".utf8).write(to: url)
        #expect(await DiagnosticsQueue(fileURL: url).load().isEmpty)
    }
}

/// Sender uten nett. `mode` styrer svaret.
final class FakeDiagnosticsSender: DiagnosticsSending, @unchecked Sendable {
    enum Mode { case ok, fail, partial }
    private let lock = NSLock()
    private var _mode: Mode = .ok
    private var _batches: [[DiagnosticRecord]] = []

    var mode: Mode {
        get { lock.withLock { _mode } }
        set { lock.withLock { _mode = newValue } }
    }

    var batches: [[DiagnosticRecord]] { lock.withLock { _batches } }

    func send(_ records: [DiagnosticRecord]) async throws -> Int {
        let mode = lock.withLock {
            _batches.append(records)
            return _mode
        }
        switch mode {
        case .ok: return records.count
        case .partial: return records.count - 1
        case .fail: throw URLError(.notConnectedToInternet)
        }
    }
}

@MainActor
struct DiagnosticsReporterTests {
    private func make(_ sender: FakeDiagnosticsSender) -> (DiagnosticsReporter, DiagnosticsQueue, URL) {
        let url = FileManager.default.temporaryDirectory.appending(path: "Feilrapporter-\(UUID().uuidString).json")
        let queue = DiagnosticsQueue(fileURL: url)
        let reporter = DiagnosticsReporter(sender: sender, queue: queue, environment: .test, appBinaryName: "DashDash18")
        return (reporter, queue, url)
    }

    @Test func venterTilNoenErInnlogget() async throws {
        let sender = FakeDiagnosticsSender()
        let (reporter, queue, url) = make(sender)
        defer { try? FileManager.default.removeItem(at: url) }
        await reporter.receive(payloadJSON: [try DiagnosticsFixture.data()])
        #expect(sender.batches.isEmpty)
        #expect(await queue.load().count == 3)

        await reporter.start(userID: UUID())
        #expect(sender.batches.map(\.count) == [3])
        #expect(await queue.load().isEmpty)
    }

    @Test func feiletSendingLarRadeneLigge() async throws {
        let sender = FakeDiagnosticsSender()
        sender.mode = .fail
        let (reporter, queue, url) = make(sender)
        defer { try? FileManager.default.removeItem(at: url) }
        await reporter.start(userID: UUID())
        await reporter.receive(payloadJSON: [try DiagnosticsFixture.data()])
        #expect(sender.batches.count == 1)
        #expect(await queue.load().count == 3)

        // Delvis svar tømmer heller ikke køen.
        sender.mode = .partial
        await reporter.flush()
        #expect(await queue.load().count == 3)

        sender.mode = .ok
        await reporter.flush()
        #expect(await queue.load().isEmpty)
    }

    @Test func sendesIBolkerPaTjue() async throws {
        let sender = FakeDiagnosticsSender()
        let (reporter, queue, url) = make(sender)
        defer { try? FileManager.default.removeItem(at: url) }
        await queue.append((0..<45).map { DiagnosticsFixture.record($0) })
        await reporter.start(userID: UUID())
        #expect(sender.batches.map(\.count) == [20, 20, 5])
        #expect(await queue.load().isEmpty)
    }

    @Test func delvisSvarStopperSendingen() async throws {
        let sender = FakeDiagnosticsSender()
        let (reporter, queue, url) = make(sender)
        defer { try? FileManager.default.removeItem(at: url) }
        await queue.append((0..<30).map { DiagnosticsFixture.record($0) })
        sender.mode = .partial
        await reporter.start(userID: UUID())
        #expect(sender.batches.count == 1)
        #expect(await queue.load().count == 30)
    }

    @Test func utloggetSenderIkke() async throws {
        let sender = FakeDiagnosticsSender()
        let (reporter, queue, url) = make(sender)
        defer { try? FileManager.default.removeItem(at: url) }
        await reporter.start(userID: UUID())
        reporter.stop()
        await reporter.receive(payloadJSON: [try DiagnosticsFixture.data()])
        #expect(sender.batches.isEmpty)
        #expect(await queue.load().count == 3)
    }
}
