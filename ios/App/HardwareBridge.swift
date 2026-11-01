import Foundation
import PetDomain

struct HardwareBridge {
    let host: String
    let token: String

    func request(_ path: String = "/device", intent: PhysicalIntent? = nil, petID: UUID? = nil) async throws -> BoardRecord {
        let name = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.hasSuffix(".local"), !name.contains("/"), !name.contains(":"), !name.contains("@"),
              !token.isEmpty, let url = URL(string: "http://\(name):8765\(path)") else {
            throw PhysicalError.message("请填写 Mac 的 .local 名称和桥接口令。")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let intent, let petID {
            struct Body: Encodable {
                let petID: UUID
                let transferID: UUID
                let revision: UInt32
                let state: FirmwareState?
            }
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(Body(petID: petID, transferID: intent.id,
                revision: intent.baseRevision, state: intent.snapshot))
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw PhysicalError.message("挂件未确认交接。请检查 USB、桥接和口令，再继续同一次旅程。")
        }
        let record = try JSONDecoder().decode(BoardRecord.self, from: data)
        try record.validate()
        return record
    }
}
