import SwiftUI
import PetDomain

struct JourneyView: View {
    @EnvironmentObject private var store: CompanionStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 27) {
                PageHeader(eyebrow: "OUR LITTLE MOMENTS", title: "一起走过的日子", subtitle: "小小的相遇，也值得被记住。")
                HStack(spacing: 14) {
                    Image(systemName: "pawprint").font(.title2).foregroundStyle(Palette.muted)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("方方 · 我们的第 \(daysTogether) 天").font(.system(size: 16, weight: .semibold))
                        Text("现在\(store.session.residence == .phone ? "住在手机小屋" : "待在随身挂件")")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                }.padding(20).background(Palette.sage.opacity(0.5), in: RoundedRectangle(cornerRadius: 23))
                ForEach(store.session.journal) { entry in
                    HStack(alignment: .top, spacing: 17) {
                        Image(systemName: entry.symbol).font(.system(size: 18))
                            .frame(width: 42, height: 42).background(Palette.room, in: Circle())
                        VStack(alignment: .leading, spacing: 7) {
                            Text(entry.date, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
                                .font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                            Text(entry.title).font(.system(size: 16, weight: .medium))
                            Text(entry.detail).font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(4)
                        }
                        Spacer(minLength: 0)
                    }.padding(.bottom, 12)
                }
                Text("它记得，每一次你来过。").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity).padding(.top, 10)
            }.foregroundStyle(Palette.ink).padding(25)
        }
    }

    private var daysTogether: Int {
        max(1, (Calendar.current.dateComponents([.day], from: store.session.createdAt, to: Date()).day ?? 0) + 1)
    }
}

struct DeviceView: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var showConnectionInfo = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(eyebrow: "A HOME IN YOUR POCKET", title: "口袋里的另一个家", subtitle: "带它出门，也带它回家。")
                VStack(spacing: 20) {
                    HStack { Eyebrow(text: "FANGFANG / 01"); Spacer(); if !store.physicalMode { DemoBadge() } }
                    TinyDevice(session: store.session).padding(.vertical, 14)
                    Text(store.physicalMode ? "方方的真实挂件" : "方方的体验挂件").font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text(store.session.residence == .device ? "方方在这里看风景" : "方方去手机小屋玩了")
                        .font(.system(size: 13)).foregroundStyle(Palette.muted)
                    Divider().overlay(Palette.line)
                    HStack {
                        Text("体验编号"); Spacer()
                        Text(String(store.session.petID.uuidString.prefix(8))).monospaced()
                    }.font(.system(size: 11)).foregroundStyle(Palette.muted)
                }.padding(23).frame(maxWidth: .infinity)
                    .background(Palette.room.opacity(0.65), in: RoundedRectangle(cornerRadius: 29))

                VStack(alignment: .leading, spacing: 10) {
                    Label(store.physicalMode ? "已切换为真实挂件" : "目前是离线体验", systemImage: "info.circle").font(.system(size: 14, weight: .semibold))
                    Text(store.physicalMode ? "手机小屋和板子共用同一只宠物。接到手机后，板上只显示空门；送回时会保留在手机里的互动结果。" : "连接下方真实挂件后，小屋将使用板上的宠物。连接前仍可体验离线演示。")
                        .font(.system(size: 13)).foregroundStyle(Palette.muted).lineSpacing(5)
                    Button("了解实物连接") { showConnectionInfo = true }
                        .font(.system(size: 13, weight: .semibold)).padding(.top, 5)
                }

                HardwareMonitorView()

                if !store.physicalMode { VStack(alignment: .leading, spacing: 13) {
                    Eyebrow(text: "DEMO / TRY A LITTLE DETOUR")
                    Toggle("下次传送时模拟中断", isOn: $store.simulateDisconnect)
                        .font(.system(size: 13)).tint(Palette.muted)
                        .accessibilityIdentifier("demo.interrupt")
                    Text("试试旅程中断后继续，心情和精力仍会被保留。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }.padding(18).background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 21)) }
            }.foregroundStyle(Palette.ink).padding(25)
        }
        .sheet(isPresented: $showConnectionInfo) {
            VStack(alignment: .leading, spacing: 23) {
                Eyebrow(text: "THE NEXT LITTLE STEP")
                Text("让它真的跑过来").font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("USB 连接开发板和 Mac，在 Mac 运行双向桥接。手机与 Mac 位于同一局域网，填写 Mac 名称和口令后连接。")
                    .font(.system(size: 15)).foregroundStyle(Palette.muted).lineSpacing(6)
                Text("往返中断时保留原手机的 App 存档，恢复连接后继续同一次旅程。不要删除 App 或强制重置板上存档。")
                    .font(.system(size: 14)).foregroundStyle(Palette.muted).lineSpacing(6)
                Button("知道了") { showConnectionInfo = false }.buttonStyle(FilledButtonStyle())
            }.padding(30)
        }
    }
}

private struct HardwareMonitorView: View {
    @EnvironmentObject private var store: CompanionStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("真实挂件 · USB 经 Mac").font(.headline)
            TextField("Mac 的 .local 名称", text: $store.bridgeHost)
                .textContentType(.URL).autocorrectionDisabled()
                .accessibilityIdentifier("hardware.host")
            SecureField("桥接访问口令", text: $store.bridgeToken)
                .accessibilityIdentifier("hardware.token")
            Button(store.hardwareBusy ? "连接中…" : "连接真实挂件") {
                Task { await store.connectHardware() }
            }.disabled(store.hardwareBusy || store.bridgeHost.isEmpty || store.bridgeToken.isEmpty)
                .accessibilityIdentifier("hardware.connect")
            Text(store.hardwareMessage).font(.caption)
                .accessibilityIdentifier("hardware.status")
            Text("连接后，小屋的出发和返回会操作这块板子。首次绑定不会覆盖体验存档。口令仅保存在本次运行内。")
                .font(.caption).foregroundStyle(Palette.muted)
        }.padding(18).background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 21))
    }
}
