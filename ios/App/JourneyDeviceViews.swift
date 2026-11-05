import SwiftUI
import PetDomain

struct DeviceView: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var showConnectionInfo = false
    @State private var showMotionDebug = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(eyebrow: "A HOME IN YOUR POCKET", title: "口袋里的另一个家", subtitle: "带它出门，也带它回家。")
                VStack(spacing: 20) {
                    HStack { Eyebrow(text: "Pomi / COMPANION"); Spacer(); if !store.physicalMode { DemoBadge() } }
                    TinyDevice(session: store.session).padding(.vertical, 14)
                    Text(store.physicalMode ? "\(store.session.name)的真实挂件" : "\(store.session.name)的体验挂件").font(.system(size: 20, weight: .semibold, design: .monospaced))
                    Text(store.session.residence == .device ? "\(store.session.name)在这里看风景" : "\(store.session.name)去手机小屋玩了")
                        .font(.system(size: 13)).foregroundStyle(Palette.muted)
                    Divider().overlay(Palette.line)
                    HStack {
                        Text("体验编号"); Spacer()
                        Text(String(store.session.petID.uuidString.prefix(8))).monospaced()
                    }.font(.system(size: 11)).foregroundStyle(Palette.muted)
                }.padding(23).frame(maxWidth: .infinity)
                    .background(Palette.room.opacity(0.65), in: PixelFrame(cornerRadius: 29))

                VStack(alignment: .leading, spacing: 10) {
                    Label(store.physicalMode ? "已切换为真实挂件" : "目前是离线体验", systemImage: "info.circle").font(.system(size: 14, weight: .semibold))
                    Text(store.physicalMode ? "手机小屋和板子共用同一只宠物。接到手机后，板上只显示空门；手机端仅查看和布置，照顾操作在挂件上完成。" : "连接下方真实挂件后，小屋将使用板上的宠物。连接前仍可体验离线演示。")
                        .font(.system(size: 13)).foregroundStyle(Palette.muted).lineSpacing(5)
                    Button("了解实物连接") { showConnectionInfo = true }
                        .font(.system(size: 13, weight: .semibold)).padding(.top, 5)
                }

                PetNameEditor()

                Button("连接设置") { store.showConnectionSettings() }
                    .buttonStyle(FilledButtonStyle())
                    .accessibilityIdentifier("hardware.settings")

                #if DEBUG
                Button("动作调试台") { showMotionDebug = true }
                    .buttonStyle(QuietButtonStyle()).accessibilityIdentifier("motion.open")
                #endif
                if !store.physicalMode { VStack(alignment: .leading, spacing: 13) {
                    Eyebrow(text: "DEMO / TRY A LITTLE DETOUR")
                    Toggle("下次传送时模拟中断", isOn: $store.simulateDisconnect)
                        .font(.system(size: 13)).tint(Palette.muted)
                        .accessibilityIdentifier("demo.interrupt")
                    Text("试试旅程中断后继续，心情和精力仍会被保留。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }.padding(18).background(.white.opacity(0.6), in: PixelFrame(cornerRadius: 21)) }
            }.foregroundStyle(Palette.ink).padding(25)
        }
        #if DEBUG
        .sheet(isPresented: $showMotionDebug) { MotionDebugView() }
        #endif
        .sheet(isPresented: $showConnectionInfo) {
            VStack(alignment: .leading, spacing: 23) {
                Eyebrow(text: "THE NEXT LITTLE STEP")
                Text("让它真的跑过来").font(.system(size: 28, weight: .semibold, design: .monospaced))
                Text("选择蓝牙连接，在 App 搜索并连接附近的 Pomi 挂件。开发调试时也可以使用 USB 经 Mac 桥接。")
                    .font(.system(size: 15)).foregroundStyle(Palette.muted).lineSpacing(6)
                Text("往返中断时保留原手机的 App 存档，恢复连接后继续同一次旅程。不要删除 App 或强制重置板上存档。")
                    .font(.system(size: 14)).foregroundStyle(Palette.muted).lineSpacing(6)
                Button("知道了") { showConnectionInfo = false }.buttonStyle(FilledButtonStyle())
            }.padding(30)
        }
    }
}

struct HardwareMonitorView: View {
    @EnvironmentObject private var store: CompanionStore
    var body: some View {
        ConnectionFields()
    }
}

private struct PetNameEditor: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var draft = ""
    @FocusState private var editing: Bool
    @State private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "MY PET / NAME")
            Text("给小伙伴起个名字").font(.system(size: 17, weight: .semibold))
            TextField("宠物名字", text: $draft)
                .focused($editing)
                .padding(12).background(.white)
                .overlay(Rectangle().stroke(Palette.line, lineWidth: 2))
                .accessibilityIdentifier("pet.name")
                .onSubmit { save() }
            Button("保存名字") { save() }
                .buttonStyle(QuietButtonStyle())
                .disabled(store.hardwareBusy || store.needsRecovery)
                .accessibilityIdentifier("pet.name.save")
            if !message.isEmpty { Text(message).font(.caption).accessibilityIdentifier("pet.name.status") }
            Text("最多 24 个字符。名字保存在这台手机，板子仍使用同一只宠物的身份。")
                .font(.caption).foregroundStyle(Palette.muted)
        }.padding(18).background(Palette.sage, in: PixelFrame())
            .onAppear { draft = store.session.name }
            .onChange(of: draft) { _, value in if value != store.session.name { message = "" } }
    }
    private func save() {
        editing = false
        do {
            try store.renamePet(to: draft)
            draft = store.session.name
            message = "名字已保存"
        } catch { message = error.localizedDescription }
    }
}
