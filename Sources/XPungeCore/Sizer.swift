import Foundation

/// Measures on-disk (allocated) size. Does not follow symbolic links and does not cross into other volumes.
public enum Sizer {
    private static let keys: [URLResourceKey] = [
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey, .isSymbolicLinkKey, .volumeIdentifierKey,
    ]

    /// Size of a file or folder in bytes; 0 if it does not exist.
    public static func size(of url: URL) -> Int64 {
        guard let rootValues = try? url.resourceValues(forKeys: Set(keys)) else { return 0 }
        if rootValues.isSymbolicLink == true { return 0 }
        if rootValues.isDirectory != true { return allocated(rootValues) }

        let rootVolume = rootValues.volumeIdentifier as? NSObject
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        for case let item as URL in enumerator {
            guard let values = try? item.resourceValues(forKeys: Set(keys)) else { continue }
            if let volume = values.volumeIdentifier as? NSObject, let rootVolume, !volume.isEqual(rootVolume) {
                enumerator.skipDescendants()
                continue
            }
            total += allocated(values)
        }
        return total
    }

    public static func size(of urls: [URL]) -> Int64 {
        urls.reduce(0) { $0 + size(of: $1) }
    }

    private static func allocated(_ values: URLResourceValues) -> Int64 {
        Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }
}
