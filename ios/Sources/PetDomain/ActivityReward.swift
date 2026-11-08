import Foundation

public struct ActivityReward: Codable, Equatable {
    public static let stages: [UInt32] = [60,180,300,480,720,900]
    public let day: UInt32
    public let progressSeconds: UInt32
    public let earnedToday: UInt32
    public let intervalSeconds: UInt32
    public var issuedTotal: UInt32? = nil
    public var lifetimeEnabled: Bool? = nil
    public var offlineClockSupported: Bool? = nil
    public var clockReady: Bool? = nil
    public var nextRefreshEpoch: UInt32? = nil
    public var profile: UInt32? = nil
    public var dailyLimit: UInt32? = nil
    public var configuredProfile: UInt32? = nil
    public var profileID: UInt32 { profile ?? (intervalSeconds==30 ? 1:2) }
    public var limit: UInt32 { profileID==3 ? 6:3 }
    public static func target(profile:UInt32,earned:UInt32) -> UInt32 {
        profile==3 ? stages[Int(min(earned,5))] : profile==1 ? 30:600
    }
    public func validate() throws {
        guard day<=3652059,profileID<=3,earnedToday<=limit,
              dailyLimit==nil || dailyLimit==limit,
              configuredProfile==nil || (1...3).contains(configuredProfile!),
              day != 0 || (progressSeconds==0 && earnedToday==0) else { throw CompanionError.invalidState }
        if lifetimeEnabled==true && issuedTotal==nil { throw CompanionError.invalidState }
        if lifetimeEnabled==false && (issuedTotal ?? 0) != 0 { throw CompanionError.invalidState }
        if clockReady==true && (offlineClockSupported != true || lifetimeEnabled != true || profileID != 3) { throw CompanionError.invalidState }
        if profileID==0 { guard [30,600].contains(intervalSeconds) else { throw CompanionError.invalidState } }
        else { guard intervalSeconds==Self.target(profile:profileID,earned:earnedToday) else { throw CompanionError.invalidState } }
        guard progressSeconds<intervalSeconds else { throw CompanionError.invalidState }
    }
    public var isTest: Bool { profileID==1 || (profileID==0 && intervalSeconds==30) }
    public var isDailySix: Bool { profileID==3 }
}
public struct ActivitySyncInfo: Codable, Equatable {
    public let petID: String
    public let day: UInt32
    public let dayLabel: String
    public let timezone: String
    public let intervalSeconds: UInt32
    public let ackDay: UInt32
    public let ackEarned: UInt32
    public let granted: UInt32
    public var profile: UInt32? = nil
    public var ackProfile: UInt32? = nil
    public var dailyLimit: UInt32? = nil
    public var refreshHour: UInt32? = nil
    public var carryEarned: UInt32? = nil
    public var clockBootstrap: Bool? = nil
    public func path(for pet: UUID, receipt: ActivityReward) throws -> String {
        try receipt.validate()
        let desired=profile ?? receipt.profileID
        let changing=desired != receipt.profileID
        guard UUID(uuidString:petID)==pet,day>0,day<=3652059,
              changing || day>=receipt.day,ackDay==receipt.day,ackEarned==receipt.earnedToday,
              granted<=1_000_000,(1...3).contains(desired) else { throw CompanionError.invalidState }
        if receipt.profile==nil {
            guard desired==receipt.profileID,intervalSeconds==receipt.intervalSeconds else { throw PhysicalError.message("请升级挂件固件以切换活动方案") }
            return "/activity/sync/\(day)/\(ackDay)/\(ackEarned)"
        }
        guard ackProfile==receipt.profileID,desired==(receipt.configuredProfile ?? receipt.profileID),
              let carry=carryEarned,carry<=(desired==3 ? 6:3),
              !changing || carry>=min(receipt.earnedToday,desired==3 ? 6:3) else { throw CompanionError.invalidState }
        return "/activity/sync/\(day)/\(ackDay)/\(ackEarned)/\(desired)/\(receipt.profileID)/\(carry)"
    }
}
