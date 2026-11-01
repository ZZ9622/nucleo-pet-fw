import Foundation

public struct BoardRecord: Codable, Equatable {
    public let v: Int
    public let ok: Bool
    public let error: String
    public let petID: UUID
    public let phase: UInt32
    public let revision: UInt32
    public let transferID: UUID
    public let payloadHash: UInt32
    public let state: FirmwareState

    public func validate() throws {
        try state.validate()
        guard v == 2, ok, phase < 4, revision < UInt32.max else {
            throw PhysicalError.message(error.isEmpty ? "挂件记录不可用，请检查固件和存档。" : error)
        }
    }
}

public enum PhysicalError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

public struct PhysicalIntent: Codable, Equatable {
    public let id: UUID
    public let destination: Residence
    public let baseRevision: UInt32
    public var snapshot: FirmwareState?
    public var released: Bool
}

/// Durable ownership record; never activates a received pet before board commit.
public struct PhysicalSession: Codable, Equatable {
    public private(set) var companion: CompanionSession
    public private(set) var intent: PhysicalIntent?

    public init(board: BoardRecord, now: Date = Date()) throws {
        try board.validate()
        guard board.phase == 0 else {
            throw PhysicalError.message("这只宠物已在交接或另一台手机里。请在原来的手机继续旅程。")
        }
        companion = CompanionSession(now: now, state: board.state, petID: board.petID,
            residence: .device, revision: UInt64(board.revision))
        intent = nil
    }

    public mutating func observe(_ board: BoardRecord, now: Date = Date()) throws {
        try board.validate()
        guard board.petID == companion.petID else { throw PhysicalError.message("这不是已绑定的挂件。") }
        guard intent == nil else { return }
        guard UInt64(board.revision) == companion.revision,
              board.phase == (companion.residence == .device ? 0 : 2) else {
            throw PhysicalError.message("两端记录不一致，已停止互动。请保留手机存档并检查挂件。")
        }
        if companion.residence == .device {
            companion.state = board.state
            companion.updatedAt = now
        } else { companion.advance(to: now) }
    }

    public mutating func advance(to now: Date) {
        if companion.residence == .phone && intent == nil { companion.advance(to: now) }
    }

    @discardableResult
    public mutating func care(_ action: CareAction, at now: Date = Date()) throws -> Bool {
        guard intent == nil else { throw CompanionError.transferInProgress }
        return try companion.care(action, at: now)
    }

    public mutating func begin(to destination: Residence, now: Date = Date()) throws {
        if let intent {
            guard intent.destination == destination else { throw CompanionError.transferInProgress }
            return
        }
        guard destination != companion.residence, companion.revision < UInt32.max - 1 else {
            throw CompanionError.wrongResidence
        }
        advance(to: now)
        let id = UUID()
        intent = PhysicalIntent(id: id, destination: destination, baseRevision: UInt32(companion.revision),
            snapshot: destination == .device ? companion.state : nil, released: false)
        companion.pendingTransfer = TransferOffer(id: id, petID: companion.petID, source: companion.residence,
            destination: destination, revision: companion.revision + 1, createdAt: now, state: companion.state)
    }

    public mutating func acceptPrepared(_ board: BoardRecord) throws {
        try matches(board)
        guard var pending = intent else { throw CompanionError.noTransfer }
        let prepared: UInt32 = pending.destination == .phone ? 1 : 3
        let completed: UInt32 = pending.destination == .phone ? 2 : 0
        guard (board.phase == prepared && board.revision == pending.baseRevision) ||
              (board.phase == completed && board.revision == pending.baseRevision + 1) else {
            throw PhysicalError.message("挂件没有确认这次交接，请继续原来的旅程。")
        }
        if pending.destination == .phone {
            if let saved = pending.snapshot, saved != board.state { throw CompanionError.invalidState }
            pending.snapshot = board.state
        } else {
            // A completed return may already be ticking on the board; compare staged hash instead.
            guard let saved = pending.snapshot, board.payloadHash == saved.handoffHash else {
                throw CompanionError.invalidState
            }
        }
        intent = pending
    }

    public mutating func releaseForReturn() throws {
        guard var pending = intent, pending.destination == .device, pending.snapshot != nil else {
            throw CompanionError.noTransfer
        }
        pending.released = true
        intent = pending
    }

    public mutating func finish(_ board: BoardRecord, now: Date = Date()) throws {
        try matches(board)
        guard let pending = intent, let snapshot = pending.snapshot,
              board.revision == pending.baseRevision + 1,
              board.phase == (pending.destination == .phone ? 2 : 0),
              pending.destination == .phone || pending.released,
              board.payloadHash == snapshot.handoffHash else { throw CompanionError.noTransfer }
        companion.state = pending.destination == .phone ? snapshot : board.state
        companion.residence = pending.destination
        companion.revision = UInt64(board.revision)
        companion.updatedAt = now // Transfer time is frozen, never counted twice.
        companion.lastActionAt = nil
        companion.lastCompletedTransferID = pending.id
        companion.pendingTransfer = nil
        companion.journal.insert(JourneyEntry(date: now,
            title: pending.destination == .phone ? "从真实挂件来到手机" : "带着新状态回到挂件",
            detail: "同一只宠物，心情、精力和睡眠状态一起到达。", symbol: "arrow.left.arrow.right"), at: 0)
        companion.journal = Array(companion.journal.prefix(100))
        intent = nil
    }

    private func matches(_ board: BoardRecord) throws {
        try board.validate()
        guard let pending = intent, board.petID == companion.petID, board.transferID == pending.id else {
            throw PhysicalError.message("交接编号不匹配，暂时停止并保留记录。")
        }
    }

    public func validate() throws {
        try companion.state.validate()
        guard companion.revision < UInt32.max else { throw CompanionError.invalidState }
        if let pending = intent {
            guard pending.baseRevision == companion.revision,
                  pending.destination != companion.residence,
                  companion.pendingTransfer?.id == pending.id else { throw CompanionError.invalidState }
            try pending.snapshot?.validate()
        } else {
            guard companion.pendingTransfer == nil else { throw CompanionError.invalidState }
        }
    }
}

extension FirmwareState {
    public var handoffHash: UInt32 {
        let words: [UInt32] = [UInt32(energy), UInt32(happiness), UInt32(experience), UInt32(coins),
            UInt32(level), stage, isSleeping ? 1 : 0, UInt32(lowEnergyAwakeSeconds), secondsSinceFeed,
            awakeDecayElapsedSeconds, sleepRecoveryElapsedSeconds, gameTimeSeconds, rngState, feedback]
        var crc: UInt32 = .max
        for word in words {
            for shift in stride(from: 0, to: 32, by: 8) {
                crc ^= (word >> shift) & 255
                for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xedb88320 : 0) }
            }
        }
        return crc ^ .max
    }
}

public struct PhysicalRepository {
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }
    public func load() throws -> PhysicalSession? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let value = try JSONDecoder().decode(PhysicalSession.self, from: Data(contentsOf: fileURL))
        try value.validate()
        return value
    }
    public func save(_ session: PhysicalSession) throws {
        try session.validate()
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(session).write(to: fileURL, options: .atomic)
    }
}
