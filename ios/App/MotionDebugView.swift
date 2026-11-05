#if DEBUG
import SwiftUI
import PetDomain

struct MotionDebugView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var preview = MotionPreview()
    @State private var events: [String] = []

    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()
            PixelGrid().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Eyebrow(text: "DEV / MOTION LAB")
                        Spacer()
                        Button("完成") { dismiss() }.accessibilityIdentifier("motion.close")
                    }
                    PageHeader(eyebrow: "NO HARDWARE NEEDED", title: "动作调试台", subtitle: "走两步，停一下，轻轻晃一晃。")
                    TimelineView(.animation(minimumInterval: 0.1, paused: scenePhase != .active || AppRuntime.isUITesting)) { _ in
                        let time = ProcessInfo.processInfo.systemUptime
                        VStack(spacing: 12) {
                            ZStack {
                                RoomBackdrop()
                                sprite(preview.pixels(at: time, reduceMotion: reduceMotion))
                                    .frame(height: 205).padding(.top, 15)
                            }.frame(height: 250)
                                .background(.white, in: PixelFrame())
                                .overlay(PixelFrame().stroke(Palette.ink, lineWidth: 2))
                            Text(preview.behavior(at: time).title)
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .accessibilityIdentifier("motion.status")
                        }
                    }
                    HStack(spacing: 10) {
                        ForEach(MotionPreview.Action.allCases) { action in
                            Button { send(action) } label: {
                                VStack(spacing: 10) {
                                    Image(systemName: symbol(action)).font(.system(size: 21))
                                    Text(action.title).font(.system(size: 12, weight: .semibold))
                                }.frame(maxWidth: .infinity, minHeight: 78)
                                    .background(preview.action == action ? Palette.ink : Palette.sage, in: PixelFrame())
                                    .foregroundStyle(preview.action == action ? .white : Palette.ink)
                            }.buttonStyle(.plain).accessibilityIdentifier("motion.\(action.rawValue)")
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("走路：持续踱步，交替迈脚。")
                        Text("停止：立即停下，回到安静待机。")
                        Text("轻晃：短暂左右晃动、冒出惊叹号，再恢复原来的动作。")
                    }.font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(4)
                    HStack {
                        Eyebrow(text: "EVENT LOG / \(preview.eventNumber)")
                        Spacer()
                        Button("重置") {
                            preview = MotionPreview()
                            events = []
                        }.font(.system(size: 12)).accessibilityIdentifier("motion.reset")
                    }
                    if events.isEmpty {
                        Text("点一个动作，开始观察小猫。")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                    ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                        Text(event).font(.system(size: 12, design: .monospaced))
                    }
                    Text("模拟输入 · 独立预览猫 · 不改变心情、精力或真实存档")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }.padding(24)
            }
        }.foregroundStyle(Palette.ink).fontDesign(.monospaced)
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { preview.send(.stop, at: ProcessInfo.processInfo.systemUptime) }
            }
    }

    private func send(_ action: MotionPreview.Action) {
        preview.send(action, at: ProcessInfo.processInfo.systemUptime)
        events.insert("#\(preview.eventNumber)  \(action.title)", at: 0)
        events = Array(events.prefix(8))
    }
    private func symbol(_ action: MotionPreview.Action) -> String {
        switch action { case .walk: return "figure.walk"; case .stop: return "stop.fill"; case .shake: return "waveform" }
    }
    private func sprite(_ pixels: [UInt8]) -> some View {
        Canvas { context, size in
            let unit = max(1, floor(min(size.width / 76, size.height / 45)))
            let left = (size.width - 76 * unit) / 2
            let top = (size.height - 45 * unit) / 2
            var path = Path()
            for y in 19..<64 {
                for x in 30..<106 where pixels[y / 8 * 128 + x] & (1 << (y % 8)) != 0 {
                    path.addRect(CGRect(x: left + Double(x-30) * unit, y: top + Double(y-19) * unit, width: unit, height: unit))
                }
            }
            context.fill(path, with: .color(Palette.ink))
        }.accessibilityLabel("动作预览猫").accessibilityIdentifier("motion.sprite")
    }
}
#endif
