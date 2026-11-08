import XCTest
@testable import PetDomain
final class ActivityRewardTests:XCTestCase {
    func receipt(day:UInt32=739928,progress:UInt32=12,earned:UInt32=1,interval:UInt32=600) throws -> ActivityReward {
        let json="{\"day\":\(day),\"progressSeconds\":\(progress),\"earnedToday\":\(earned),\"intervalSeconds\":\(interval)}"
        return try JSONDecoder().decode(ActivityReward.self,from:Data(json.utf8))
    }
    func testBothProfilesAndInvalidCounts() throws {
        try receipt().validate();try receipt(interval:30).validate()
        XCTAssertThrowsError(try receipt(earned:4).validate())
        XCTAssertThrowsError(try receipt(progress:600).validate())
        XCTAssertThrowsError(try receipt(interval:60).validate())
        XCTAssertThrowsError(try receipt(day:0).validate())
        try receipt(day:0,progress:0,earned:0).validate()
    }
    func testCalendarAcknowledgementIsBoundToPetAndExactReceipt() throws {
        let pet=UUID(),r=try receipt()
        let json="{\"petID\":\"\(pet)\",\"day\":739929,\"dayLabel\":\"2026-11-09\",\"timezone\":\"Europe/Stockholm\",\"intervalSeconds\":600,\"ackDay\":739928,\"ackEarned\":1,\"granted\":1}"
        let ack=try JSONDecoder().decode(ActivitySyncInfo.self,from:Data(json.utf8))
        XCTAssertEqual(try ack.path(for:pet,receipt:r),"/activity/sync/739929/739928/1")
        XCTAssertThrowsError(try ack.path(for:UUID(),receipt:r))
        XCTAssertThrowsError(try ack.path(for:pet,receipt:receipt(earned:2)))
    }
    func testSyncFramePayloadAndCRC() throws {
        let id=UUID(),intent=PhysicalIntent(id:UUID(),destination:.device,baseRevision:4,snapshot:nil,released:false)
        let data=try BoardWire.request(path:"/activity/sync/739929/739928/3",requestID:id,intent:intent,petID:UUID())
        let fields=String(decoding:data,as:UTF8.self).trimmingCharacters(in:.newlines).split(separator:"|",omittingEmptySubsequences:false)
        XCTAssertEqual(fields[1],"ACTIVITY_SYNC");XCTAssertEqual(fields[5],"739929,739928,3")
        XCTAssertEqual(UInt32(fields[6],radix:16),BoardWire.crc32(Data(fields[0...5].joined(separator:"|").utf8)))
        XCTAssertThrowsError(try BoardWire.request(path:"/activity/sync/739929/739928/4",requestID:id,intent:intent,petID:UUID()))
    }
}
