import Foundation

protocol SnapshotCaching: Sendable {
    func load() async throws -> [ProviderID: ProviderSnapshot]
    func save(_ snapshots: [ProviderID: ProviderSnapshot]) async throws
    func remove(_ providerID: ProviderID) async throws
}

protocol SnapshotFileWriting: Sendable {
    func write(_ data: Data, to fileURL: URL) throws
}

struct AtomicSnapshotFileWriter: SnapshotFileWriting {
    func write(_ data: Data, to fileURL: URL) throws {
        try data.write(to: fileURL, options: .atomic)
    }
}

actor SnapshotCache: SnapshotCaching {
    enum CacheError: Error, Equatable {
        case unsupportedSchema(Int)
        case duplicateProvider(ProviderID)
        case providerIdentityMismatch(ProviderID)
    }

    private struct Envelope: Codable {
        let schemaVersion: Int
        let snapshots: [ProviderSnapshot]
    }

    private static let schemaVersion = 1

    private let fileURL: URL
    private let writer: SnapshotFileWriting
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileURL: URL = SnapshotCache.defaultFileURL(),
        writer: SnapshotFileWriting = AtomicSnapshotFileWriter(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.writer = writer
        self.fileManager = fileManager

        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
    }

    func load() throws -> [ProviderID: ProviderSnapshot] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [:] }

        let envelope = try decoder.decode(Envelope.self, from: Data(contentsOf: fileURL))
        guard envelope.schemaVersion == Self.schemaVersion else {
            throw CacheError.unsupportedSchema(envelope.schemaVersion)
        }

        var snapshots: [ProviderID: ProviderSnapshot] = [:]
        for snapshot in envelope.snapshots {
            guard snapshots.updateValue(snapshot, forKey: snapshot.providerID) == nil else {
                throw CacheError.duplicateProvider(snapshot.providerID)
            }
        }
        return snapshots
    }

    func save(_ snapshots: [ProviderID: ProviderSnapshot]) throws {
        for (providerID, snapshot) in snapshots where providerID != snapshot.providerID {
            throw CacheError.providerIdentityMismatch(providerID)
        }

        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let envelope = Envelope(
            schemaVersion: Self.schemaVersion,
            snapshots: snapshots.values.sorted { $0.providerID.rawValue < $1.providerID.rawValue }
        )
        try writer.write(encoder.encode(envelope), to: fileURL)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)

        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableFileURL = fileURL
        try mutableFileURL.setResourceValues(resourceValues)
    }

    func remove(_ providerID: ProviderID) throws {
        var snapshots = try load()
        snapshots.removeValue(forKey: providerID)
        try save(snapshots)
    }

    private static func defaultFileURL() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return applicationSupport
            .appendingPathComponent("LLMSpendMonitor", isDirectory: true)
            .appendingPathComponent("snapshots-v1.json")
    }
}
