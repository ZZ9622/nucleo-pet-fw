import SwiftUI
import Combine
import PetDomain
#if canImport(UIKit)
import UIKit
#endif

enum AppRuntime {
    static var isUITesting: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--uitesting")
        #else
        return false
        #endif
    }
}

@MainActor
final class CompanionStore: ObservableObject {
    @Published private(set) var session: CompanionSession
    @Published var errorMessage: String?
    @Published var needsRecovery = false
    @Published var simulateDisconnect = false
    @Published var response: String?
    @Published private(set) var physicalMode = false
    @Published private(set) var hardwareBusy = false
    @Published var hardwareMessage = "填写 Mac 名称和口令，连接真实挂件"
    @Published var bridgeHost = UserDefaults.standard.string(forKey: "bridgeHost") ?? "CHUNdeMacBook-Pro.local"
    @Published var bridgeToken = ""
    private var physical: PhysicalSession?
    private var physicalRepository: PhysicalRepository!
    private var physicalBlocked = false
    private let repository: SessionRepository
    private var lastSavedAt = Date.distantPast
    private var responseAt = Date.distantPast

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #if DEBUG
        let testing = ProcessInfo.processInfo.arguments.contains("--uitesting")
        let fileName = testing ? "ui-test-session.json" : "session.json"
        #else
        let fileName = "session.json"
        #endif
        repository = SessionRepository(fileURL: directory.appendingPathComponent("NucleoPet/\(fileName)"))
        session = CompanionSession()
        #if DEBUG
        if testing && ProcessInfo.processInfo.arguments.contains("--reset-demo") {
            do { try repository.save(session) }
            catch { errorMessage = error.localizedDescription }
        }
        #endif
        reload()
        physicalRepository = PhysicalRepository(fileURL: directory.appendingPathComponent("NucleoPet/\(AppRuntime.isUITesting ? "ui-test-physical-session" : "physical-session").json"))
        do {
            if let saved = try physicalRepository.load() {
                physical = saved
                physicalMode = true
                session = saved.companion
                needsRecovery = false
                hardwareMessage = "已保留真实挂件记录；往返前请连接 Mac 桥接"
            }
        } catch {
            physicalMode = true
            needsRecovery = true
            errorMessage = "真实挂件存档无法读取，请保留存档，勿重置或重新绑定。"
        }
    }

    func reload() {
        if physicalMode {
            do {
                guard let saved = try physicalRepository.load() else { throw CompanionError.invalidState }
                physical = saved
                session = saved.companion
                needsRecovery = false
            } catch { needsRecovery = true }
            return
        }
        do {
            var loaded = try repository.load() ?? CompanionSession()
            loaded.advance(to: Date())
            try repository.save(loaded)
            session = loaded
            needsRecovery = false
            errorMessage = nil
            lastSavedAt = Date()
        } catch {
            needsRecovery = true
        }
    }

    func recoverWithBackup() {
        guard !physicalMode else { return }
        do {
            try repository.backUpUnreadableSave()
            let fresh = CompanionSession()
            try repository.save(fresh)
            session = fresh
            needsRecovery = false
        } catch { errorMessage = error.localizedDescription }
    }

    func refresh() {
        guard !needsRecovery, !hardwareBusy else { return }
        if physicalMode {
            guard !physicalBlocked, var next = physical else { return }
            next.advance(to: Date())
            physical = next
            session = next.companion
        } else { session.advance(to: Date()) }
        if Date().timeIntervalSince(responseAt) > 3 { response = nil }
        if Date().timeIntervalSince(lastSavedAt) >= 15 { flush() }
    }

    func flush() {
        guard !needsRecovery else { return }
        do {
            if physicalMode {
                guard let physical else { return }
                try physicalRepository.save(physical)
            } else { try repository.save(session) }
            lastSavedAt = Date()
        } catch { errorMessage = error.localizedDescription }
    }

    private func transaction<T>(_ operation: (inout CompanionSession) throws -> T) throws -> T {
        guard !needsRecovery else { throw CompanionError.invalidState }
        var next = session
        let result = try operation(&next)
        try repository.save(next)
        session = next
        lastSavedAt = Date()
        return result
    }

    func care(_ action: CareAction) {
        guard !hardwareBusy, !needsRecovery else { return }
        do {
            let accepted: Bool
            if physicalMode {
                guard !physicalBlocked, var next = physical else { throw CompanionError.invalidState }
                accepted = try next.care(action)
                try savePhysical(next)
            } else { accepted = try transaction { try $0.care(action) } }
            responseAt = Date()
            if accepted {
                switch action {
                case .feed: response = "小点心，刚刚好。"
                case .pet: response = "嗯，再摸一下也可以。"
                case .play: response = "刚才那一下，超开心！"
                case .sleep: response = session.state.isSleeping ? "晚安，陪我做个好梦。" : "醒来就能看见你，真好。"
                }
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                #endif
            } else {
                response = session.state.isCollapsed ? "给我一点小点心，就能恢复啦。" : "它正在做梦，先轻轻叫醒吧。"
            }
        } catch {
            if error is CompanionError {
                responseAt = Date()
                response = error.localizedDescription
            } else { errorMessage = error.localizedDescription }
        }
    }

    func beginTransfer(to destination: Residence) throws -> TransferOffer {
        guard !physicalMode else { throw CompanionError.transferInProgress }
        return try transaction { try $0.beginTransfer(to: destination) }
    }

    func finishTransfer(id: UUID) throws {
        guard !physicalMode else { throw CompanionError.transferInProgress }
        try transaction { try $0.completeTransfer(id: id) }
        responseAt = Date()
        response = session.residence == .phone ? "我来啦，这里好暖和。" : nil
    }

    func cancelTransfer() {
        guard !physicalMode else { return }
        do { try transaction { $0.cancelSimulatedTransfer() } }
        catch { errorMessage = error.localizedDescription }
    }
    private func savePhysical(_ value: PhysicalSession) throws {
        try physicalRepository.save(value)
        physical = value
        physicalMode = true
        session = value.companion
        lastSavedAt = Date()
    }

    func connectHardware() async {
        guard !hardwareBusy, !needsRecovery else { return }
        hardwareBusy = true
        defer { hardwareBusy = false }
        do {
            let record = try await HardwareBridge(host: bridgeHost, token: bridgeToken).request()
            var next = try physical ?? PhysicalSession(board: record)
            try next.observe(record)
            try savePhysical(next)
            physicalBlocked = false
            UserDefaults.standard.set(bridgeHost, forKey: "bridgeHost")
            hardwareMessage = next.intent == nil ? "真实挂件已连接 · 可以在小屋手动往返" : "交接记录已找回，请在小屋继续旅程"
        } catch {
            // Unavailable network is not a loss of phone ownership. An inconsistent
            // board is handled by observe throwing; freeze until next verified read.
            if physical != nil { physicalBlocked = true }
            hardwareMessage = error.localizedDescription
        }
    }

    func travelWithHardware(to destination: Residence) async throws {
        guard !hardwareBusy, !needsRecovery, var next = physical else { throw CompanionError.invalidState }
        guard !bridgeToken.isEmpty else { throw PhysicalError.message("请先在挂件页填写桥接口令并连接。") }
        hardwareBusy = true
        defer { hardwareBusy = false }
        let client = HardwareBridge(host: bridgeHost, token: bridgeToken)
        if next.intent == nil {
            let current = try await client.request()
            try next.observe(current)
        }
        try next.begin(to: destination)
        try savePhysical(next) // Intent is durable BEFORE the first mutating request.
        guard let pending = next.intent else { throw CompanionError.noTransfer }
        let prefix = destination == .phone ? "/handoff/take" : "/handoff/return"
        let prepared = try await client.request(prefix + (destination == .phone ? "/prepare" : "/stage"),
            intent: pending, petID: next.companion.petID)
        try next.acceptPrepared(prepared)
        try savePhysical(next) // Received snapshot is durable while both sides are frozen.
        if destination == .device {
            try next.releaseForReturn()
            try savePhysical(next) // Irrevocable local release BEFORE board activation.
        }
        let receipt = try await client.request(prefix + "/commit", intent: next.intent, petID: next.companion.petID)
        try next.finish(receipt)
        try savePhysical(next)
        physicalBlocked = false
        hardwareMessage = destination == .phone ? "宠物已离开板子，进入手机小屋" : "宠物已带着新状态回到板子"
    }

}
