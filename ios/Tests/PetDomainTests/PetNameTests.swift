import XCTest
@testable import PetDomain

final class PetNameTests: XCTestCase {
    func testNameValidationAndPersistencePreservePetIdentityAndState() throws {
        var session = CompanionSession()
        let id = session.petID
        let state = session.state
        try session.rename(to: "  团子 🐱  ")
        XCTAssertEqual(session.name, "团子 🐱")
        XCTAssertEqual(session.petID, id)
        XCTAssertEqual(session.state, state)
        for invalid in ["   ", String(repeating: "猫", count: 25), "小\n猫"] {
            XCTAssertThrowsError(try session.rename(to: invalid))
            XCTAssertEqual(session.name, "团子 🐱")
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("session.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = SessionRepository(fileURL: url)
        try repository.save(session)
        XCTAssertEqual(try repository.load()?.name, "团子 🐱")
        XCTAssertEqual(try repository.load()?.petID, id)
    }
    func testRealPetRenamePersistsAndBoardReadKeepsUserName() throws {
        let state = FirmwareState()
        let id = UUID()
        let board = BoardRecord(v: 2, ok: true, error: "", petID: id, phase: 0, revision: 0,
            transferID: UUID(), payloadHash: state.handoffHash, state: state)
        var physical = try PhysicalSession(board: board)
        try physical.rename(to: "豆豆")
        try physical.observe(board)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("physical.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repo = PhysicalRepository(fileURL: url)
        try repo.save(physical)
        let saved = try XCTUnwrap(repo.load())
        XCTAssertEqual(saved.companion.name, "豆豆")
        XCTAssertEqual(saved.companion.petID, id)
        XCTAssertEqual(saved.companion.state, state)
        XCTAssertEqual(saved.companion.revision, 0)
        XCTAssertEqual(saved.companion.residence, .device)
    }
}
