import Foundation

public struct SessionRepository {
    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    private struct SaveEnvelope: Codable {
        let schemaVersion: Int
        let session: CompanionSession
    }

    public func load() throws -> CompanionSession? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let envelope = try JSONDecoder().decode(SaveEnvelope.self, from: data)
        guard envelope.schemaVersion == 1 else { throw CompanionError.unsupportedSave }
        try envelope.session.validate()
        return envelope.session
    }

    public func save(_ session: CompanionSession) throws {
        try session.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(SaveEnvelope(schemaVersion: 1, session: session))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                               withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    @discardableResult
    public func backUpUnreadableSave() throws -> URL? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let backup = fileURL.deletingPathExtension().appendingPathExtension("backup-\(UUID().uuidString).json")
        try FileManager.default.copyItem(at: fileURL, to: backup)
        return backup
    }
}
