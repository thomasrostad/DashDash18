import Foundation
import Network

/// Klokke for utboksen: tidsstempler og ventetid mellom nye forsøk. Byttes ut i testene.
protocol OutboxClock: AnyObject {
    var now: Date { get }
    func sleep(for duration: Duration) async throws
}

final class SystemOutboxClock: OutboxClock {
    var now: Date { Date() }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

/// Om telefonen har nett. Strømmen gir `true` når nettet er der og `false` når det er borte.
protocol NetworkMonitoring: AnyObject {
    func availability() -> AsyncStream<Bool>
}

/// `NWPathMonitor` som strøm. Én monitor per strøm, stoppes når strømmen avsluttes.
final class PathNetworkMonitor: NetworkMonitoring {
    func availability() -> AsyncStream<Bool> {
        Self.makeStream()
    }

    // Utenfor MainActor: NWPathMonitor kaller tilbake på sin egen kø.
    private nonisolated static func makeStream() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied)
            }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "no.dashdash18.utboks.nett"))
        }
    }
}

/// Ventetid før neste forsøk: 1, 2, 4, 8 … sekunder, maks `maximum`.
nonisolated struct OutboxBackoff: Equatable, Sendable {
    var base: Duration = .seconds(1)
    var maximum: Duration = .seconds(60)

    /// `failures` er antall feil på rad (minst 1).
    func delay(afterFailures failures: Int) -> Duration {
        let exponent = min(max(failures, 1) - 1, 30)
        let delay = base * (1 << exponent)
        return min(delay, maximum)
    }
}
