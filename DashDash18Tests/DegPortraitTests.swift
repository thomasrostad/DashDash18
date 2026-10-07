import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import DashDash18

/// Fixturen `DegFixtures.json`: handicap og portrettutsnitt.
enum DegFixtures {
    struct File: Decodable {
        struct Handicap: Decodable {
            struct Valid: Decodable {
                let tekst: String
                let indeks: Double?
            }

            struct Display: Decodable {
                let indeks: Double?
                let tekst: String
            }

            let gyldige: [Valid]
            let ugyldige: [String]
            let visning: [Display]
        }

        struct Crop: Decodable {
            let bredde: Int
            let hoyde: Int
            let x: Int
            let y: Int
            let side: Int
            let ut: Int
        }

        let handicap: Handicap
        let portrettUtsnitt: [Crop]
    }

    private final class BundleToken {}

    static func load() throws -> File {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "DegFixtures", withExtension: "json"))
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
    }
}

struct DegHandicapFixtureTests {
    @Test func gyldigeTolkes() throws {
        for item in try DegFixtures.load().handicap.gyldige {
            #expect(try ClubInput.handicapIndex(item.tekst).get() == item.indeks, "«\(item.tekst)»")
        }
    }

    @Test func ugyldigeAvvises() throws {
        for text in try DegFixtures.load().handicap.ugyldige {
            if case .success = ClubInput.handicapIndex(text) {
                Issue.record("«\(text)» skulle vært avvist")
            }
        }
    }

    @Test func visningMedKomma() throws {
        for item in try DegFixtures.load().handicap.visning {
            #expect(TroppInput.handicapText(item.indeks) == item.tekst)
        }
    }

    @Test func toppenViserHandicap() {
        #expect(DegHandicapText.short(12.4) == "hcp 12,4")
        #expect(DegHandicapText.short(-2.3) == "hcp +2,3")
        #expect(DegHandicapText.short(nil) == "hcp ikke oppgitt")
    }
}

struct DegPortraitCropTests {
    @Test func utsnittSomPWAen() throws {
        for item in try DegFixtures.load().portrettUtsnitt {
            let crop = try #require(DegPortraitCrop(width: item.bredde, height: item.hoyde))
            #expect(crop == DegPortraitCrop(x: item.x, y: item.y, side: item.side, output: item.ut),
                    "\(item.bredde)×\(item.hoyde)")
        }
    }

    @Test func tomtBildeHarIkkeUtsnitt() {
        #expect(DegPortraitCrop(width: 0, height: 100) == nil)
        #expect(DegPortraitCrop(width: 100, height: -1) == nil)
    }
}

struct DegPortraitCompressorTests {
    private func decodedSize(_ data: Data) throws -> (Int, Int) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return (props[kCGImagePropertyPixelWidth] as? Int ?? 0, props[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    @Test func kameraBildeBlirKvadratisk600() throws {
        let output = try DegPortraitCompressor.compress(TradImageCompressorTests.jpeg(width: 4032, height: 3024))
        #expect(output.side == 600)
        let (width, height) = try decodedSize(output.data)
        #expect(width == 600 && height == 600)
        #expect(output.data.count <= DegPortraitSpec.maxBytes)
        #expect(output.data.prefix(2) == Data([0xFF, 0xD8]))
    }

    @Test func retningenBakesInnOgMetadataFjernes() throws {
        let output = try DegPortraitCompressor.compress(TradImageCompressorTests.jpeg(width: 3024, height: 4032, orientation: 6))
        let source = try #require(CGImageSourceCreateWithData(output.data as CFData, nil))
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        #expect((props?[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
        #expect(props?[kCGImagePropertyGPSDictionary] == nil)
        let (width, height) = try decodedSize(output.data)
        #expect(width == 600 && height == 600)
    }

    @Test func smaaBilderBlaasesIkkeOpp() throws {
        let output = try DegPortraitCompressor.compress(TradImageCompressorTests.jpeg(width: 320, height: 200))
        #expect(output.side == 200)
        let (width, height) = try decodedSize(output.data)
        #expect(width == 200 && height == 200)
    }

    @Test func oedelagtFilGirMelding() {
        #expect(throws: TradImageCompressor.Failure.unreadable) {
            try DegPortraitCompressor.compress(Data("ikke et bilde".utf8))
        }
    }
}

struct DegAvatarPathTests {
    private let member = UUID(uuidString: "11111111-AAAA-0000-0000-000000000002")!
    private let file = UUID(uuidString: "BBBBBBBB-0000-4000-8000-00000000000C")!

