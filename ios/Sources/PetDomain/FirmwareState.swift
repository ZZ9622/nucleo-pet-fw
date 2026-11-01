import Foundation
import CPetCore

public enum CareAction: String, Codable, CaseIterable {
    case feed, pet, play, sleep

    var native: PetCommandType {
        switch self {
        case .feed: return PET_CMD_FEED
        case .pet: return PET_CMD_PET
        case .play: return PET_CMD_PLAY
        case .sleep: return PET_CMD_SLEEP_TOGGLE
        }
    }
}

/// Complete firmware state, including fractional rule timers and RNG state.
/// PetSnapshot alone is intentionally insufficient for a handoff.
public struct FirmwareState: Codable, Equatable {
    public var energy: UInt8
    public var happiness: UInt8
    public var experience: UInt16
    public var coins: UInt16
    public var level: UInt8
    public var stage: UInt32
    public var isSleeping: Bool
    public var lowEnergyAwakeSeconds: UInt8
    public var secondsSinceFeed: UInt32
    public var awakeDecayElapsedSeconds: UInt32
    public var sleepRecoveryElapsedSeconds: UInt32
    public var gameTimeSeconds: UInt32
    public var rngState: UInt32
    public var feedback: UInt32

    public init(seed: UInt32 = 0x4010F00D) {
        var state = PetState()
        pet_init(&state, seed)
        self.init(native: state)
    }

    init(native: PetState) {
        energy = native.energy
        happiness = native.happiness
        experience = native.experience
        coins = native.coins
        level = native.level
        stage = native.stage.rawValue
        isSleeping = native.is_sleeping
        lowEnergyAwakeSeconds = native.low_energy_awake_s
        secondsSinceFeed = native.seconds_since_feed
        awakeDecayElapsedSeconds = native.awake_decay_elapsed_s
        sleepRecoveryElapsedSeconds = native.sleep_recovery_elapsed_s
        gameTimeSeconds = native.game_time_s
        rngState = native.rng_state
        feedback = native.feedback.rawValue
    }

    var native: PetState {
        var state = PetState()
        state.energy = energy
        state.happiness = happiness
        state.experience = experience
        state.coins = coins
        state.level = level
        state.stage = PetLifeStage(rawValue: stage)
        state.is_sleeping = isSleeping
        state.low_energy_awake_s = lowEnergyAwakeSeconds
        state.seconds_since_feed = secondsSinceFeed
        state.awake_decay_elapsed_s = awakeDecayElapsedSeconds
        state.sleep_recovery_elapsed_s = sleepRecoveryElapsedSeconds
        state.game_time_s = gameTimeSeconds
        state.rng_state = rngState
        state.feedback = PetEvent(rawValue: feedback)
        return state
    }

    public var isCollapsed: Bool { secondsSinceFeed >= 86_400 }

    public var moodTitle: String {
        if isCollapsed { return "有点饿了" }
        if isSleeping { return "正在做梦" }
        if min(energy, happiness) <= 20 { return "想被照顾一下" }
        if min(energy, happiness) <= 50 { return "安静待一会儿" }
        if energy >= 75 && happiness >= 75 { return "今天很开心" }
        return "自在的小日子"
    }

    public func validate() throws {
        guard energy <= 100, happiness <= 100, (1...99).contains(level),
              stage <= 2, feedback <= 10, lowEnergyAwakeSeconds <= 3,
              secondsSinceFeed <= 86_400, awakeDecayElapsedSeconds < 3_600,
              sleepRecoveryElapsedSeconds < 60,
              !isCollapsed || energy == 0 else {
            throw CompanionError.invalidState
        }
    }

    @discardableResult
    public mutating func apply(_ action: CareAction) -> Bool {
        var state = native
        var rules = PET_RULES_DEFAULT
        var command = PetCommand()
        command.type = action.native
        var transition = PetTransition()
        pet_apply(&state, &rules, &command, &transition)
        self = FirmwareState(native: state)
        return transition.count > 0
    }

    public mutating func advance(seconds: UInt32) {
        var state = native
        var rules = PET_RULES_DEFAULT
        var transition = PetTransition()
        pet_advance(&state, &rules, seconds, &transition)
        self = FirmwareState(native: state)
    }

    /// Original 128×64 SSD1306 page buffer, drawn by the unchanged C renderer.
    public func pixels(animationTime: TimeInterval, feedbackAge: TimeInterval) -> [UInt8] {
        var state = native
        var snapshot = PetSnapshot()
        pet_make_snapshot(&state, &snapshot)
        snapshot.feedback_elapsed_ms = Self.milliseconds(feedbackAge)
        if feedbackAge >= 2.5 { snapshot.feedback = PET_EVENT_NONE }
        var frame = [UInt8](repeating: 0, count: 1024)
        frame.withUnsafeMutableBufferPointer { buffer in
            pet_view_draw(buffer.baseAddress, &snapshot, Self.milliseconds(animationTime))
        }
        return frame
    }

    private static func milliseconds(_ seconds: TimeInterval) -> UInt32 {
        guard seconds.isFinite else { return UInt32.max }
        return UInt32((max(0, seconds) * 1_000).truncatingRemainder(dividingBy: 4_294_967_296))
    }
}
