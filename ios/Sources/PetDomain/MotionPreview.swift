import Foundation

/// Visual-only sensor simulator. Owns no CompanionSession and cannot save or transfer a pet.
public struct MotionPreview {
    public enum Action: String, CaseIterable, Identifiable {
        case walk, stop, shake
        public var id: String { rawValue }
        public var title: String {
            switch self { case .walk: return "模拟走路"; case .stop: return "停止"; case .shake: return "轻晃" }
        }
    }
    public enum Behavior: String {
        case walking, idle, surprised
        public var title: String {
            switch self { case .walking: return "正在走路"; case .idle: return "停下休息"; case .surprised: return "咦？轻轻晃了一下" }
        }
    }
    public private(set) var action: Action = .stop
    public private(set) var eventNumber = 0
    private var startedAt: TimeInterval = 0
    private var resumeWalking = false
    public init() {}

    /// Pass a monotonic clock (systemUptime), independent of phone clock changes.
    public mutating func send(_ action: Action, at time: TimeInterval) {
        guard time.isFinite else { return }
        if action == .shake { resumeWalking = behavior(at: time) == .walking || (self.action == .shake && resumeWalking) }
        else { resumeWalking = action == .walk }
        self.action = action
        startedAt = time
        eventNumber += 1
    }
    public func behavior(at time: TimeInterval) -> Behavior {
        if action == .shake && elapsed(time) < 0.9 { return .surprised }
        if action == .walk || (action == .shake && resumeWalking) { return .walking }
        return .idle
    }
    private func elapsed(_ time: TimeInterval) -> TimeInterval {
        guard time.isFinite else { return 0 }
        return max(0, time - startedAt)
    }
    public func pixels(at time: TimeInterval, reduceMotion: Bool = false) -> [UInt8] {
        let behavior = behavior(at: time)
        let age = elapsed(time)
        let animation: Double
        if behavior == .walking {
            // Sample the firmware's actual walk sequence, including alternating feet.
            animation = reduceMotion ? 7.6 : 7 + age.truncatingRemainder(dividingBy: 3.2)
        } else { animation = reduceMotion ? 0 : age.truncatingRemainder(dividingBy: 2) }
        let source = FirmwareState().pixels(animationTime: animation, feedbackAge: 100)
        guard behavior == .surprised else { return source }
        var frame = source
        func set(_ x: Int, _ y: Int, _ on: Bool) {
            guard (0..<128).contains(x), (0..<64).contains(y) else { return }
            let mask = UInt8(1 << (y % 8))
            if on { frame[y / 8 * 128 + x] |= mask } else { frame[y / 8 * 128 + x] &= ~mask }
        }
        // Discrete pixel sway, never a smooth scaling or rotation of the sprite.
        let offsets = [0, -2, 2, -3, 3, -1, 1, 0, 0]
        let step = min(8, Int(age * 10))
        let dx = reduceMotion ? 0 : offsets[step]
        let dy = reduceMotion ? 0 : (step % 2 == 0 ? -2 : 0)
        for y in 19..<64 { for x in 30..<107 { set(x, y, false) } }
        for y in 19..<64 {
            for x in 30..<107 where source[y / 8 * 128 + x] & (1 << (y % 8)) != 0 { set(x + dx, y + dy, true) }
        }
        for y in 22..<28 { for x in 87..<89 { set(x, y, true) } }
        for x in 87..<89 { set(x, 30, true) }
        return frame
    }
}
