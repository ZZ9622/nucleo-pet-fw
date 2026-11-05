import Foundation

/// The same version-2 UART frames used by STM32, carried unchanged over BLE.
public enum BoardWire {
    public static let serviceUUID = "A27C38E1-9447-454A-898F-F1B8719391E3"
    public static let characteristicUUID = "87A0909E-5440-4883-A0B9-5FB589496AD8"
    public static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = .max
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xedb88320 : 0) }
        }
        return crc ^ .max
    }
    public static func hex(_ id: UUID) -> String { id.uuidString.replacingOccurrences(of: "-", with: "").lowercased() }
    public static func request(path: String, requestID: UUID, intent: PhysicalIntent? = nil, petID: UUID? = nil) throws -> Data {
        let commands = ["/device":"STATUS", "/handoff/take/prepare":"TAKE_PREPARE", "/handoff/take/commit":"TAKE_COMMIT",
                        "/items/open":"ITEM_OPEN", "/items/food1":"ITEM_FOOD1", "/items/food2":"ITEM_FOOD2",
                        "/handoff/return/stage":"RETURN_STAGE", "/handoff/return/commit":"RETURN_COMMIT"]
        guard let command = commands[path] else { throw CompanionError.invalidState }
        if command != "STATUS" {
            guard let intent, petID != nil, intent.baseRevision < UInt32.max,
                  intent.id != UUID(uuidString: "00000000-0000-0000-0000-000000000000") else { throw CompanionError.invalidState }
        }
        var state = ""
        if command == "RETURN_STAGE" {
            guard let snapshot = intent?.snapshot else { throw CompanionError.invalidState }
            try snapshot.validate()
            state = words(snapshot).map(String.init).joined(separator: ",")
        }
        let zero = String(repeating: "0", count: 32)
        let text = "!\(hex(requestID))|\(command)|\(petID.map(hex) ?? zero)|\(intent.map { hex($0.id) } ?? zero)|\(intent?.baseRevision ?? 0)|\(state)"
        let data = Data(text.utf8)
        return data + Data(String(format: "|%08x\n", crc32(data)).utf8)
    }
    public static func decode(_ line: Data, requestID: UUID) throws -> BoardRecord {
        var line = line
        if line.last == 10 { line.removeLast() }
        guard line.count <= 4096, let split = line.lastIndex(of: 124) else { throw CompanionError.invalidState }
        let payload = Data(line[..<split])
        let suffix = line[line.index(after: split)...]
        guard suffix.count == 8, let crcText = String(data: suffix, encoding: .ascii),
              let checksum = UInt32(crcText, radix: 16), checksum == crc32(payload) else { throw CompanionError.invalidState }
        struct Raw: Decodable {
            let v: Int; let requestID: String; let ok: Bool; let error: String
            let petID: String; let phase: UInt32; let revision: UInt32; let transferID: String
            let payloadHash: UInt32; let state: [UInt32]
            let itemOperationID: String?; let itemStatus: UInt32?; let itemKind: UInt32?; let itemLevel: UInt32?
        }
        let raw = try JSONDecoder().decode(Raw.self, from: payload)
        guard raw.v == 2, raw.requestID == hex(requestID), raw.phase <= 4, raw.revision < UInt32.max else { throw CompanionError.invalidState }
        let state = try state(raw.state)
        var value = BoardRecord(v: raw.v, ok: raw.ok, error: raw.error, petID: try uuid(raw.petID),
            phase: raw.phase, revision: raw.revision, transferID: try uuid(raw.transferID), payloadHash: raw.payloadHash, state: state)
        if let op=raw.itemOperationID { value.itemOperationID=try uuid(op) }
        value.itemStatus=raw.itemStatus;value.itemKind=raw.itemKind;value.itemLevel=raw.itemLevel
        try value.validate()
        return value
    }
    private static func uuid(_ text: String) throws -> UUID {
        guard text.count == 32, text.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { throw CompanionError.invalidState }
        var s = text
        for offset in [20,16,12,8] { s.insert("-", at: s.index(s.startIndex, offsetBy: offset)) }
        guard let id = UUID(uuidString: s) else { throw CompanionError.invalidState }
        return id
    }
    private static func words(_ s: FirmwareState) -> [UInt32] {
        [UInt32(s.energy),UInt32(s.happiness),UInt32(s.experience),UInt32(s.coins),UInt32(s.level),s.stage,s.isSleeping ? 1 : 0,
         UInt32(s.lowEnergyAwakeSeconds),s.secondsSinceFeed,s.awakeDecayElapsedSeconds,s.sleepRecoveryElapsedSeconds,s.gameTimeSeconds,s.rngState,s.feedback]
    }
    private static func state(_ w: [UInt32]) throws -> FirmwareState {
        let limits: [UInt32] = [100,100,65535,65535,99,2,1,3,86400,3599,59,.max,.max,10]
        guard w.count == 14, zip(w,limits).allSatisfy({ $0 <= $1 }), w[4] > 0 else { throw CompanionError.invalidState }
        var s = FirmwareState()
        s.energy=UInt8(w[0]);s.happiness=UInt8(w[1]);s.experience=UInt16(w[2]);s.coins=UInt16(w[3]);s.level=UInt8(w[4]);s.stage=w[5]
        s.isSleeping=w[6] != 0;s.lowEnergyAwakeSeconds=UInt8(w[7]);s.secondsSinceFeed=w[8];s.awakeDecayElapsedSeconds=w[9]
        s.sleepRecoveryElapsedSeconds=w[10];s.gameTimeSeconds=w[11];s.rngState=w[12];s.feedback=w[13]
        try s.validate();return s
    }
}

public struct BoardLineBuffer {
    private var bytes = Data()
    private var discarding = false
    public init() {}
    public mutating func append(_ chunk: Data) -> [Data] {
        var lines: [Data] = []
        for byte in chunk {
            if byte == 10 {
                if !discarding && !bytes.isEmpty { lines.append(bytes) }
                bytes.removeAll(keepingCapacity: true);discarding=false
            } else if !discarding {
                bytes.append(byte)
                if bytes.count > 4096 { bytes.removeAll(keepingCapacity: true);discarding=true }
            }
        }
        return lines
    }
}
