import SwiftUI
import Combine

@main
struct NucleoPetApp: App {
    @StateObject private var store = CompanionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .preferredColorScheme(.light)
                #if os(macOS)
                .frame(minWidth: 390, idealWidth: 430, maxWidth: 520, minHeight: 780)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 430, height: 900)
        #endif
    }
}

struct RootView: View {
    @EnvironmentObject private var store: CompanionStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()
            PixelGrid().ignoresSafeArea()
            if !store.hasEnteredHome {
                ConnectionView().frame(maxWidth: 520)
            } else { VStack(spacing: 0) {
                Group {
                    switch tab {
                    case 1: JourneyView()
                    case 2: DeviceView()
                    default: HomeView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: 0) {
                    tabButton("小屋", symbol: "house", index: 0)
                    tabButton("足迹", symbol: "sparkles", index: 1)
                    tabButton("挂件", symbol: "lanyardcard", index: 2)
                }
                .padding(.top, 14).padding(.bottom, 10)
                .background(Palette.paper)
                .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
            }
            .frame(maxWidth: 520) }
        }
        .fontDesign(.monospaced)
        .tint(Palette.ink)
        .onChange(of: store.hasEnteredHome) { _, entered in if entered { tab = 0 } }
        .onReceive(timer) { _ in if !AppRuntime.isUITesting { store.refresh() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refresh() } else { store.flush() }
        }
        .alert("记录暂时没有保存", isPresented: Binding(
            get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("重试保存") { store.flush() }
            Button("稍后", role: .cancel) { }
        } message: { Text(store.errorMessage ?? "") }
        .sheet(isPresented: Binding(get: { store.needsRecovery }, set: { _ in })) {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "externaldrive.badge.exclamationmark").font(.largeTitle)
                Text("先保管好它的记录").font(.title2.bold())
                Text("原记录暂时无法读取，已保留。可以重试；也可以先备份原文件，再创建新的体验宠物。")
                    .foregroundStyle(Palette.muted)
                Button("重新读取") { store.reload() }.buttonStyle(FilledButtonStyle())
                if !store.physicalMode { Button("备份后重新开始") { store.recoverWithBackup() }.buttonStyle(QuietButtonStyle()) }
            }
            .padding(32).interactiveDismissDisabled()
        }
    }

    private func tabButton(_ title: String, symbol: String, index: Int) -> some View {
        Button { tab = index } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 20, weight: tab == index ? .semibold : .regular))
                Text(title).font(.system(size: 11, weight: .medium))
                Rectangle().fill(tab == index ? Palette.ink : .clear).frame(width: 14, height: 3)
            }
            .foregroundStyle(tab == index ? Palette.ink : Palette.muted)
            .frame(maxWidth: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(tab == index ? .isSelected : [])
            .accessibilityIdentifier("tab.\(index)")
    }
}
