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
    }

    func reload() {
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
        do {
            try repository.backUpUnreadableSave()
            let fresh = CompanionSession()
            try repository.save(fresh)
            session = fresh
            needsRecovery = false
        } catch { errorMessage = error.localizedDescription }
    }

    func refresh() {
        guard !needsRecovery else { return }
        session.advance(to: Date())
        if Date().timeIntervalSince(responseAt) > 3 { response = nil }
        if Date().timeIntervalSince(lastSavedAt) >= 15 { flush() }
    }

    func flush() {
        guard !needsRecovery else { return }
        do {
            try repository.save(session)
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
        do {
            let accepted = try transaction { try $0.care(action) }
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
        try transaction { try $0.beginTransfer(to: destination) }
    }

    func finishTransfer(id: UUID) throws {
        try transaction { try $0.completeTransfer(id: id) }
        responseAt = Date()
        response = session.residence == .phone ? "我来啦，这里好暖和。" : nil
    }

    func cancelTransfer() {
        do { try transaction { $0.cancelSimulatedTransfer() } }
        catch { errorMessage = error.localizedDescription }
    }
}
