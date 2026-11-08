import Foundation

public struct ActivityReward: Codable, Equatable {
    public let day: UInt32
    public let progressSeconds: UInt32
    public let earnedToday: UInt32
    public let intervalSeconds: UInt32
    public func validate() throws {
        guard day<=3652059, [30,600].contains(intervalSeconds),progressSeconds<intervalSeconds,
              earnedToday<=3, day != 0 || (progressSeconds==0 && earnedToday==0) else { throw CompanionError.invalidState }
    }
    public var isTest: Bool { intervalSeconds==30 }
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
    public func path(for pet: UUID, receipt: ActivityReward) throws -> String {
        try receipt.validate()
        guard UUID(uuidString:petID)==pet,day>=receipt.day,day>0,day<=3652059,
              intervalSeconds==receipt.intervalSeconds,ackDay==receipt.day,ackEarned==receipt.earnedToday,
              granted<=3 else { throw CompanionError.invalidState }
        return "/activity/sync/\(day)/\(ackDay)/\(ackEarned)"
    }
}
