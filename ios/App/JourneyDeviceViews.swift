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
                    HStack { Eyebrow(text: "FANGFANG / 01"); Spacer(); DemoBadge() }
                    TinyDevice(session: store.session).padding(.vertical, 14)
                    Text("方方的体验挂件").font(.system(size: 20, weight: .semibold, design: .rounded))
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
                    Label("目前是离线体验", systemImage: "info.circle").font(.system(size: 14, weight: .semibold))
                    Text("这里的挂件是体验设备。可以体验往返和互动，宠物记录会保存在这台手机上。体验宠物不会改变你的真实开发板；下方可单独读取实物属性。")
                        .font(.system(size: 13)).foregroundStyle(Palette.muted).lineSpacing(5)
                    Button("了解实物连接") { showConnectionInfo = true }
                        .font(.system(size: 13, weight: .semibold)).padding(.top, 5)
                }

                HardwareMonitorView()

                VStack(alignment: .leading, spacing: 13) {
                    Eyebrow(text: "DEMO / TRY A LITTLE DETOUR")
                    Toggle("下次传送时模拟中断", isOn: $store.simulateDisconnect)
                        .font(.system(size: 13)).tint(Palette.muted)
                        .accessibilityIdentifier("demo.interrupt")
                    Text("试试旅程中断后继续，心情和精力仍会被保留。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }.padding(18).background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 21))
            }.foregroundStyle(Palette.ink).padding(25)
        }
        .sheet(isPresented: $showConnectionInfo) {
            VStack(alignment: .leading, spacing: 23) {
                Eyebrow(text: "THE NEXT LITTLE STEP")
                Text("让它真的跑过来").font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("当前 NUCLEO-F401RE 固件还没有手机通信和存档功能。USB 读取可通过 Mac 桥接；实物往返仍需双端持久化状态交接，再在两台设备上验证。")
                    .font(.system(size: 15)).foregroundStyle(Palette.muted).lineSpacing(6)
                Text("这个版本先把手机小屋和往返体验做好。实物连接开放后，会在这里完成配对。")
                    .font(.system(size: 14)).foregroundStyle(Palette.muted).lineSpacing(6)
                Button("知道了") { showConnectionInfo = false }.buttonStyle(FilledButtonStyle())
            }.padding(30)
        }
    }
}

/// A separate read-only instrument; never imports telemetry into the demo pet.
private struct HardwareMonitorView: View {
    @State private var host = ""
    @State private var token = ""
    @State private var message = "尚未读取真实设备"
    @State private var state: LiveBoardState?
    @State private var reading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("真实挂件 · USB 经 Mac").font(.headline)
            TextField("Mac 名称，例如 lindas-mac.local", text: $host)
                .textContentType(.URL).autocorrectionDisabled().disabled(reading)
            SecureField("桥接访问口令", text: $token).disabled(reading)
            Button(reading ? "读取中…" : "读取真实属性") {
                Task { await readState() }
            }.disabled(reading || host.isEmpty || token.isEmpty)
            Text(message).font(.caption)
            if let state {
                Text("Happiness \(state.happiness) · Energy \(state.energy)")
                Text(state.sleeping ? "正在睡觉" : "醒着").font(.caption)
            }
            Text("这里只读真实属性，不改变体验宠物；出发和返回仍是模拟。")
                .font(.caption).foregroundStyle(Palette.muted)
        }.padding(18).background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 21))
        .onChange(of: host) { _, _ in state = nil }
        .onChange(of: token) { _, _ in state = nil }
        .task(id: state?.seq) {
            guard state != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            state = nil
            message = "数据已过期，请重新读取"
        }
    }

    @MainActor private func readState() async {
        reading = true
        state = nil
        defer { reading = false }
        let name = host.trimmingCharacters(in: .whitespacesAndNewlines)
        // Local hostname only: avoid transmitting this development token to public hosts.
        guard name.hasSuffix(".local"), !name.contains("/"), !name.contains(":"),
              !name.contains("@"), let url = URL(string: "http://\(name):8765/state") else {
            message = "请填写 Mac 的 .local 名称（系统设置 → 通用 → 共享）"
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                message = "桥接访问失败，请检查口令"
                return
            }
            let result = try JSONDecoder().decode(LiveBoardResponse.self, from: data)
            guard result.connected, let value = result.state,
                  value.v == 1, (0...100).contains(value.energy),
                  (0...100).contains(value.happiness) else {
                message = "挂件已断开或数据已过期"
                return
            }
            state = value
            message = "刚刚读取 · 3 秒后过期"
        } catch {
            message = "无法读取，请检查 Mac 桥接、同一 Wi-Fi 和本地网络权限"
        }
    }
}

private struct LiveBoardResponse: Decodable {
    let connected: Bool
    let state: LiveBoardState?
}
private struct LiveBoardState: Decodable {
    let v: Int
    let seq: UInt32
    let energy: Int
    let happiness: Int
    let sleeping: Bool
}
