import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import DashDash18

/// Sikkerhetsrevisjonen av appen (docs/sikkerhet-app.md): nøkler, lokal rydding, metadata i bilder
/// og Privacy Manifest.
struct SikkerhetAppTests {
    static let userA = UUID(uuidString: "0A0A0A0A-0000-4000-8000-00000000000A")!
    static let userB = UUID(uuidString: "0B0B0B0B-0000-4000-8000-00000000000B")!

    /// En JWT med gitt rolle (signaturen sjekkes ikke av appen).
    static func jwt(role: String) -> String {
        func b64(_ json: String) -> String {
            Data(json.utf8).base64EncodedString()
                .replacingOccurrences(of: "=", with: "")
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
        }
        return b64(#"{"alg":"HS256","typ":"JWT"}"#) + "." + b64(#"{"iss":"supabase","role":"\#(role)"}"#) + ".c2lnbmF0dXI"
    }

    /// Egen `UserDefaults`-suite per test.
    static func defaults() -> (UserDefaults, String) {
        let name = "sikkerhet.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    // MARK: Nøkler

    @Test func hemmeligeNoklerAvvises() {
        #expect(AppConfig.isSecretKey("sb_secret_abc"))
        #expect(AppConfig.isSecretKey(Self.jwt(role: "service_role")))
        #expect(!AppConfig.isSecretKey(Self.jwt(role: "anon")))
        #expect(!AppConfig.isSecretKey("sb_publishable_abc"))
        #expect(!AppConfig.isSecretKey("eyJ-ikke-en-jwt"))
    }

    @Test func serviceRoleJWTIKonfigStopper() throws {
        let plist: [String: Any] = [
            "Environment": "test",
            "SupabaseURL": "https://abc.supabase.co",
            "SupabasePublishableKey": Self.jwt(role: "service_role"),
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        #expect(throws: AppConfig.LoadError.secretKey) {
            try AppConfig(plistData: data, expecting: .test)
        }
    }

    // MARK: Sletting av konto: innstillinger på telefonen

    @Test func kontoensNoklerFinnes() {
        let a = Self.userA.uuidString
        let keys = [
            "apenValg.\(a.lowercased())",
            "statistikk.foring.\(a)",
            "medlemskap.\(Self.userB.uuidString.lowercased())",
            "trad.lastSeen.x.y",
            "varsler.sistSett.z",
            "valgtKlubb",
            "ventendeKjop",
            "apenValg.\(Self.userB.uuidString.lowercased())",
            "statistikk.foring.\(Self.userB.uuidString)",
            FreshInstallGuard.markerKey,
            "AppleLanguages",
        ]
        let removed = LocalDataReset.accountKeys(in: keys, userID: Self.userA)
        #expect(Set(removed) == [
            "apenValg.\(a.lowercased())", "statistikk.foring.\(a)",
            "medlemskap.\(Self.userB.uuidString.lowercased())", "trad.lastSeen.x.y", "varsler.sistSett.z",
            "valgtKlubb", "ventendeKjop",
        ])
        // En annen konto sine valg på samme telefon står, og det samme gjør installasjonsmerket.
        #expect(!removed.contains("apenValg.\(Self.userB.uuidString.lowercased())"))
        #expect(!removed.contains(FreshInstallGuard.markerKey))
    }

    @Test func kontoensNoklerSlettesFraUserDefaults() {
        let (defaults, name) = Self.defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        AppHomeChoiceStore(defaults: defaults).save(.friends, userID: Self.userA)
        AppHomeChoiceStore(defaults: defaults).save(.club, userID: Self.userB)
        HoleStatsSetting(defaults: defaults).set(true, for: Self.userA)
        PendingPurchaseStore(defaults: defaults).setTarget(UUID())

        LocalDataReset.removeAccountData(userID: Self.userA, defaults: defaults)

        #expect(AppHomeChoiceStore(defaults: defaults).load(userID: Self.userA) == nil)
        #expect(!HoleStatsSetting(defaults: defaults).isOn(for: Self.userA))
        #expect(defaults.dictionary(forKey: "ventendeKjop") == nil)
        #expect(AppHomeChoiceStore(defaults: defaults).load(userID: Self.userB) == .club)
    }

    // MARK: Ny installasjon

    @Test func nyInstallasjonFjernerOktenFraNokkelringen() {
        #expect(FreshInstallGuard.decide(appDefaults: nil) == .freshInstall)
        #expect(FreshInstallGuard.decide(appDefaults: [:]) == .freshInstall)
        #expect(FreshInstallGuard.decide(appDefaults: ["medlemskap.x": Data()]) == .upgraded)
        #expect(FreshInstallGuard.decide(appDefaults: [FreshInstallGuard.markerKey: true]) == .known)
    }

    @Test func vaktenKjorerBareEnGang() {
        let (defaults, name) = Self.defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        var cleared = 0
        FreshInstallGuard.run(defaults: defaults, domain: name) { cleared += 1 }
        #expect(cleared == 1)
        #expect(defaults.bool(forKey: FreshInstallGuard.markerKey))
        FreshInstallGuard.run(defaults: defaults, domain: name) { cleared += 1 }
        #expect(cleared == 1)
    }

