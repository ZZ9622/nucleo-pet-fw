import SwiftUI
import Combine

@main
struct NucleoPetApp: App {
    @StateObject private var store = CompanionStore()
    @AppStorage(PomiLanguage.preferenceKey) private var language = PomiLanguage.system

    var body: some Scene {
        WindowGroup {
            entryView
                .environmentObject(store)
                .environment(\.locale, language.locale)
                .preferredColorScheme(.light)
                #if os(macOS)
                .frame(minWidth: 390, idealWidth: 430, maxWidth: 520, minHeight: 780)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 430, height: 900)
        #endif
    }
    @ViewBuilder private var entryView: some View {
        #if os(iOS)
        if AppRuntime.isUITesting {
            RootView()
        } else {
            AccountTestEntry()
        }
        #else
        RootView()
        #endif
    }

}

struct RootView: View {
    var accountPage: AnyView? = nil
    var selectedPomi: String? = nil
    var socialPage: AnyView? = nil
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
                if store.physicalMode && store.connectionKind == .bluetooth {
                    BluetoothStatusBanner(radio: store.bluetooth)
                }
                Group {
                    switch tab {
                    case 1: CottageView().environmentObject(store.world)
                    case 2: PomiSettingsView(accountPage: accountPage)
                    case 4: socialPage
                    default:
                        VStack(spacing: 0) {
                            if let selectedPomi {
                                Text("当前测试 Pomi · \(selectedPomi.suffix(8).uppercased())")
                                    .font(.caption)
                                    .foregroundStyle(Palette.muted)
                                    .padding(.top, 8)
                            }
                            HomeView(requiresPendant: socialPage != nil, radio: store.bluetooth)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: 0) {
                    tabButton("主页", symbol: "house", index: 0)
                    tabButton("Poyage", symbol: "house.fill", index: 1)
                    if socialPage != nil {
                        tabButton("串门", symbol: "storefront", index: 4)
                    }
                    tabButton("Pomi", symbol: "lanyardcard", index: 2, icon: "PomiTabIcon")
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
        .onReceive(timer) { _ in if scenePhase == .active && !AppRuntime.isUITesting { store.refresh() } }
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

    private func tabButton(_ title: LocalizedStringKey, symbol: String, index: Int, icon: String? = nil) -> some View {
        Button { tab = index } label: {
            VStack(spacing: 5) {
                Group {
                    if let icon {
                        Canvas { context, size in
                            // Map black to blue and the bright cyan cat to white.
                            var colors = ColorMatrix()
                            colors.r1 = 0
                            colors.r3 = 0.89
                            colors.r5 = 0.11
                            colors.g2 = 0
                            colors.g3 = 0.64
                            colors.g5 = 0.36
                            colors.b3 = 0.20
                            colors.b5 = 0.80
                            context.addFilter(.colorMatrix(colors))
                            context.draw(Image(icon), in: CGRect(origin: .zero, size: size))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .accessibilityHidden(true)
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 20, weight: tab == index ? .semibold : .regular))
                    }
                }
                .frame(width: 23, height: 23)
                Text(title).font(.system(size: 11, weight: .medium))
                Rectangle().fill(tab == index ? Palette.ink : .clear).frame(width: 14, height: 3)
            }
            .foregroundStyle(tab == index ? Palette.ink : Palette.muted)
            .frame(maxWidth: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(tab == index ? .isSelected : [])
            .accessibilityIdentifier("tab.\(index)")
    }
}
