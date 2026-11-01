import XCTest
@testable import PetDomain

final class CompanionTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_793_491_200)

    func atPhone(state: FirmwareState = FirmwareState()) throws -> CompanionSession {
        var session = CompanionSession(now: now, state: state)
        let offer = try session.beginTransfer(to: .phone, at: now)
        try session.completeTransfer(id: offer.id, at: now)
        return session
    }

    func testUsesFirmwareRulesAndBounds() throws {
        var session = try atPhone()
        XCTAssertEqual(session.state.happiness, 75)
        XCTAssertEqual(session.state.energy, 80)
        XCTAssertTrue(try session.care(.pet, at: now))
        XCTAssertEqual(session.state.happiness, 85)
        XCTAssertTrue(try session.care(.play, at: now))
        XCTAssertEqual(session.state.happiness, 100)
        XCTAssertEqual(session.state.energy, 68)
        XCTAssertTrue(try session.care(.feed, at: now))
        XCTAssertEqual(session.state.energy, 98)
        _ = try session.care(.feed, at: now)
        XCTAssertEqual(session.state.energy, 100)
    }

    func testSleepingIgnoresOrdinaryCareAndRecovers() throws {
        var session = try atPhone()
        _ = try session.care(.sleep, at: now)
        XCTAssertFalse(try session.care(.pet, at: now))
        XCTAssertFalse(try session.care(.feed, at: now))
        session.advance(to: now.addingTimeInterval(120))
        XCTAssertEqual(session.state.energy, 82)
        XCTAssertEqual(session.state.happiness, 75)
        XCTAssertTrue(session.state.isSleeping)
    }

    func testDailyCollapseAndFeedRescueMatchFirmware() throws {
        var session = try atPhone()
        session.advance(to: now.addingTimeInterval(86_400))
        XCTAssertTrue(session.state.isCollapsed)
        XCTAssertEqual(session.state.energy, 0)
        XCTAssertFalse(try session.care(.pet, at: now.addingTimeInterval(86_400)))
        XCTAssertTrue(try session.care(.feed, at: now.addingTimeInterval(86_400)))
        XCTAssertFalse(session.state.isCollapsed)
        XCTAssertFalse(session.state.isSleeping)
        XCTAssertEqual(session.state.energy, 30)
    }

    func testAutoSleepAfterThreeSeconds() {
        var state = FirmwareState()
        state.energy = 10
        state.advance(seconds: 2)
        XCTAssertFalse(state.isSleeping)
        state.advance(seconds: 1)
        XCTAssertTrue(state.isSleeping)
    }

    func testRoundTripPreservesEveryStateFieldAndIdentity() throws {
        var session = try atPhone()
        _ = try session.care(.play, at: now)
        _ = try session.care(.sleep, at: now)
        session.advance(to: now.addingTimeInterval(33))
        let original = session.state
        let identity = session.petID
        let time = now.addingTimeInterval(33)
        let home = try session.beginTransfer(to: .device, at: time)
        XCTAssertEqual(home.state, original)
        try session.completeTransfer(id: home.id, at: time)
        let visit = try session.beginTransfer(to: .phone, at: time)
        try session.completeTransfer(id: visit.id, at: time)
        XCTAssertEqual(session.state, original)
        XCTAssertEqual(session.petID, identity)
        XCTAssertEqual(session.residence, .phone)
        XCTAssertTrue(session.state.isSleeping)
    }

    func testPendingTransferBlocksCommandsAndDuplicateBeginIsIdempotent() throws {
        var session = CompanionSession(now: now)
        let offer = try session.beginTransfer(to: .phone, at: now)
        let repeated = try session.beginTransfer(to: .phone, at: now.addingTimeInterval(50))
        XCTAssertEqual(offer, repeated)
        XCTAssertThrowsError(try session.care(.pet, at: now))
        XCTAssertThrowsError(try session.beginTransfer(to: .device, at: now))
        XCTAssertFalse(session.canInteract)
        XCTAssertEqual(session.residence, .device)
    }

    func testWrongReceiptCannotChangeOwner() throws {
        var session = CompanionSession(now: now)
        _ = try session.beginTransfer(to: .phone, at: now)
        let original = session
        XCTAssertThrowsError(try session.completeTransfer(id: UUID(), at: now))
        XCTAssertEqual(session, original)
    }

    func testRepeatedReceiptDoesNotDuplicateArrivalOrAdvanceAgain() throws {
        var session = CompanionSession(now: now)
        let offer = try session.beginTransfer(to: .phone, at: now)
        try session.completeTransfer(id: offer.id, at: now)
        let completed = session
        try session.completeTransfer(id: offer.id, at: now.addingTimeInterval(60))
        XCTAssertEqual(session, completed)
    }

    func testInterruptedOfferSurvivesRestartAndCanResume() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = SessionRepository(fileURL: directory.appendingPathComponent("session.json"))
        var original = CompanionSession(now: now)
        let offer = try original.beginTransfer(to: .phone, at: now)
        try repository.save(original)
        var restored = try XCTUnwrap(repository.load())
        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.pendingTransfer?.id, offer.id)
        try restored.completeTransfer(id: offer.id, at: now.addingTimeInterval(3_600))
        XCTAssertEqual(restored.residence, .phone)
        XCTAssertEqual(restored.state.energy, 79)
        XCTAssertEqual(restored.state.happiness, 74)
        XCTAssertEqual(restored.petID, original.petID)
    }

    func testCancellingSimulationPreservesOwnerAndElapsedTime() throws {
        var session = CompanionSession(now: now)
        _ = try session.beginTransfer(to: .phone, at: now)
        session.cancelSimulatedTransfer(at: now.addingTimeInterval(3_600))
        XCTAssertEqual(session.residence, .device)
        XCTAssertNil(session.pendingTransfer)
        XCTAssertEqual(session.state.energy, 79)
    }

    func testClockGoingBackDoesNotReverseTimeOrLoseFractions() throws {
        var session = try atPhone()
        session.advance(to: now.addingTimeInterval(0.9))
        session.advance(to: now.addingTimeInterval(1.2))
        XCTAssertEqual(session.state.gameTimeSeconds, 1)
        session.advance(to: now.addingTimeInterval(-100))
        session.advance(to: now.addingTimeInterval(2.1))
        XCTAssertEqual(session.state.gameTimeSeconds, 2)
    }

    func testCannotCareForDeviceCopy() {
        var session = CompanionSession(now: now)
        let original = session
        XCTAssertThrowsError(try session.care(.feed, at: now))
        XCTAssertEqual(session, original)
    }

    func testInvalidSaveRejectedAndOriginalCanBeBackedUp() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("session.json")
        let original = Data("not a valid save".utf8)
        try original.write(to: url)
        let repository = SessionRepository(fileURL: url)
        XCTAssertThrowsError(try repository.load())
        let backup = try XCTUnwrap(repository.backUpUnreadableSave())
        XCTAssertEqual(try Data(contentsOf: backup), original)
        XCTAssertEqual(try Data(contentsOf: url), original)
        var invalid = FirmwareState()
        invalid.energy = 101
        XCTAssertThrowsError(try repository.save(CompanionSession(now: now, state: invalid)))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testRendererProducesFullFrameWithoutMutatingState() {
        let state = FirmwareState()
        let pixels = state.pixels(animationTime: 8, feedbackAge: 10)
        XCTAssertEqual(pixels.count, 1024)
        XCTAssertTrue(pixels.contains { $0 != 0 })
        XCTAssertEqual(state, FirmwareState())
    }
}
