import XCTest
@testable import PetDomain
final class DailySixTests:XCTestCase {
    func receipt(earned:UInt32,progress:UInt32=0,profile:UInt32=3,configured:UInt32=3,day:UInt32=739928) throws -> ActivityReward {
        let interval=ActivityReward.target(profile:profile,earned:earned)
        let dict:[String:Any] = ["day":day,"earnedToday":earned,"progressSeconds":progress,"profile":profile,
            "configuredProfile":configured,"intervalSeconds":interval,"dailyLimit":profile==3 ? 6:3]
        return try JSONDecoder().decode(ActivityReward.self,from:JSONSerialization.data(withJSONObject:dict))
    }
    func ack(pet:UUID,day:UInt32,ackDay:UInt32,earned:UInt32,profile:UInt32=3,ackProfile:UInt32=3,carry:UInt32=0) throws -> ActivitySyncInfo {
        let dict:[String:Any] = ["petID":pet.uuidString,"day":day,"ackDay":ackDay,"ackEarned":earned,"profile":profile,
            "ackProfile":ackProfile,"carryEarned":carry,"intervalSeconds":60,"granted":0,"dayLabel":"2026-11-08","timezone":"Europe/Stockholm"]
        return try JSONDecoder().decode(ActivitySyncInfo.self,from:JSONSerialization.data(withJSONObject:dict))
    }
    func testStageTargetsAndDailyLimit() throws {
        for i:UInt32 in 0...6 {
            let r=try receipt(earned:i);try r.validate()
            XCTAssertEqual(r.intervalSeconds,ActivityReward.stages[Int(min(i,5))]);XCTAssertEqual(r.limit,6);XCTAssertTrue(r.isDailySix)
        }
        XCTAssertThrowsError(try receipt(earned:7).validate())
        XCTAssertThrowsError(try receipt(earned:1,progress:180).validate())
    }
    func testThirtySecondProfileRemainsThreeBoxes() throws {
        let r=try receipt(earned:3,profile:1,configured:1);try r.validate()
        XCTAssertTrue(r.isTest);XCTAssertEqual(r.limit,3);XCTAssertEqual(r.intervalSeconds,30)
        XCTAssertThrowsError(try receipt(earned:4,profile:1,configured:1).validate())
    }
    func testExtendedSyncFrameAndBackwardsDateOnlyOnProfileMigration() throws {
        let pet=UUID(),r=try receipt(earned:3,profile:1)
        let a=try ack(pet:pet,day:739927,ackDay:739928,earned:3,ackProfile:1,carry:3)
        let path=try a.path(for:pet,receipt:r)
        XCTAssertEqual(path,"/activity/sync/739927/739928/3/3/1/3")
        let intent=PhysicalIntent(id:UUID(),destination:.device,baseRevision:5,snapshot:nil,released:false)
        let bytes=try BoardWire.request(path:path,requestID:UUID(),intent:intent,petID:pet)
        XCTAssertTrue(String(decoding:bytes,as:UTF8.self).contains("|739927,739928,3,3,1,3|"))
        let same=try ack(pet:pet,day:739927,ackDay:739928,earned:3)
        XCTAssertThrowsError(try same.path(for:pet,receipt:receipt(earned:3)))
    }
    func testCannotDropPreviouslyIssuedCountWhileMigrating() throws {
        let pet=UUID(),r=try receipt(earned:3,profile:1)
        let wrong=try ack(pet:pet,day:739928,ackDay:739928,earned:3,ackProfile:1,carry:0)
        XCTAssertThrowsError(try wrong.path(for:pet,receipt:r))
        let wrongDevice=try ack(pet:UUID(),day:739928,ackDay:739928,earned:3,ackProfile:1,carry:3)
        XCTAssertThrowsError(try wrongDevice.path(for:pet,receipt:r))
    }
    func testV4UnknownProfileCanMigrateAfterServerAcknowledgement() throws {
        let r=try receipt(earned:3,profile:0)
        try r.validate();XCTAssertEqual(r.profileID,0)
        let pet=UUID(),a=try ack(pet:pet,day:739928,ackDay:739928,earned:3,ackProfile:0,carry:3)
        XCTAssertEqual(try a.path(for:pet,receipt:r),"/activity/sync/739928/739928/3/3/0/3")
    }
}
