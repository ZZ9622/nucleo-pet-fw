import Foundation
import Combine
import CoreBluetooth
import PetDomain

@MainActor
final class BluetoothTransport: NSObject, ObservableObject, DeviceTransport, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    struct Device: Identifiable { let id: UUID; let name: String; let rssi: Int }
    @Published private(set) var devices: [Device] = []
    @Published private(set) var message = "搜索附近的 Pomi 挂件"
    @Published private(set) var scanning = false
    @Published private(set) var ready = false
    private var scanTimer: Task<Void,Never>?
    private var central: CBCentralManager?
    private var peripherals: [UUID:CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var channel: CBCharacteristic?
    private var connection: CheckedContinuation<Void,Error>?
    private var connectionTimer: Task<Void,Never>?
    private var connectionID: UUID?
    private var pending: CheckedContinuation<BoardRecord,Error>?
    private var pendingID: UUID?
    private var requestTimer: Task<Void,Never>?
    private var chunks: [Data] = []
    private var incoming = BoardLineBuffer()

    func startScan() {
        guard connection == nil, pending == nil else { return }
        devices=[];peripherals=[:]
        if ready, let p=peripheral {
            peripherals[p.identifier]=p
            devices=[Device(id:p.identifier,name:p.name ?? "Pomi",rssi:0)]
        }
        if central == nil { central=CBCentralManager(delegate:self,queue:.main) }
        else { scanWhenReady() }
    }
    func stopScan() { central?.stopScan();scanning=false;scanTimer?.cancel();scanTimer=nil }
    private func scanWhenReady() {
        guard let central else { return }
        switch central.state {
        case .poweredOn:
            stopScan();scanning=true;message="正在搜索附近的 Pomi…"
            central.scanForPeripherals(withServices:[CBUUID(string:BoardWire.serviceUUID)])
            scanTimer=Task { do { try await Task.sleep(for:.seconds(12)) } catch { return };if self.scanning { self.stopScan();self.message=self.devices.isEmpty ? "未找到挂件，请确认挂件已通电且未被其他手机连接" : "选择要连接的挂件" } }
        case .poweredOff: scanning=false;message="请打开蓝牙后重新搜索"
        case .unauthorized: scanning=false;message="请在系统设置中允许 Pomi 使用蓝牙"
        case .unsupported: scanning=false;message="当前设备不支持蓝牙；iPhone 模拟器请使用开发预览，实物连接需实体 iPhone"
        case .resetting: scanning=false;message="蓝牙正在重启，请稍后重新搜索"
        default: message="正在准备蓝牙…"
        }
    }
    func connect(to id: UUID) async throws {
        guard connection == nil, pending == nil, let central, central.state == .poweredOn,
              let target=peripherals[id] else { throw PhysicalError.message("请重新搜索挂件。") }
        if ready, peripheral?.identifier == id { return }
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        stopScan();ready=false;channel=nil;incoming=BoardLineBuffer();peripheral=target;target.delegate=self
        message="正在连接 \(target.name ?? "Pomi")…"
        let attempt=UUID();connectionID=attempt
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void,Error>) in
                connection=continuation
                connectionTimer=Task { do { try await Task.sleep(for:.seconds(12)) } catch { return }
                    if self.connectionID == attempt { self.failConnection("连接超时，请靠近挂件后重试。") } }
                central.connect(target)
            }
        } onCancel: { Task { @MainActor in if self.connectionID == attempt { self.failConnection("连接已取消") } } }
    }
    func request(_ path: String = "/device", intent: PhysicalIntent? = nil, petID: UUID? = nil) async throws -> BoardRecord {
        guard pending == nil else { throw PhysicalError.message("挂件正在处理上一次操作，请稍后。") }
        let id=UUID()
        let frame=try BoardWire.request(path:path,requestID:id,intent:intent,petID:petID)
        for attempt in 0..<2 {
            do { return try await exchange(frame,id:id) }
            catch {
                if attempt == 1 || !ready || Task.isCancelled { throw error }
                // Same frame/ID: a lost response never creates a second handoff.
            }
        }
        throw CompanionError.noTransfer
    }
    private func exchange(_ frame: Data,id: UUID) async throws -> BoardRecord {
        guard ready, let peripheral, let channel else { throw PhysicalError.message("蓝牙已断开，请重新连接后继续同一次旅程。") }
        let size=max(1,min(180,peripheral.maximumWriteValueLength(for:.withResponse)))
        incoming=BoardLineBuffer()
        chunks=stride(from:0,to:frame.count,by:size).map { frame.subdata(in:$0..<min(frame.count,$0+size)) }
        pendingID=id
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<BoardRecord,Error>) in
                pending=continuation
                requestTimer=Task { do { try await Task.sleep(for:.seconds(5)) } catch { return }
                    if self.pendingID == id { self.failRequest(PhysicalError.message("挂件未确认操作，请恢复连接后继续原来的旅程。")) } }
                peripheral.writeValue(chunks.removeFirst(),for:channel,type:.withResponse)
            }
        } onCancel: { Task { @MainActor in if self.pendingID == id { self.failRequest(CancellationError()) } } }
    }
    private func failRequest(_ error: Error) {
        let callback=pending;pending=nil;pendingID=nil;chunks=[];requestTimer?.cancel();requestTimer=nil
        callback?.resume(throwing:error)
    }
    private func failConnection(_ text:String) {
        ready=false;message=text;connectionTimer?.cancel();connectionTimer=nil;connectionID=nil
        let callback=connection;connection=nil
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        callback?.resume(throwing:PhysicalError.message(text))
    }
    func centralManagerDidUpdateState(_ central:CBCentralManager) {
        if central.state != .poweredOn {
            ready=false
            failRequest(PhysicalError.message("蓝牙不可用，交接记录已保留。"))
            if connection != nil { failConnection("蓝牙不可用，请检查蓝牙权限与开关。") }
        }
        scanWhenReady()
    }
    func centralManager(_ central:CBCentralManager,didDiscover peripheral:CBPeripheral,advertisementData:[String:Any],rssi RSSI:NSNumber) {
        peripherals[peripheral.identifier]=peripheral
        let device=Device(id:peripheral.identifier,name:advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "Pomi",rssi:RSSI.intValue)
        devices.removeAll{$0.id==device.id};devices.append(device);devices.sort{$0.rssi > $1.rssi}
    }
    func centralManager(_ central:CBCentralManager,didConnect peripheral:CBPeripheral) {
        guard self.peripheral?.identifier == peripheral.identifier, connection != nil else { return }
        message="正在确认挂件服务…";peripheral.discoverServices([CBUUID(string:BoardWire.serviceUUID)])
    }
    func centralManager(_ central:CBCentralManager,didFailToConnect peripheral:CBPeripheral,error:Error?) {
        guard self.peripheral?.identifier == peripheral.identifier else { return };failConnection("无法连接挂件，请重试。")
    }
    func centralManager(_ central:CBCentralManager,didDisconnectPeripheral peripheral:CBPeripheral,error:Error?) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        ready=false;channel=nil;message="挂件已断开；如有旅程未完成，请重新连接后继续"
        failRequest(PhysicalError.message(message))
        if connection != nil { failConnection(message) }
    }
    func peripheral(_ peripheral:CBPeripheral,didDiscoverServices error:Error?) {
        guard error == nil, let service=peripheral.services?.first(where:{$0.uuid==CBUUID(string:BoardWire.serviceUUID)}) else { failConnection("没有找到 Pomi 服务，请检查模块固件。");return }
        peripheral.discoverCharacteristics([CBUUID(string:BoardWire.characteristicUUID)],for:service)
    }
    func peripheral(_ peripheral:CBPeripheral,didDiscoverCharacteristicsFor service:CBService,error:Error?) {
        guard error == nil, let c=service.characteristics?.first(where:{$0.uuid==CBUUID(string:BoardWire.characteristicUUID)}),
              c.properties.contains(.write),c.properties.contains(.notify) else {
            failConnection("模块仍是只读版本，需要升级 Pomi 双向蓝牙固件。");return
        }
        channel=c;peripheral.setNotifyValue(true,for:c)
    }
    func peripheral(_ peripheral:CBPeripheral,didUpdateNotificationStateFor characteristic:CBCharacteristic,error:Error?) {
        guard characteristic.uuid==channel?.uuid else { return }
        guard error == nil,characteristic.isNotifying else { failConnection("无法订阅挂件回复，请重新连接。");return }
        ready=true;message="蓝牙已连接，正在读取真实宠物…";connectionTimer?.cancel();connectionTimer=nil;connectionID=nil
        let callback=connection;connection=nil;callback?.resume()
    }
    func peripheral(_ peripheral:CBPeripheral,didWriteValueFor characteristic:CBCharacteristic,error:Error?) {
        guard pending != nil,characteristic.uuid==channel?.uuid else { return }
        if let error { failRequest(error);return }
        if !chunks.isEmpty { peripheral.writeValue(chunks.removeFirst(),for:characteristic,type:.withResponse) }
    }
    func peripheral(_ peripheral:CBPeripheral,didUpdateValueFor characteristic:CBCharacteristic,error:Error?) {
        guard characteristic.uuid==channel?.uuid,let id=pendingID,pending != nil else { return }
        if let error { failRequest(error);return }
        for line in incoming.append(characteristic.value ?? Data()) {
            let value: BoardRecord
            do { value=try BoardWire.decode(line,requestID:id) }
            catch let error as PhysicalError { failRequest(error);return }
            catch { continue }
            let callback=pending;pending=nil;pendingID=nil;chunks=[];requestTimer?.cancel();requestTimer=nil
            callback?.resume(returning:value);break
        }
    }
}
