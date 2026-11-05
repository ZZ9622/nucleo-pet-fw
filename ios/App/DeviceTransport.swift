import Foundation
import PetDomain

@MainActor
protocol DeviceTransport {
    func request(_ path: String, intent: PhysicalIntent?, petID: UUID?) async throws -> BoardRecord
}
