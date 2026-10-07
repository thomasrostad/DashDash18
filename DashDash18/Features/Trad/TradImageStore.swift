import UIKit

/// Bildene i tråden, hurtigbufret per sti. En sti peker alltid på samme bilde (ny fil får ny
/// sti), så bildet kan brukes om igjen selv når den signerte lenka er fornyet.
final class TradImageStore {
    static let shared = TradImageStore()

    private let cache = NSCache<NSString, UIImage>()
    /// Bilder sendt fra denne telefonen. Holdes til appen avsluttes, så de vises uten nett.
    private var local: [String: UIImage] = [:]
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        cache.countLimit = 150
    }

    func storeLocal(_ jpeg: Data, for path: String) {
        guard let image = UIImage(data: jpeg) else { return }
        local[path] = image
    }

    func hasLocal(_ path: String) -> Bool { local[path] != nil }

    func forget(_ path: String) {
        local[path] = nil
        cache.removeObject(forKey: path as NSString)
    }

    /// Ved utlogging: ingen bilder fra forrige innlogging ligger igjen i minnet.
    func removeAll() {
        local.removeAll()
        cache.removeAllObjects()
    }

    func cached(_ path: String) -> UIImage? {
        local[path] ?? cache.object(forKey: path as NSString)
    }

    /// Bildet fra hurtigbufferen, ellers lastet ned fra den signerte lenka.
    func image(for path: String, url: URL) async throws -> UIImage {
        if let image = cached(path) { return image }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard let image = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}
