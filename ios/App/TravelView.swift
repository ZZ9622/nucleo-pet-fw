import SwiftUI
import PetDomain

struct TravelView: View {
    let destination: Residence
    @EnvironmentObject private var store: CompanionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage: Stage = .ready
    @State private var attempt = 0
    @State private var failure: String?
    private enum Stage { case ready, travelling, interrupted, arrived }
    private var motionPaused: Bool { reduceMotion || AppRuntime.isUITesting }

    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 25) {
                    HStack {
                        Eyebrow(text: "ONE FRIEND / TWO LITTLE WORLDS")
                        Spacer()
                        if stage != .travelling {
                            Button { dismiss() } label: { Image(systemName: "xmark").padding(10).background(Palette.line.opacity(0.5), in: Rectangle()) }
                                .buttonStyle(.plain).accessibilityLabel("关闭旅程")
                                .accessibilityIdentifier("travel.close")
                        }
                    }.padding(.bottom, 25)
                    if !store.physicalMode { DemoBadge() }
                    Text(title).font(.system(size: 29, weight: .semibold, design: .monospaced))
                    Text(subtitle).font(.system(size: 14)).foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center).lineSpacing(5)
                    ZStack {
                        Rectangle().fill(Palette.sage.opacity(0.4)).frame(width: 240, height: 240)
                        PixelPet(session: store.session).frame(width: 250, height: 170)
                            .offset(x: stage == .travelling && !motionPaused ? 18 : 0)
                            .animation(stage == .travelling && !motionPaused ? .easeInOut(duration: 0.45).repeatForever(autoreverses: true) : .default, value: stage)
                    }.padding(.vertical, 10)
                    HStack(spacing: 20) {
                        endpoint(destination == .phone ? "挂件" : "手机小屋", symbol: destination == .phone ? "lanyardcard" : "house")
                        if stage == .travelling { ProgressView().tint(Palette.ink) }
                        else { Image(systemName: stage == .arrived ? "checkmark" : "arrow.right").foregroundStyle(Palette.muted) }
                        endpoint(destination.title, symbol: destination == .phone ? "house" : "lanyardcard")
                    }
                    if let failure {
                        Text(failure).font(.system(size: 12)).foregroundStyle(Palette.coral).multilineTextAlignment(.center)
                    }
                    if stage == .travelling {
                        Text("正在收好它的小小行李…").font(.system(size: 13)).foregroundStyle(Palette.muted)
                    } else if stage == .arrived {
                        Button(destination == .phone ? "去小屋看看" : "下次再来玩") { dismiss() }.buttonStyle(FilledButtonStyle())
                            .accessibilityIdentifier("travel.complete")
                    } else {
                        Button(stage == .interrupted ? "继续这次旅程" : "出发吧") { attempt += 1 }.buttonStyle(FilledButtonStyle())
                            .accessibilityIdentifier("travel.start")
                        if store.session.pendingTransfer != nil && !store.physicalMode {
                            Button("暂时留在原来的家") { store.cancelTransfer(); dismiss() }
                                .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        }
                    }
                    Text(store.physicalMode ? (store.connectionKind == .bluetooth ? "真实蓝牙往返 · 请保持挂件在附近；中断后继续同一次旅程。" : "真实 USB 往返 · 交接中请保持 Mac 桥接运行；中断后继续同一次旅程。") : "本次为离线体验，真实挂件不会发生变化。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                }.padding(28)
            }
        }.foregroundStyle(Palette.ink)
        .interactiveDismissDisabled(stage == .travelling)
        .onAppear { if store.session.pendingTransfer != nil { stage = .interrupted } }
        .task(id: attempt) { if attempt > 0 { await travel() } }
    }

    private var title: String {
        switch stage {
        case .ready: return destination == .phone ? "接\(store.session.name)来坐坐" : "送\(store.session.name)回口袋"
        case .travelling: return "带着心情，出发啦"
        case .interrupted: return "小旅程，暂停了一下"
        case .arrived: return destination == .phone ? "我来啦！" : "已经回到挂件啦"
        }
    }

    private var subtitle: String {
        switch stage {
        case .ready: return "同一个\(store.session.name)，带着原来的心情和精力。\n换个地方，继续陪着你。"
        case .travelling: return "小屋和挂件，正在交接它的记录。"
        case .interrupted: return store.physicalMode ? "交接记录已保留。请恢复连接后继续，\n完成前双方暂停互动。" : "记录已经保留。继续出发，\n或者让它先待在原来的家。"
        case .arrived: return "心情、精力和睡眠状态，都一起到了。"
        }
    }

    private func endpoint(_ title: String, symbol: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 24))
            Text(title).font(.system(size: 12))
        }.frame(width: 90)
    }

    @MainActor
    private func travel() async {
        stage = .travelling
        failure = nil
        do {
            if store.physicalMode {
                try await store.travelWithHardware(to: destination)
                stage = .arrived
                return
            }
            let offer = try store.beginTransfer(to: destination)
            try await Task.sleep(for: .milliseconds(1_100))
            if store.simulateDisconnect {
                store.simulateDisconnect = false
                stage = .interrupted
                failure = "模拟连接中断，\(store.session.name)仍在原来的家。"
                return
            }
            try store.finishTransfer(id: offer.id)
            stage = .arrived
        } catch is CancellationError {
            // Prepared offer is already durable; a later launch can resume it.
        } catch {
            stage = .interrupted
            failure = error.localizedDescription
        }
    }
}
