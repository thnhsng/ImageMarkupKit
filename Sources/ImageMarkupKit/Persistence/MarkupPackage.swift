import UIKit

/// Editable markup on disk, so a saved board or photo can be reopened and edited later:
///
///     <document id>.markup/
///         document.json     objects, styles, bindings (MarkupDocument, schemaVersion 1)
///         assets/<assetID>  original photos, byte-for-byte
///         export.jpg        the flattened image
///         thumbnail.jpg     512 px preview
///
/// Saving writes a temporary folder and swaps it in atomically; photos no longer referenced are dropped.
public enum MarkupPackage {
    public static let pathExtension = "markup"

    public struct Contents {
        public let url: URL
        public let document: MarkupDocument
        public let assets: AssetCatalog
        public let exportURL: URL?
        public let thumbnailURL: URL?
    }

    public enum PackageError: Error {
        case missingAsset(String)
    }

    /// Saves (or replaces) the package of `document` inside `directory`. Safe to call off the main thread.
    @discardableResult
    public static func save(_ document: MarkupDocument, assets: AssetCatalog, export: MarkupRendering?, in directory: URL) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = url(for: document.id, in: directory)
        let staging = directory.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        let assetsFolder = staging.appendingPathComponent("assets", isDirectory: true)
        try fileManager.createDirectory(at: assetsFolder, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        for assetID in Set(document.items.compactMap(\.imageContent?.assetID)) {
            guard let source = assets.url(for: assetID) else { throw PackageError.missingAsset(assetID) }
            try fileManager.copyItem(at: source, to: assetsFolder.appendingPathComponent(fileName(for: assetID)))
        }
        try document.jsonData().write(to: staging.appendingPathComponent("document.json"), options: .atomic)
        if let export {
            try export.data.write(to: staging.appendingPathComponent("export.jpg"), options: .atomic)
            if let thumbnail = ImagePipeline.downsample(data: export.data, maxPixelSize: 512),
               let data = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.8) {
                try data.write(to: staging.appendingPathComponent("thumbnail.jpg"), options: .atomic)
            }
        }

        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: destination)
        }
        return destination
    }

    /// Reads a package; the returned catalog points at the photos inside it.
    public static func load(from url: URL) throws -> Contents {
        let document = try MarkupDocument.decode(from: Data(contentsOf: url.appendingPathComponent("document.json")))
        var catalog = AssetCatalog()
        for assetID in Set(document.items.compactMap(\.imageContent?.assetID)) {
            let file = url.appendingPathComponent("assets", isDirectory: true).appendingPathComponent(fileName(for: assetID))
            guard FileManager.default.fileExists(atPath: file.path) else { throw PackageError.missingAsset(assetID) }
            catalog[assetID] = file
        }
        let export = url.appendingPathComponent("export.jpg")
        let thumbnail = url.appendingPathComponent("thumbnail.jpg")
        return Contents(
            url: url,
            document: document,
            assets: catalog,
            exportURL: FileManager.default.fileExists(atPath: export.path) ? export : nil,
            thumbnailURL: FileManager.default.fileExists(atPath: thumbnail.path) ? thumbnail : nil
        )
    }

    /// Packages in `directory`, most recently modified first.
    public static func packages(in directory: URL) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return urls
            .filter { $0.pathExtension == pathExtension }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
                return a > b
            }
    }

    public static func url(for documentID: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent("\(documentID.uuidString).\(pathExtension)", isDirectory: true)
    }

    /// Asset IDs are file names; strip any path components defensively.
    private static func fileName(for assetID: String) -> String {
        (assetID as NSString).lastPathComponent
    }
}