    @Test func oppdatertAppBeholderInnloggingen() {
        let (defaults, name) = Self.defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("x", forKey: "valgtKlubb")
        var cleared = 0
        FreshInstallGuard.run(defaults: defaults, domain: name) { cleared += 1 }
        #expect(cleared == 0)
        #expect(defaults.bool(forKey: FreshInstallGuard.markerKey))
    }

    // MARK: Utlogging: widgetene

    @Test func widgetDataSlettesVedUtlogging() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "sikkerhet-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        var snapshot = WidgetSnapshot()
        snapshot.top = [.init(place: 1, name: "Anders", points: 10, pointsText: "10", isMe: false)]
        snapshot.tavlaLoaded = true
        try store.write(snapshot)
        #expect(store.read().top.count == 1)

        store.clear(reloadWidgets: false)

        #expect(store.read() == .empty)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path()))
        // Ingen fil: ingenting å gjøre, og ingen feil.
        store.clear(reloadWidgets: false)
    }

    // MARK: Bilder: ingen metadata (GPS) følger med

    /// Et JPEG med GPS-posisjon og EXIF, som fra kameraet.
    static func jpegWithLocation(width: Int = 2000, height: Int = 1500) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.3, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let out = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil))
        let props: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 59.91,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 10.75,
                kCGImagePropertyGPSLongitudeRef: "E",
            ],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "Hjemme"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "iPhone"],
        ]
        CGImageDestinationAddImage(destination, image, props as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        // Sjekk at testbildet faktisk har posisjonen.
        let source = try #require(CGImageSourceCreateWithData(out as CFData, nil))
        let inProps = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        #expect(inProps?[kCGImagePropertyGPSDictionary] != nil)
        return out as Data
    }

    static func metadata(_ jpeg: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }

    @Test func tradBildeMisterGPS() throws {
        let output = try TradImageCompressor.compress(Self.jpegWithLocation())
        let props = try Self.metadata(output.data)
        #expect(props[kCGImagePropertyGPSDictionary] == nil)
        #expect((props[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFModel] == nil)
        #expect((props[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifUserComment] == nil)
    }

    @Test func portrettMisterGPS() throws {
        let output = try DegPortraitCompressor.compress(Self.jpegWithLocation())
        let props = try Self.metadata(output.data)
        #expect(props[kCGImagePropertyGPSDictionary] == nil)
        #expect((props[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFModel] == nil)
    }

    // MARK: Privacy Manifest og tekster i appen

    @Test func privacyManifestLiggerIAppen() throws {
        let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let data = try Data(contentsOf: url)
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["NSPrivacyTracking"] as? Bool == false)
        let apis = plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []
        let reasons = Dictionary(uniqueKeysWithValues: apis.compactMap { entry -> (String, [String])? in
            guard let type = entry["NSPrivacyAccessedAPIType"] as? String else { return nil }
            return (type, entry["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? [])
        })
        #expect(reasons["NSPrivacyAccessedAPICategoryUserDefaults"] == ["CA92.1"])
        let collected = (plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]] ?? [])
            .compactMap { $0["NSPrivacyCollectedDataType"] as? String }
        #expect(collected.contains("NSPrivacyCollectedDataTypeEmailAddress"))
        #expect(collected.contains("NSPrivacyCollectedDataTypePhotosorVideos"))
    }

    @Test func kamerateksteneNevnerTradOgPortrett() {
        let text = Bundle.main.localizedString(forKey: "NSCameraUsageDescription", value: nil, table: "InfoPlist")
        #expect(text.contains("tråden"))
        #expect(text.contains("portrett"))
    }
}

/// Sletting av konto: hullene i utboksen fjernes for kontoen, ikke for andre.
@MainActor
struct SikkerhetUtboksTests {
    @Test func slettetKontoTommerUtboksen() async throws {
        let container = try OutboxScoreSubmitter.makeContainer(inMemory: true)
        let sender = FakeSender()
        sender.mode = .offline
        let roundID = UUID(), player = UUID()
        let outbox = OutboxScoreSubmitter(inner: sender, container: container, clock: TestClock(), network: FakeNetwork())
        func hole(_ index: Int) -> HoleSubmission {
            HoleSubmission(roundID: roundID, holeIndex: index,
                           entries: [HoleSubmission.Entry(memberID: player, strokes: 4)], recordedAt: .now)
        }
        outbox.start(userID: SikkerhetAppTests.userA)
        _ = try await outbox.submit(hole(1))
        outbox.stop()
        outbox.start(userID: SikkerhetAppTests.userB)
        _ = try await outbox.submit(hole(2))
        outbox.stop()

        outbox.removeAll(userID: SikkerhetAppTests.userA)

        let left = try ModelContext(container).fetch(FetchDescriptor<OutboxItem>())
        #expect(left.map(\.holeIndex) == [2])
        #expect(left.first?.userID == SikkerhetAppTests.userB)
    }
}
