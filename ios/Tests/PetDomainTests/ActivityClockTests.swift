import XCTest
@testable import PetDomain
final class ActivityClockTests:XCTestCase {
    func date(_ s:String) -> Date { ISO8601DateFormatter().date(from:s)! }
    func receipt(day:UInt32) throws -> ActivityReward {
        let json="{\"day\":\(day),\"progressSeconds\":12,\"earnedToday\":0,\"intervalSeconds\":60,\"profile\":3,\"configuredProfile\":3,\"issuedTotal\":0,\"lifetimeEnabled\":true,\"offlineClockSupported\":true,\"clockReady\":false}"
        return try JSONDecoder().decode(ActivityReward.self,from:Data(json.utf8))
    }
    func testLocal8BoundaryAndOrdinalsMatchServerCalendar() throws {
        let before=try ActivityClockPlan.make(now:date("2026-11-08T06:59:59Z"),timeZone:"Europe/Stockholm")
        let after=try ActivityClockPlan.make(now:date("2026-11-08T07:00:00Z"),timeZone:"Europe/Stockholm")
        XCTAssertEqual(after.day,before.day+1);XCTAssertEqual(before.nextEpoch,before.epoch+1)
        XCTAssertEqual(after.nextEpoch,after.epoch+86400)
        let midnight=try ActivityClockPlan.make(now:date("2026-11-08T23:30:00Z"),timeZone:"Europe/Stockholm")
        XCTAssertEqual(midnight.day,after.day)
    }
    func testTenYearPlanIncludes23And25HourExceptions() throws {
        let plan=try ActivityClockPlan.make(now:date("2026-11-08T10:00:00Z"),timeZone:"Europe/Stockholm")
        XCTAssertTrue(plan.exceptions.contains{$0.1==82800});XCTAssertTrue(plan.exceptions.contains{$0.1==90000})
        XCTAssertLessThanOrEqual(plan.exceptions.count,24)
        XCTAssertGreaterThan(plan.validUntil-plan.epoch,86400*365*9)
        let utc=try ActivityClockPlan.make(now:date("2026-11-08T10:00:00Z"),timeZone:"UTC")
        XCTAssertTrue(utc.exceptions.isEmpty)
    }
    func testClockFrameFitsBLEBridgeAndHasValidCRC() throws {
        let plan=try ActivityClockPlan.make(now:date("2026-11-08T10:00:00Z"),timeZone:"Europe/Stockholm")
        let r=try receipt(day:plan.day),payload=try plan.payload(receipt:r)
        let intent=PhysicalIntent(id:UUID(),destination:.device,baseRevision:5,snapshot:nil,released:false)
        let bytes=try BoardWire.request(path:"/activity/clock/"+payload,requestID:UUID(),intent:intent,petID:UUID())
        XCTAssertLessThan(bytes.count,1024)
        let fields=String(decoding:bytes,as:UTF8.self).trimmingCharacters(in:.newlines).split(separator:"|",omittingEmptySubsequences:false)
        XCTAssertEqual(fields[1],"CLOCK_SET")
        XCTAssertEqual(UInt32(fields[6],radix:16),BoardWire.crc32(Data(fields[0...5].joined(separator:"|").utf8)))
        XCTAssertThrowsError(try plan.payload(receipt:receipt(day:plan.day+1)))
    }
    func testInvalidZoneAndIncompleteCounterCannotBeUsed() throws {
        XCTAssertThrowsError(try ActivityClockPlan.make(now:date("2026-11-08T10:00:00Z"),timeZone:"Invalid/Zone"))
        let json="{\"day\":739928,\"progressSeconds\":0,\"earnedToday\":0,\"intervalSeconds\":60,\"profile\":3,\"lifetimeEnabled\":true}"
        let r=try JSONDecoder().decode(ActivityReward.self,from:Data(json.utf8))
        XCTAssertThrowsError(try r.validate())
    }
}
