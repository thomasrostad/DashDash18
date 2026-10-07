import Foundation
import ImageIO

// Portrettet under «Deg» (PWA: `komprimerPortrett`, `portrettUtsnitt`, `velgKlubbilde`).
// Ren logikk: sti, utsnitt, krymping og sjekken av raden som kommer tilbake.
// Nettverket ligger i `DegPortraitModel`.

/// Stien i bøtta `avatars` (008): `<member_id>/<uuid>.jpg`, små bokstaver. Storage-policyen
/// (`storage_path_member`/`storage_can_write`) leser medlemmet fra mappen, og
/// `club_members_avatar_path_shape` krever at raden peker inn i sin egen mappe.
nonisolated enum DegAvatarPath {
    static let bucket = "avatars"

    static func make(memberID: UUID, fileID: UUID = UUID()) -> String {
        "\(memberID.uuidString.lowercased())/\(fileID.uuidString.lowercased()).jpg"
    }

    /// Om stien har formen databasen godtar for akkurat dette medlemmet.
    static func isValid(_ path: String, memberID: UUID) -> Bool {
        let prefix = memberID.uuidString.lowercased() + "/"
        guard path.hasPrefix(prefix) else { return false }
        let file = path.dropFirst(prefix.count)
        return file.wholeMatch(of: /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg/) != nil
    }
}

/// Hvordan portrettet gjøres klart (PWA: `PORTRETT_SIDE`, JPEG 0,85).
nonisolated enum DegPortraitSpec {
    /// Sidelengden på det kvadratiske portrettet i piksler.
    static let side = 600
    static let quality = 0.85
    /// Bøttas grense (`file_size_limit` 3 MB, som tråden).
    static let maxBytes = TradImageSpec.maxBytes
    static let fallbackQualities = TradImageSpec.fallbackQualities
}

/// Det kvadratiske utsnittet av bildet (PWA: `portrettUtsnitt`). Et stående bilde skjæres
/// fra øvre del (en firedel ned), der ansiktet pleier å være; et liggende fra midten.
nonisolated struct DegPortraitCrop: Equatable, Sendable {
    let x: Int
    let y: Int
    /// Sidelengden på utsnittet i originalbildet.
    let side: Int
    /// Sidelengden på portrettet som lagres (aldri forstørret).
    let output: Int

    init(x: Int, y: Int, side: Int, output: Int) {
        self.x = x
        self.y = y
        self.side = side
        self.output = output
    }

    /// `Math.round` = `floor(x + 0,5)`, som i PWA-en.
    init?(width: Int, height: Int, maxSide: Int = DegPortraitSpec.side) {
        guard width > 0, height > 0 else { return nil }
        func jsRound(_ value: Double) -> Int { Int((value + 0.5).rounded(.down)) }
        let side = min(width, height)
        self.init(
            x: jsRound(Double(width - side) / 2),
            y: height > width ? jsRound(Double(height - side) * 0.25) : 0,
            side: side,
            output: min(maxSide, side)
        )
    }
}

/// Lager portrettet: retningen fra kameraet bakes inn, kvadratisk utsnitt, 600 px, JPEG uten
/// metadata (som GPS-posisjon).
nonisolated enum DegPortraitCompressor {
    struct Output: Equatable, Sendable {
        let data: Data
        let side: Int
    }

    typealias Failure = TradImageCompressor.Failure

    static func compress(_ data: Data) throws(Failure) -> Output {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int
        else { throw .unreadable }
        // Hele bildet, rettet opp. Lengste side begrenses så et 48 MP-bilde ikke fyller minnet;
        // det kvadratiske utsnittet blir likevel minst `DegPortraitSpec.side` når det går.
        let shortest = max(1, min(width, height))
        let longest = max(width, height)
        let limit = min(longest, Int((Double(longest) * Double(DegPortraitSpec.side * 2) / Double(shortest)).rounded(.up)))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, limit),
        ]
        guard let oriented = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let crop = DegPortraitCrop(width: oriented.width, height: oriented.height),
              let square = oriented.cropping(to: CGRect(x: crop.x, y: crop.y, width: crop.side, height: crop.side)),
              let scaled = scale(square, to: crop.output)
        else { throw .unreadable }
        for quality in [DegPortraitSpec.quality] + DegPortraitSpec.fallbackQualities {
            guard let jpeg = TradImageCompressor.encode(scaled, quality: quality) else { throw .unreadable }
            if jpeg.count <= DegPortraitSpec.maxBytes {
                return Output(data: jpeg, side: scaled.width)
            }
        }
        throw .tooLarge
    }

    private static func scale(_ image: CGImage, to side: Int) -> CGImage? {
        if image.width == side, image.height == side { return image }
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()
    }
}

/// Bare `avatar_path`, sendt som `null` når portrettet fjernes.
nonisolated struct AvatarPatch: Encodable, Equatable, Sendable {
    let avatarPath: String?

    enum CodingKeys: String, CodingKey {
        case avatarPath = "avatar_path"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(avatarPath, forKey: .avatarPath)
    }
}

nonisolated enum DegPortrait {
    /// Sjekker raden etter at portrettet er byttet eller fjernet. Null rader betyr at RLS sa nei.
    static func verify(returned rows: [ClubMemberRow], memberID: UUID, path: String?) -> Result<ClubMemberRow, DegProfileError> {
        guard rows.count == 1, let row = rows.first, row.id == memberID else { return .failure(.notSaved) }
        guard row.avatarPath == path else { return .failure(.mismatch) }
        return .success(row)
    }

    /// Den gamle fila som skal fjernes etter at raden peker på den nye. Bare filer i
    /// medlemmets egen mappe, og aldri den nye.
    static func staleFile(old: String?, new: String?, memberID: UUID) -> String? {
        guard let old, old != new, DegAvatarPath.isValid(old, memberID: memberID) else { return nil }
        return old
    }
}