    @Test func stienErMedlemmetsMappeMedSmaaBokstaver() {
        let path = DegAvatarPath.make(memberID: member, fileID: file)
        #expect(path == "11111111-aaaa-0000-0000-000000000002/bbbbbbbb-0000-4000-8000-00000000000c.jpg")
        #expect(DegAvatarPath.isValid(path, memberID: member))
        #expect(DegAvatarPath.bucket == "avatars")
    }

    @Test func nyFilFaarNySti() {
        #expect(DegAvatarPath.make(memberID: member) != DegAvatarPath.make(memberID: member))
    }

    @Test func andresMappeEllerFeilFormAvvises() {
        let other = UUID()
        #expect(!DegAvatarPath.isValid(DegAvatarPath.make(memberID: other), memberID: member))
        #expect(!DegAvatarPath.isValid("11111111-aaaa-0000-0000-000000000002/bilde.png", memberID: member))
        #expect(!DegAvatarPath.isValid("11111111-aaaa-0000-0000-000000000002/sub/x.jpg", memberID: member))
    }

    @Test func patchenSenderBareAvatarStien() throws {
        let set = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AvatarPatch(avatarPath: "a/b.jpg"))) as? [String: Any]
        #expect(set?.keys.sorted() == ["avatar_path"])
        #expect(set?["avatar_path"] as? String == "a/b.jpg")
        let keys = Set(set.map { Array($0.keys) } ?? [])
        #expect(keys.isSubset(of: DegProfile.ownWritableColumns))
        let cleared = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AvatarPatch(avatarPath: nil))) as? [String: Any]
        #expect(cleared?["avatar_path"] is NSNull)
    }
}

struct DegPortraitVerifyTests {
    private let member = UUID(uuidString: "11111111-0000-0000-0000-000000000002")!

    private func row(id: UUID? = nil, avatar: String?) -> ClubMemberRow {
        ClubMemberRow(
            id: id ?? member, clubID: UUID(), userID: UUID(), displayName: "Anders", handicapIndex: 18.4,
            seedGroup: nil, isOrganizer: false, isTreasurer: false, status: .active, avatarPath: avatar
        )
    }

    @Test func lagretStiGodtas() {
        let path = DegAvatarPath.make(memberID: member)
        let saved = row(avatar: path)
        #expect(DegPortrait.verify(returned: [saved], memberID: member, path: path) == .success(saved))
        let cleared = row(avatar: nil)
        #expect(DegPortrait.verify(returned: [cleared], memberID: member, path: nil) == .success(cleared))
    }

    @Test func ingenRadErIkkeLagret() {
        #expect(DegPortrait.verify(returned: [], memberID: member, path: "x") == .failure(.notSaved))
        #expect(DegPortrait.verify(returned: [row(id: UUID(), avatar: "x")], memberID: member, path: "x") == .failure(.notSaved))
    }

    @Test func annenStiTilbakeOppdages() {
        #expect(DegPortrait.verify(returned: [row(avatar: "y")], memberID: member, path: "x") == .failure(.mismatch))
    }

    @Test func gammelFilRyddesBareIEgenMappe() {
        let old = DegAvatarPath.make(memberID: member)
        let new = DegAvatarPath.make(memberID: member)
        #expect(DegPortrait.staleFile(old: old, new: new, memberID: member) == old)
        #expect(DegPortrait.staleFile(old: old, new: nil, memberID: member) == old)
        #expect(DegPortrait.staleFile(old: old, new: old, memberID: member) == nil)
        #expect(DegPortrait.staleFile(old: nil, new: new, memberID: member) == nil)
        #expect(DegPortrait.staleFile(old: DegAvatarPath.make(memberID: UUID()), new: new, memberID: member) == nil)
    }
}
