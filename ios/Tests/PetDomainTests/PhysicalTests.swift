import XCTest
@testable import PetDomain

final class PhysicalTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_793_491_200)
    let petID = UUID()
    func board(phase: UInt32, revision: UInt32, tx: UUID = UUID(), state: FirmwareState = FirmwareState(), hash: UInt32? = nil) -> BoardRecord {
        BoardRecord(v: 2, ok: true, error: "", petID: petID, phase: phase, revision: revision,
                    transferID: tx, payloadHash: hash ?? state.handoffHash, state: state)
    }
    func durable(_ session: PhysicalSession) throws -> PhysicalSession {
        let repo = PhysicalRepository(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("physical.json"))
        defer { try? FileManager.default.removeItem(at: repo.fileURL.deletingLastPathComponent()) }
        try repo.save(session)
        return try XCTUnwrap(repo.load())
    }
    func testRealRoundtripRequiresBothReceiptsAndPreservesAllFields() throws {
        var source = FirmwareState(); source.secondsSinceFeed = 1234
        source.awakeDecayElapsedSeconds = 234; source.rngState = 987654
        var session = try PhysicalSession(board: board(phase: 0, revision: 0, state: source), now: now)
        session.advance(to: now.addingTimeInterval(300))
        XCTAssertEqual(session.companion.state, source) // Board-owned copy NEVER simulates.
        try session.begin(to: .phone, now: now)
        let take = try XCTUnwrap(session.intent)
        XCTAssertThrowsError(try session.care(.play))
        session = try durable(session)
        try session.acceptPrepared(board(phase: 1, revision: 0, tx: take.id, state: source))
        session = try durable(session)
        XCTAssertFalse(session.companion.canInteract)
        try session.finish(board(phase: 2, revision: 1, tx: take.id, state: source), now: now)
        XCTAssertEqual(session.companion.state, source)
        XCTAssertTrue(try session.care(.play, at: now))
        XCTAssertTrue(try session.care(.pet, at: now))
        XCTAssertEqual(session.companion.state.energy, 68)
        XCTAssertEqual(session.companion.state.happiness, 100)
        try session.begin(to: .device, now: now)
        let back = try XCTUnwrap(session.intent)
        let updated = try XCTUnwrap(back.snapshot)
        session = try durable(session)
        try session.acceptPrepared(board(phase: 3, revision: 1, tx: back.id, state: updated))
        XCTAssertThrowsError(try session.finish(board(phase: 0, revision: 2, tx: back.id, state: updated)))
        try session.releaseForReturn()
        session = try durable(session)
        // A lost commit response: retry against a board which is already ticking.
        var ticking = updated; ticking.advance(seconds: 2)
        let receipt = board(phase: 0, revision: 2, tx: back.id, state: ticking, hash: updated.handoffHash)
        try session.acceptPrepared(receipt)
        try session.finish(receipt, now: now)
        XCTAssertEqual(session.companion.state, ticking)
        XCTAssertEqual(session.companion.petID, petID)
        XCTAssertEqual(session.companion.residence, .device)
        XCTAssertNil(session.intent)
    }
    func testWrongRevisionHashAndUnknownOwnerFailClosed() throws {
        XCTAssertThrowsError(try PhysicalSession(board: board(phase: 2, revision: 1)))
        var session = try PhysicalSession(board: board(phase: 0, revision: 0), now: now)
        XCTAssertThrowsError(try session.observe(board(phase: 0, revision: 2)))
        try session.begin(to: .phone, now: now)
        let tx = try XCTUnwrap(session.intent).id
        XCTAssertThrowsError(try session.acceptPrepared(board(phase: 1, revision: 0)))
        try session.acceptPrepared(board(phase: 1, revision: 0, tx: tx))
        XCTAssertThrowsError(try session.finish(board(phase: 2, revision: 1, tx: tx, hash: 0)))
        XCTAssertFalse(session.companion.canInteract)
    }
    func testPendingRestartFreezesElapsedTimeAndCannotChangeDestination() throws {
        var session = try PhysicalSession(board: board(phase: 0, revision: 0), now: now)
        try session.begin(to: .phone, now: now)
        let id = session.intent?.id
        session = try durable(session)
        session.advance(to: now.addingTimeInterval(100000))
        XCTAssertEqual(session.companion.state.energy, 80)
        try session.begin(to: .phone, now: now)
        XCTAssertEqual(session.intent?.id, id)
        XCTAssertThrowsError(try session.begin(to: .device, now: now))
    }
}
