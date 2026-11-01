import Foundation

public enum Residence: String, Codable {
    case device, phone
    public var title: String { self == .device ? "挂件" : "手机小屋" }
}

public enum CompanionError: LocalizedError {
    case invalidState, transferInProgress, wrongResidence, noTransfer, unsupportedSave

    public var errorDescription: String? {
        switch self {
        case .invalidState: return "这份宠物记录不完整，暂时不能使用。"
        case .transferInProgress: return "它还在路上，等旅程完成再互动吧。"
        case .wrongResidence: return "它还在挂件里，先接到手机小屋吧。"
        case .noTransfer: return "这次旅程已经变化，请重新查看。"
        case .unsupportedSave: return "这份记录来自其他版本，请保留原记录。"
        }
    }
}

public struct JourneyEntry: Identifiable, Codable, Equatable {
    public let id: UUID
    public let date: Date
    public let title: String
    public let detail: String
    public let symbol: String

    public init(date: Date, title: String, detail: String, symbol: String) {
        self.id = UUID()
        self.date = date
        self.title = title
        self.detail = detail
        self.symbol = symbol
    }
}

public struct TransferOffer: Codable, Equatable, Identifiable {
    public let id: UUID
    public let petID: UUID
    public let source: Residence
    public let destination: Residence
    public let revision: UInt64
    public let createdAt: Date
    public let state: FirmwareState
}

/// An offline prototype with ONE authoritative pet. Device residence is simulated.
/// Production transport must implement durable prepare/receipt/commit on both peers.
public struct CompanionSession: Codable, Equatable {
    public let petID: UUID
    public var name: String
    public internal(set) var state: FirmwareState
    public internal(set) var residence: Residence
    public internal(set) var revision: UInt64
    public internal(set) var pendingTransfer: TransferOffer?
    public internal(set) var lastCompletedTransferID: UUID?
    public internal(set) var updatedAt: Date
    public internal(set) var lastActionAt: Date?
    public let createdAt: Date
    public internal(set) var journal: [JourneyEntry]

    public init(name: String = "方方", now: Date = Date(), state: FirmwareState = FirmwareState(), petID: UUID = UUID(), residence: Residence = .device, revision: UInt64 = 0) {
        self.petID = petID
        self.name = name
        self.state = state
        self.residence = residence
        self.revision = revision
        updatedAt = now
        createdAt = now
        journal = [JourneyEntry(date: now, title: "遇见方方", detail: "从一块小小的像素屏，开始我们的故事。", symbol: "sparkles")]
    }

    public var canInteract: Bool { residence == .phone && pendingTransfer == nil }

    public mutating func advance(to now: Date) {
        guard pendingTransfer == nil else { return }
        let interval = now.timeIntervalSince(updatedAt)
        guard interval >= 1, interval.isFinite else { return }
        let seconds = UInt32(min(interval.rounded(.down), Double(UInt32.max)))
        state.advance(seconds: seconds)
        updatedAt = updatedAt.addingTimeInterval(Double(seconds))
        if let actionAt = lastActionAt, now.timeIntervalSince(actionAt) >= 2.5 {
            state.feedback = 0
        }
    }

    @discardableResult
    public mutating func care(_ action: CareAction, at now: Date = Date()) throws -> Bool {
        guard pendingTransfer == nil else { throw CompanionError.transferInProgress }
        guard residence == .phone else { throw CompanionError.wrongResidence }
        advance(to: now)
        let accepted = state.apply(action)
        guard accepted else { return false }
        lastActionAt = now
        let text: (String, String, String)
        switch action {
        case .feed: text = ("吃了一口小点心", "精力补充好了，继续陪你。", "carrot")
        case .pet: text = ("被温柔地摸摸", "方方把这份喜欢，悄悄收好了。", "heart")
        case .play: text = ("一起玩了一会儿", "小小的跳跃，大大的开心。", "tennisball")
        case .sleep: text = state.isSleeping
            ? ("开始做一个好梦", "休息的时候，精力会慢慢恢复。", "moon")
            : ("伸了个懒腰", "醒来第一眼，就看见了你。", "sun.max")
        }
        record(JourneyEntry(date: now, title: text.0, detail: text.1, symbol: text.2))
        return true
    }

    @discardableResult
    public mutating func beginTransfer(to destination: Residence, at now: Date = Date()) throws -> TransferOffer {
        if let offer = pendingTransfer {
            guard offer.destination == destination else { throw CompanionError.transferInProgress }
            return offer
        }
        guard destination != residence else { throw CompanionError.wrongResidence }
        advance(to: now)
        let offer = TransferOffer(id: UUID(), petID: petID, source: residence,
            destination: destination, revision: revision + 1, createdAt: now, state: state)
        pendingTransfer = offer
        return offer
    }

    /// Called only after the simulated receiver acknowledges durable receipt.
    /// Repeated receipt for the last completed ID has no effect.
    public mutating func completeTransfer(id: UUID, at now: Date = Date()) throws {
        if id == lastCompletedTransferID { return }
        guard let offer = pendingTransfer, offer.id == id,
              offer.petID == petID, offer.source == residence,
              offer.revision == revision + 1, offer.state == state else {
            throw CompanionError.noTransfer
        }
        try offer.state.validate()
        residence = offer.destination
        revision = offer.revision
        lastCompletedTransferID = id
        pendingTransfer = nil
        advance(to: now)
        record(JourneyEntry(date: now,
            title: residence == .phone ? "来手机小屋做客" : "回到随身挂件",
            detail: residence == .phone ? "带着原来的心情和精力，换个地方陪你。" : "口袋里的小世界，又有了它的身影。",
            symbol: residence == .phone ? "door.left.hand.open" : "arrow.turn.up.left"))
    }

    /// Only safe in this single-process simulator: no external receiver owns a copy.
    public mutating func cancelSimulatedTransfer(at now: Date = Date()) {
        pendingTransfer = nil
        advance(to: now)
    }

    public func validate() throws {
        try state.validate()
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 24, revision < UInt64.max,
              updatedAt.timeIntervalSince1970.isFinite,
              createdAt.timeIntervalSince1970.isFinite else { throw CompanionError.invalidState }
        if let offer = pendingTransfer {
            guard offer.petID == petID, offer.source == residence,
                  offer.destination != residence, offer.revision == revision + 1,
                  offer.state == state else { throw CompanionError.invalidState }
            try offer.state.validate()
        }
    }

    private mutating func record(_ entry: JourneyEntry) {
        journal.insert(entry, at: 0)
        journal = Array(journal.prefix(100))
    }
}
