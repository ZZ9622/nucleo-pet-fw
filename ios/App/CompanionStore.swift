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
    enum ConnectionKind { case bluetooth, usb }
    @Published var connectionKind: ConnectionKind = .bluetooth
    let bluetooth = BluetoothTransport()
    let world = PomiWorldStore()
    @Published private(set) var lastHardwareRead: Date?
    @Published private(set) var liveMessage = "等待挂件同步"
    private var pollTask: Task<Void,Never>?
    private var lastPoll = Date.distantPast
    @Published private(set) var hasEnteredHome = false
    @Published private(set) var physicalMode = false
    @Published private(set) var hardwareBusy = false
    @Published var hardwareMessage = "搜索附近的 Pomi，选择挂件后连接"
    @Published var bridgeHost = UserDefaults.standard.string(forKey: "bridgeHost") ?? ""
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
                hardwareMessage = "已保留真实挂件记录；请连接挂件后继续"
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
            if hasEnteredHome && connectionKind == .bluetooth && bluetooth.ready && Date().timeIntervalSince(lastPoll) >= 2 && pollTask == nil {
                lastPoll=Date();pollTask=Task { await self.pollHardware();self.pollTask=nil }
            }
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

    func renamePet(to value: String) throws {
        guard !hardwareBusy, !needsRecovery else { throw CompanionError.invalidState }
        if physicalMode {
            guard var next = physical else { throw CompanionError.invalidState }
            try next.rename(to: value)
            try savePhysical(next)
        } else { try transaction { try $0.rename(to: value) } }
    }

    func care(_ action: CareAction) {
        response="请在挂件上照顾宠物";responseAt=Date()
    }

    private func pollHardware() async {
        guard !hardwareBusy, physical?.intent == nil else { return }
        hardwareBusy=true;defer{hardwareBusy=false}
        do {
            let record=try await transport.request("/device",intent:nil,petID:nil)
            guard var next=physical else { return }
            try next.observe(record);try savePhysical(next)
            lastHardwareRead=Date();liveMessage="属性已同步";physicalBlocked=false
            try await settleItemReceipt(record)
        } catch { liveMessage=error.localizedDescription }
    }

    func startItem(kind: String, id: String) async {
        guard !hardwareBusy,session.residence == .device,session.pendingTransfer == nil else { world.message="宠物回到挂件后才能操作";return }
        if physicalMode && (connectionKind != .bluetooth || !bluetooth.ready) { world.message="请先连接蓝牙挂件";return }
        if kind=="open" && session.state.energy<10 { world.message="精力不足 10，请让宠物在挂件上休息";return }
        do {
            var body: [String:Any] = ["kind":kind,"petID":session.petID.uuidString]
            body[kind=="open" ? "boxID":"itemID"]=id
            _ = try await world.perform("/prepare",body)
            await continueItem()
        } catch { world.message=error.localizedDescription }
    }
    func continueItem() async {
        guard !hardwareBusy,let p=world.inventory.pending,session.residence == .device,
              session.pendingTransfer == nil,p.petID.lowercased()==session.petID.uuidString.lowercased(),let id=UUID(uuidString:p.id) else { return }
        guard physicalMode else { world.message=p.kind=="food" ? "预览：等待模拟挂件按键确认" : "预览：宠物已将盒子推到门口，点击模拟确认完成";return }
        guard connectionKind == .bluetooth,bluetooth.ready else { world.message="请连接原挂件后继续";return }
        hardwareBusy=true;defer{hardwareBusy=false}
        do {
            let intent=PhysicalIntent(id:id,destination:.device,baseRevision:UInt32(session.revision),snapshot:nil,released:false)
            let record=try await bluetooth.request(p.kind=="open" ? "/items/open" : (p.level==2 ? "/items/food2":"/items/food1"),intent:intent,petID:session.petID)
            if var next=physical { try next.observe(record);try savePhysical(next) }
            lastHardwareRead=Date()
            try await settleItemReceipt(record)
            if world.inventory.pending != nil { world.message=p.kind=="open" ? "挂件正在把盒子推到门口…" : "已送达挂件，请按 B1 确认使用食物；若睡着，先长按 B1 叫醒" }
        } catch { world.message=error.localizedDescription }
    }
    private func settleItemReceipt(_ record: BoardRecord) async throws {
        guard let p=world.inventory.pending,let id=UUID(uuidString:p.id),record.petID==session.petID,
              record.itemOperationID==id,record.itemStatus==2 else { return }
        guard record.itemKind==(p.kind=="open" ? 1:2),record.itemLevel==UInt32(p.level) else { throw CompanionError.invalidState }
        _ = try await world.perform("/settle",["operationID":p.id,"receiptID":p.id,"petID":p.petID],requestID:"settle-"+p.id)
        world.message=p.kind=="open" ? "盒子打开了，物品已放入仓库" : "挂件已确认，食物已使用"
    }
    #if DEBUG
    func confirmPreviewItem() async {
        guard !physicalMode,let p=world.inventory.pending else { return }
        do {
            try session.simulateBoardItem(open:p.kind=="open",level:p.level)
            _ = try await world.perform("/settle",["operationID":p.id]);flush()
        } catch { world.message=error.localizedDescription }
    }
    #endif

    func beginTransfer(to destination: Residence) throws -> TransferOffer {
        guard world.inventory.pending == nil else { throw PhysicalError.message("请先完成待确认物品操作") }
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
    func showConnectionSettings() {
        hasEnteredHome = false
    }

    #if DEBUG
    func enterDevelopmentPreview() {
        guard !hardwareBusy else { return }
        // Load the separate demo record; never alter real ownership or its save.
        do {
            let demo = try repository.load() ?? CompanionSession()
            session = demo
            physical = nil
            physicalMode = false
            physicalBlocked = false
            hasEnteredHome = true
            world.configure(preview:true)
        } catch { errorMessage = error.localizedDescription }
    }
    #endif

    private func savePhysical(_ value: PhysicalSession) throws {
        try physicalRepository.save(value)
        physical = value
        physicalMode = true
        session = value.companion
        lastSavedAt = Date()
    }

    private var transport: any DeviceTransport {
        if connectionKind == .bluetooth { return bluetooth }
        return HardwareBridge(host: bridgeHost, token: bridgeToken)
    }

    private func acceptHardware(_ record: BoardRecord) throws {
        var next = try physical ?? physicalRepository.load() ?? PhysicalSession(board: record)
        try next.observe(record)
        try savePhysical(next)
        physicalBlocked = false
        hasEnteredHome = true
        lastHardwareRead=Date();liveMessage="属性已同步"
        world.configure(preview:false)
        if !world.serviceURL.isEmpty { Task { await world.connect() } }
        hardwareMessage = next.intent == nil ? "真实挂件已连接 · 可以在小屋手动往返" : "交接记录已找回，请在小屋继续旅程"
    }

    func connectBluetooth(_ id: UUID) async {
        guard !hardwareBusy, !needsRecovery else { return }
        hardwareBusy = true
        connectionKind = .bluetooth
        defer { hardwareBusy = false }
        do {
            try await bluetooth.connect(to: id)
            try acceptHardware(try await bluetooth.request())
        } catch {
            if physical != nil { physicalBlocked = true }
            hardwareMessage = error.localizedDescription
        }
    }

    func connectHardware() async {
        guard !hardwareBusy, !needsRecovery else { return }
        hardwareBusy = true
        defer { hardwareBusy = false }
        do {
            let record = try await transport.request("/device", intent: nil, petID: nil)
            try acceptHardware(record)
            if connectionKind == .usb { UserDefaults.standard.set(bridgeHost, forKey: "bridgeHost") }
        } catch {
            // Unavailable network is not a loss of phone ownership. An inconsistent
            // board is handled by observe throwing; freeze until next verified read.
            if physical != nil { physicalBlocked = true }
            hardwareMessage = error.localizedDescription
        }
    }

    func travelWithHardware(to destination: Residence) async throws {
        guard world.inventory.pending == nil else { throw PhysicalError.message("请先完成开盒或食物确认，再让宠物出门") }
        guard !hardwareBusy, !needsRecovery, var next = physical else { throw CompanionError.invalidState }
        guard connectionKind == .bluetooth || !bridgeToken.isEmpty else { throw PhysicalError.message("请先连接挂件。") }
        hardwareBusy = true
        defer { hardwareBusy = false }
        let client = transport
        if next.intent == nil {
            let current = try await client.request("/device", intent: nil, petID: nil)
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
