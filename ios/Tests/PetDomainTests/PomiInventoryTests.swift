import XCTest
@testable import PetDomain

final class PomiInventoryTests:XCTestCase {
    func testMergeConsumesThreeMatchingIdleItems() throws {
        var s=PomiInventory();s.items=[.init(kind:"plant"),.init(kind:"plant"),.init(kind:"plant"),.init(kind:"shell")]
        try s.merge(s.items[0].id)
        XCTAssertEqual(s.items.count,2);XCTAssertEqual(s.items.first{$0.kind=="plant"}?.level,2)
        XCTAssertThrowsError(try s.merge(s.items.first{$0.kind=="plant"}!.id))
    }
    func testPlacedAndPendingItemsCannotBeMerged() throws {
        var s=PomiInventory();s.items=(0..<3).map{_ in .init(kind:"plant")}
        try s.decorate(s.items[0].id,slot:"corner")
        XCTAssertThrowsError(try s.merge(s.items[1].id))
        try s.decorate(nil,slot:"corner")
        s.pending = .init(id:"pending",kind:"food",boxID:nil,itemID:s.items[0].id,petID:"pet",reward:nil,level:1)
        XCTAssertThrowsError(try s.merge(s.items[1].id))
        XCTAssertThrowsError(try s.decorate(s.items[0].id,slot:"corner"))
    }
    func testWrongSlotRejectedAndInventoryRoundTrips() throws {
        var s=PomiInventory.preview();let food=s.items.first{$0.kind=="berry"}!
        XCTAssertThrowsError(try s.decorate(food.id,slot:"wall"))
        XCTAssertEqual(try JSONDecoder().decode(PomiInventory.self,from:JSONEncoder().encode(s)),s)
    }
    func testItemWireCommandsAreVersionTwoCRCFrames() throws {
        let op=PhysicalIntent(id:UUID(),destination:.device,baseRevision:10,snapshot:nil,released:false)
        let bytes=try BoardWire.request(path:"/items/open",requestID:UUID(),intent:op,petID:UUID())
        let text=String(decoding:bytes,as:UTF8.self)
        XCTAssertTrue(text.contains("|ITEM_OPEN|"));XCTAssertTrue(text.contains("|10||"))
    }
}
