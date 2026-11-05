import SwiftUI
import PetDomain

struct ConnectionView: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var showMotionDebug = false
    private let preview = CompanionSession()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Eyebrow(text: "Pomi")
                    Spacer()
                    Text("01 / CONNECT").font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                VStack(spacing: 18) {
                    TinyDevice(session: preview).padding(.top, 12)
                    HStack(spacing: 6) {
                        ForEach(0..<5) { _ in Rectangle().fill(Palette.line).frame(width: 5, height: 5) }
                        Text("HELLO, LITTLE FRIEND").font(.system(size: 9, weight: .bold, design: .monospaced))
                        ForEach(0..<5) { _ in Rectangle().fill(Palette.line).frame(width: 5, height: 5) }
                    }
                }.frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 10) {
                    Text("连接你的小伙伴")
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .accessibilityIdentifier("connection.title")
                    Text("让口袋里的像素，走进手机。")
                        .font(.system(size: 14)).foregroundStyle(Palette.muted)
                }
                if store.connectionKind == .bluetooth {
                    BluetoothConnectionFields(radio: store.bluetooth)
                } else { ConnectionFields() }
                HStack {
                    Button("蓝牙连接") { store.connectionKind = .bluetooth }
                        .accessibilityIdentifier("connection.bluetooth")
                    Spacer()
                    Button("USB 经 Mac") { store.connectionKind = .usb; store.bluetooth.stopScan() }
                        .accessibilityIdentifier("connection.usb")
                }.font(.system(size: 12, weight: .semibold)).disabled(store.hardwareBusy)
                Text(store.connectionKind == .bluetooth ? "挂件通电后，搜索并选择附近的 Pomi。确认真实宠物记录后自动进入小屋，无需 Mac 桥接。" : "开发板通过 USB 连到 Mac，手机与 Mac 连接同一 Wi-Fi。连接成功后自动进入小屋。")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(4)
                #if DEBUG
                Button("无硬件开发预览 →") { store.enterDevelopmentPreview() }
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("connection.preview")
                Button("动作调试台 →") { showMotionDebug = true }
                    .font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("motion.open")
                Text("独立体验存档 · 不操作真实挂件")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity)
                #endif
            }.foregroundStyle(Palette.ink).padding(24)
        }.scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("connection.screen")
            #if DEBUG
            .sheet(isPresented: $showMotionDebug) { MotionDebugView() }
            #endif
    }
}

struct ConnectionFields: View {
    @EnvironmentObject private var store: CompanionStore
    @FocusState private var focus: Field?
    private enum Field { case host, token }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Rectangle().fill(Palette.coral).frame(width: 7, height: 7)
                Text("USB / MAC BRIDGE").font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Mac 地址").font(.system(size: 12, weight: .semibold))
                TextField("例如 your-mac.local", text: $store.bridgeHost)
                    .textContentType(.URL).autocorrectionDisabled()
                    .focused($focus, equals: .host).submitLabel(.next)
                    .onSubmit { focus = .token }
                    .padding(13).background(Palette.paper)
                    .overlay(Rectangle().stroke(focus == .host ? Palette.ink : Palette.line, lineWidth: 2))
                    .accessibilityIdentifier("hardware.host")
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("访问口令").font(.system(size: 12, weight: .semibold))
                SecureField("填写 Mac 桥接口令", text: $store.bridgeToken)
                    .focused($focus, equals: .token).submitLabel(.go)
                    .onSubmit { connect() }
                    .padding(13).background(Palette.paper)
                    .overlay(Rectangle().stroke(focus == .token ? Palette.ink : Palette.line, lineWidth: 2))
                    .accessibilityIdentifier("hardware.token")
            }
            Button { connect() } label: {
                HStack {
                    Spacer()
                    if store.hardwareBusy { ProgressView().tint(.white) }
                    Text(store.hardwareBusy ? "正在寻找小伙伴…" : "连接并进入小屋")
                    if !store.hardwareBusy { Image(systemName: "arrow.right") }
                    Spacer()
                }
            }.buttonStyle(FilledButtonStyle())
                .disabled(store.hardwareBusy || store.bridgeHost.isEmpty || store.bridgeToken.isEmpty || store.needsRecovery)
                .opacity(store.bridgeToken.isEmpty ? 0.55 : 1)
                .accessibilityIdentifier("hardware.connect")
            Text(store.hardwareMessage).font(.system(size: 12)).foregroundStyle(Palette.muted)
                .lineSpacing(3).accessibilityIdentifier("hardware.status")
        }.font(.system(size: 14, design: .monospaced))
            .padding(20).background(.white, in: PixelFrame())
            .overlay(PixelFrame().stroke(Palette.ink, lineWidth: 2))
            .disabled(store.hardwareBusy)
    }
    private func connect() {
        guard !store.hardwareBusy, !store.bridgeHost.isEmpty, !store.bridgeToken.isEmpty else { return }
        focus = nil
        Task { await store.connectHardware() }
    }
}

struct BluetoothConnectionFields: View {
    @EnvironmentObject private var store: CompanionStore
    @ObservedObject var radio: BluetoothTransport
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow(text: "Pomi / BLUETOOTH LE")
            Button(radio.scanning ? "停止搜索" : "搜索附近挂件") {
                if radio.scanning { radio.stopScan() } else { radio.startScan() }
            }.buttonStyle(FilledButtonStyle()).disabled(store.hardwareBusy)
                .accessibilityIdentifier("bluetooth.scan")
            if radio.scanning { ProgressView().tint(Palette.ink) }
            Text(radio.message).font(.system(size: 12)).foregroundStyle(Palette.muted)
                .accessibilityIdentifier("bluetooth.status")
            ForEach(radio.devices) { device in
                Button { Task { await store.connectBluetooth(device.id) } } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(device.name).font(.system(size: 16, weight: .semibold))
                            Text(String(device.id.uuidString.prefix(8))).font(.system(size: 10, design: .monospaced))
                        }
                        Spacer()
                        Text("\(device.rssi) dBm").font(.system(size: 11, design: .monospaced))
                        Image(systemName: "arrow.right")
                    }.padding(14).background(Palette.sage, in: PixelFrame())
                }.buttonStyle(.plain).disabled(store.hardwareBusy)
                    .accessibilityIdentifier("bluetooth.device.\(device.id.uuidString)")
            }
            if store.hardwareBusy { HStack { ProgressView(); Text("连接并确认宠物记录…").font(.caption) } }
            Text(store.hardwareMessage).font(.system(size: 12)).foregroundStyle(Palette.muted)
                .accessibilityIdentifier("hardware.status")
        }.padding(20).background(.white, in: PixelFrame())
            .overlay(PixelFrame().stroke(Palette.ink, lineWidth: 2))
    }
}

struct BluetoothStatusBanner: View {
    @EnvironmentObject private var store: CompanionStore
    @ObservedObject var radio: BluetoothTransport
    var body: some View {
        if !radio.ready {
            Button { store.showConnectionSettings() } label: {
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    Text("蓝牙已断开 · 点此重新连接")
                    Spacer()
                    Image(systemName: "arrow.right")
                }.font(.system(size: 12)).padding(12).background(Palette.sage)
            }.buttonStyle(.plain).accessibilityIdentifier("bluetooth.reconnect")
        }
    }
}
