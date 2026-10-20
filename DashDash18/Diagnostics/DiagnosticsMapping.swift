import Foundation
import Supabase

/// Gjør JSON-en fra `MXDiagnosticPayload.jsonRepresentation()` om til rader. Ren logikk, så den
/// kan testes med en fixture (MetricKit leverer ikke i simulatoren).
nonisolated enum DiagnosticsMapping {
    /// Grensene i `public.app_diagnostics` (sql/064).
    static let signatureLimit = 300
    static let appVersionLimit = 40
    static let buildLimit = 40
    static let osVersionLimit = 120
    static let deviceModelLimit = 60
    /// Litt under 200 kB på serveren, så JSON-en der (jsonb) også holder seg under.
    static let payloadLimit = 190_000

    /// Én rad per diagnose i payloaden. Ugyldig JSON gir ingen rader.
    static func records(payloadJSON data: Data,
                        appBinaryName: String,
                        environment: AppEnvironment,
                        makeID: () -> UUID = { UUID() }) -> [DiagnosticRecord] {
        guard let root = (try? JSONDecoder().decode(AnyJSON.self, from: data))?.objectValue else { return [] }
        var records: [DiagnosticRecord] = []
        for kind in DiagnosticKind.allCases {
            for item in root[kind.payloadKey]?.arrayValue ?? [] {
                guard let diagnostic = item.objectValue else { continue }
                let meta = diagnostic["diagnosticMetaData"]?.objectValue ?? [:]
                records.append(DiagnosticRecord(
                    id: makeID(),
                    kind: kind,
                    signature: signature(kind: kind, diagnostic: diagnostic, appBinaryName: appBinaryName),
                    appVersion: text(meta["appVersion"], limit: appVersionLimit),
                    build: text(meta["appBuildVersion"], limit: buildLimit),
                    osVersion: text(meta["osVersion"], limit: osVersionLimit),
                    deviceModel: text(meta["deviceType"], limit: deviceModelLimit),
                    payload: payload(kind: kind, diagnostic: diagnostic, root: root),
                    environment: environment.rawValue
                ))
            }
        }
        return records
    }

    // MARK: - Signatur

    /// F.eks. «EXC_BAD_ACCESS (SIGSEGV) · DashDash18+0x1a2b» eller «hang 3 sec · DashDash18+0x10».
    static func signature(kind: DiagnosticKind, diagnostic: JSONObject, appBinaryName: String) -> String {
        let meta = diagnostic["diagnosticMetaData"]?.objectValue ?? [:]
        let head: String = switch kind {
        case .crash: crashHead(meta)
        case .hang: measured("hang", meta["hangDuration"])
        case .cpu: measured("cpu", meta["totalCPUTime"])
        case .disk: measured("disk", meta["writesCaused"])
        case .launch: measured("launch", meta["launchDuration"])
        }
        let frame = topFrame(diagnostic["callStackTree"], appBinaryName: appBinaryName) ?? "no frame"
        return truncate("\(head) · \(frame)", to: signatureLimit)
    }

    /// Unntaket fra Objective-C (når det finnes), Mach-unntaket og signalet.
    static func crashHead(_ meta: JSONObject) -> String {
        var parts: [String] = []
        if let reason = meta["objectiveCexceptionReason"]?.objectValue,
           let name = (reason["exceptionName"] ?? reason["exceptionType"])?.stringValue, !name.isEmpty {
            parts.append(name)
        }
        let mach = meta["exceptionType"]?.intValue.map(machExceptionName)
        let signal = meta["signal"]?.intValue.map(signalName)
        switch (mach, signal) {
        case let (mach?, signal?): parts.append("\(mach) (\(signal))")
        case let (mach?, nil): parts.append(mach)
        case let (nil, signal?): parts.append(signal)
        case (nil, nil):
            if let reason = meta["terminationReason"]?.stringValue, !reason.isEmpty { parts.append(reason) }
        }
        return parts.isEmpty ? "crash" : parts.joined(separator: " · ")
    }

    static func machExceptionName(_ type: Int) -> String {
        switch type {
        case 1: "EXC_BAD_ACCESS"
        case 2: "EXC_BAD_INSTRUCTION"
        case 3: "EXC_ARITHMETIC"
        case 4: "EXC_EMULATION"
        case 5: "EXC_SOFTWARE"
        case 6: "EXC_BREAKPOINT"
        case 7: "EXC_SYSCALL"
        case 8: "EXC_MACH_SYSCALL"
        case 9: "EXC_RPC_ALERT"
        case 10: "EXC_CRASH"
        case 11: "EXC_RESOURCE"
        case 12: "EXC_GUARD"
        case 13: "EXC_CORPSE_NOTIFY"
        default: "EXC_\(type)"
        }
    }

    static func signalName(_ signal: Int) -> String {
        switch signal {
        case 1: "SIGHUP"
        case 2: "SIGINT"
        case 3: "SIGQUIT"
        case 4: "SIGILL"
        case 5: "SIGTRAP"
        case 6: "SIGABRT"
        case 7: "SIGEMT"
        case 8: "SIGFPE"
        case 9: "SIGKILL"
        case 10: "SIGBUS"
        case 11: "SIGSEGV"
        case 12: "SIGSYS"
        case 13: "SIGPIPE"
        case 14: "SIGALRM"
        case 15: "SIGTERM"
        default: "SIG\(signal)"
        }
    }

    /// Øverste ramme fra appen i tråden som fikk skylda (`threadAttributed`), ellers den første
    /// tråden. Finnes ingen ramme fra appen, brukes den øverste rammen uansett bibliotek.
    /// MetricKit symboliserer ikke, så rammen er binæren og forskyvningen: «DashDash18+0x1a2b».
    static func topFrame(_ callStackTree: AnyJSON?, appBinaryName: String) -> String? {
        let stacks = callStackTree?.objectValue?["callStacks"]?.arrayValue?.compactMap(\.objectValue) ?? []
        guard let stack = stacks.first(where: { $0["threadAttributed"]?.boolValue == true }) ?? stacks.first else {
            return nil
        }
        let frames = flatten(stack["callStackRootFrames"]?.arrayValue ?? [])
        let frame = frames.first { $0["binaryName"]?.stringValue == appBinaryName } ?? frames.first
        return frame.map(describe(frame:))
    }

    /// Rammene i rekkefølge: hver ramme før rammene under den (`subFrames`).
    static func flatten(_ frames: [AnyJSON]) -> [JSONObject] {
        frames.compactMap(\.objectValue).flatMap { frame in
            [frame] + flatten(frame["subFrames"]?.arrayValue ?? [])
        }
    }

    static func describe(frame: JSONObject) -> String {
        let binary = frame["binaryName"]?.stringValue ?? "?"
        if let offset = frame["offsetIntoBinaryTextSegment"]?.intValue {
            return "\(binary)+0x\(String(offset, radix: 16))"
        }
        if let address = frame["address"]?.intValue {
            return "\(binary)@0x\(String(address, radix: 16))"
        }
        return binary
    }

    // MARK: - Tekst og payload

    /// Kutter til `limit` tegn, med «…» som siste tegn når noe er kuttet.
    static func truncate(_ text: String, to limit: Int) -> String {
        guard text.count > limit, limit > 0 else { return text }
        return String(text.prefix(limit - 1)) + "…"
    }

    private static func measured(_ label: String, _ value: AnyJSON?) -> String {
        text(value, limit: 60).map { "\(label) \($0)" } ?? label
    }

    /// Tekst eller tall som tekst, kuttet til `limit`. Tom eller manglende verdi gir nil.
    static func text(_ value: AnyJSON?, limit: Int) -> String? {
        let raw: String? = switch value {
        case .string(let string): string
        case .integer(let int): String(int)
        case .double(let double): String(double)
        default: nil
        }
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return truncate(raw, to: limit)
    }

    /// Payloaden med bare denne diagnosen. Er den for stor, tas kallstakken bort (signaturen
    /// har fortsatt øverste ramme), og er den fortsatt for stor, står bare merket igjen.
    static func payload(kind: DiagnosticKind, diagnostic: JSONObject, root: JSONObject) -> AnyJSON {
        var base: JSONObject = [:]
        for key in ["timeStampBegin", "timeStampEnd"] {
            if let value = root[key] { base[key] = value }
        }
        func wrap(_ diagnostic: JSONObject) -> AnyJSON {
            var object = base
            object[kind.payloadKey] = .array([.object(diagnostic)])
            return .object(object)
        }
        let full = wrap(diagnostic)
        let size = byteCount(full)
        guard size > payloadLimit else { return full }
        var trimmed = diagnostic
        trimmed["callStackTree"] = .object(["truncated": .bool(true), "bytes": .integer(size)])
        let smaller = wrap(trimmed)
        if byteCount(smaller) <= payloadLimit { return smaller }
        return .object(["truncated": .bool(true), "bytes": .integer(size)])
    }

    static func byteCount(_ value: AnyJSON) -> Int {
        (try? JSONEncoder().encode(value).count) ?? .max
    }
}
