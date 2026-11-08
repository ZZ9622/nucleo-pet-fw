import Foundation

/// Live LIS3DH readings. This is transient telemetry, separate from pet ownership.
public struct MotionTelemetry: Codable, Equatable {
    public let connected: Bool
    public let xMg: Int
    public let yMg: Int
    public let zMg: Int
    public let behavior: UInt32
    public let samples: UInt32
    public let ageMs: UInt32
    public let activeMs: UInt32

    public var isFresh: Bool { connected && samples > 0 && ageMs <= 250 }
    public var title: String {
        switch behavior {
        case 1: return "活动"
        case 2: return "晃动"
        default: return "静止"
        }
    }

    public func validate() throws {
        guard (-2048...2047).contains(xMg),
              (-2048...2047).contains(yMg),
              (-2048...2047).contains(zMg),
              behavior <= 2 else { throw CompanionError.invalidState }
    }
}
