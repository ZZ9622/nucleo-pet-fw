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

                if store.physicalMode { LiveMotionPanel();ActivityRewardPanel() }

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


private struct LiveMotionPanel: View {
    @EnvironmentObject private var store: CompanionStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "LIS3DH / LIVE")
                Text("挂件活动").font(.system(size: 17, weight: .semibold))
                if let motion = store.liveMotion {
                    if !connectionAvailable || !recent(at: context.date) {
                        Text("数据已过期，请重新连接挂件")
                    } else if !motion.isFresh {
                        Text("未收到传感器新数据，请检查四根连接线")
                    } else {
                        Text(motion.title).font(.title2.bold())
                            .accessibilityIdentifier("motion.live.status")
                        Text("X \(motion.xMg) · Y \(motion.yMg) · Z \(motion.zMg) mg")
                            .font(.system(size: 12, design: .monospaced))
                            .accessibilityIdentifier("motion.live.axes")
                        Text("本次通电活动累计 \(motion.activeMs / 1000) 秒")
                            .font(.caption)
                        Text("轻晃提示保留约 3 秒，静置后会恢复静止。")
                            .font(.caption).foregroundStyle(Palette.muted)
                    }
                } else {
                    Text("等待传感器数据；请确认已安装支持 LIS3DH 的固件。")
                        .font(.caption)
                }
                Text("活动判断处于校准阶段，累计时间随挂件重启归零。")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.sage, in: PixelFrame())
        }
    }

    private var connectionAvailable: Bool {
        store.connectionKind != .bluetooth || store.bluetooth.ready
    }

    private func recent(at now: Date) -> Bool {
        guard let received = store.motionReceivedAt else { return false }
        return (0...6).contains(now.timeIntervalSince(received))
    }
}

struct ActivityRewardPanel: View {
    @EnvironmentObject private var store: CompanionStore
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("活动盒子").font(.headline)
            if let reward=store.activityReward {
                if reward.configuredProfile==3 && !reward.isDailySix {
                    Text("六盒版等待启用：请连接匹配的小屋服务").font(.caption.bold()).foregroundStyle(Palette.coral)
                }
                if reward.isTest { Text("短周期测试 · 30 秒 / 盒").font(.caption.bold()).foregroundStyle(Palette.coral) }
                else if reward.isDailySix {
                    Text("每天 08:00 刷新 · 最多 6 盒").font(.caption.bold())
                    Text("每盒再累计 1、3、5、8、12、15 分钟").font(.caption2)
                    Text("当前阶段：再累计 \(reward.intervalSeconds/60) 分钟").font(.caption)
                } else { Text("原版 · 累计 10 分钟 / 盒").font(.caption) }
                if reward.day==0 { Text("先同步小屋服务以确认日期，再开始累计活动").font(.caption) }
                else {
                    Text("今日已获得 \(reward.earnedToday) / \(reward.limit)").accessibilityIdentifier("activity.earned")
                    if reward.earnedToday<reward.limit {
                        ProgressView(value:Double(reward.progressSeconds),total:Double(reward.intervalSeconds))
                        Text("已保存 \(reward.progressSeconds) / \(reward.intervalSeconds) 秒").font(.caption).monospacedDigit().accessibilityIdentifier("activity.progress")
                    } else { Text("今日已达上限，联网确认新日期后继续").font(.caption) }
                }
                if store.physicalMode && !store.bluetooth.ready { Text("蓝牙未连接 · 上次保存的进度").font(.caption) }
                Text(store.activityMessage).font(.caption).foregroundStyle(Palette.muted)
                if reward.offlineClockSupported==true && reward.isDailySix {
                    Text("离线奖励将在小屋服务恢复后自动入库。").font(.caption2).foregroundStyle(Palette.muted)
                    if reward.clockReady==true {
                        Text("已校时 · 有电离线自动08:00刷新").font(.caption)
                        if let next=reward.nextRefreshEpoch,next>0 { Text("下次刷新：\(Date(timeIntervalSince1970:Double(next)).formatted(date:.abbreviated,time:.shortened))").font(.caption2) }
                    } else { Text(reward.lifetimeEnabled==true ? "断电后请连接手机校时，已保存进度保留" : "首次启用请先同步小屋服务并校时").font(.caption) }
                } else { Text(reward.isTest ? "30秒测试版保留原三盒规则，跨日由服务确认。" : "旧固件：离线保留进度，跨日仍需服务确认。").font(.caption2).foregroundStyle(Palette.muted) }
            } else { Text("当前固件尚未提供活动奖励进度，请更新挂件固件。").font(.caption) }
        }.padding(18).frame(maxWidth:.infinity,alignment:.leading).background(Palette.sage,in:PixelFrame())
    }
}
