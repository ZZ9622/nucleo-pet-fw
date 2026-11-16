import SwiftUI
import Combine
import PetDomain

struct JourneySection: View {
    @EnvironmentObject private var store: CompanionStore
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Text("一起走过的足迹").font(.headline)
            ForEach(store.session.journal.prefix(8)) { entry in
                HStack(alignment:.top,spacing:12) {
                    Image(systemName:entry.symbol).frame(width:24)
                    VStack(alignment:.leading,spacing:4) {
                        Text(entry.title).font(.subheadline)
                        Text(entry.date,format:.dateTime.month().day().hour().minute()).font(.caption2).foregroundStyle(Palette.muted)
                    }
                }
            }
            WorldMoments(world:store.world)
        }.padding(18).frame(maxWidth:.infinity,alignment:.leading).background(Palette.sage,in:PixelFrame())
    }
}
private struct WorldMoments: View {
    @ObservedObject var world:PomiWorldStore
    var body: some View {
        ForEach(world.inventory.log.prefix(8)) { moment in
            HStack(alignment:.top,spacing:12) {
                Image(systemName:"sparkles").frame(width:24)
                VStack(alignment:.leading,spacing:4) {
                    Text(moment.text).font(.subheadline)
                    Text(Date(timeIntervalSince1970:moment.date),format:.dateTime.month().day().hour().minute()).font(.caption2).foregroundStyle(Palette.muted)
                }
            }
        }
    }
}
struct CottageView: View {
    @EnvironmentObject private var store: CompanionStore
    @EnvironmentObject private var world: PomiWorldStore
    @State private var section=0
    @State private var selected: PomiItem?
    @State private var releasing: PomiItem?
    @State private var showService=false
    @State private var listingItemID: String?
    @State private var wantedKinds: [String] = []
    @State private var listingError = ""
    private let columns=[GridItem(.adaptive(minimum:86),spacing:10)]
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                PageHeader(eyebrow:"Pomi / LITTLE COLLECTIONS",title:"把日子装进小屋",subtitle:"出门遇见惊喜，回家留下一点风景。")
                if world.preview { Text("独立预览 · 模拟物品与放生海").font(.caption.bold()).padding(10).background(Palette.blush) }
                if store.physicalMode { ActivityRewardPanel() }
                room
                if !world.inventory.room.isEmpty {
                    DisclosureGroup("已摆放的收藏") {
                        HStack { slot("wall", "墙面"); Spacer(); slot("corner", "角落") }
                        HStack { slot("floor", "地面"); Spacer(); slot("table", "桌面") }
                        Text("长按物品可收回仓库。猫塔家具布置将在后续接入。")
                            .font(.caption).foregroundStyle(Palette.muted)
                    }
                }
                Picker("小屋内容",selection:$section) {
                    Text("仓库").tag(0);Text("放生海").tag(1)
                }.pickerStyle(.segmented).accessibilityIdentifier("cottage.section")
                if section==0 { warehouse } else { sea }
                if !world.message.isEmpty && !(showService && !world.preview && world.accountID == nil) { Text(world.message).font(.footnote).foregroundStyle(Palette.muted).accessibilityIdentifier("world.message") }
                if !world.preview {
                    Button(world.accountID == nil ? "同步真实仓库" : "同步账号仓库") { Task { await world.connect() } }.buttonStyle(QuietButtonStyle()).disabled(world.busy)
                    if world.accountID == nil {
                        Button("小屋服务设置") { showService.toggle() }.buttonStyle(QuietButtonStyle())
                        if showService {
                            TextField("https://你的服务地址",text:$world.serviceURL).textFieldStyle(.roundedBorder).autocorrectionDisabled()
                            Text("身份保存在本机钥匙串。换手机前请先保留身份；当前版本尚无账号找回功能。").font(.caption).foregroundStyle(Palette.muted)
                            Button(world.busy ? "正在同步…" : "连接并同步仓库") {
                                Task { await world.connect() }
                            }
                            .buttonStyle(FilledButtonStyle())
                            .disabled(world.busy)
                            if world.busy {
                                ProgressView("正在联系小屋服务")
                                    .font(.footnote)
                            }
                            if !world.message.isEmpty {
                                Text(world.message)
                                    .font(.footnote)
                                    .foregroundStyle(Palette.muted)
                            }
                        }
                    }
                }
                #if DEBUG
                if world.preview {
                    Button("模拟一次有效散步") { act("/activity") }.buttonStyle(QuietButtonStyle()).accessibilityIdentifier("world.walk")
                    Text("实际活动奖励等待加速度模块接入；预览按钮不会发放真实物品。").font(.caption2).foregroundStyle(Palette.muted)
                }
                #endif
            }.padding(24).foregroundStyle(Palette.ink)
        }
        .sheet(item:$selected, onDismiss: resetListing) { item in
            itemSheet(item)
                .interactiveDismissDisabled(world.busy)
        }

    }
    private var room: some View {
        CatTowerEntrance(session: store.session)
            .id(store.session.petID)
    }
    private func slot(_ key:String,_ title:String) -> some View {
        let item=world.inventory.items.first{$0.id==world.inventory.room[key]}
        return VStack(spacing:7) {
            if let item { ItemGlyph(item:item,entry:world.inventory.entry(item)).frame(width:60,height:44) }
            else { Image(systemName:"plus").font(.title2).foregroundStyle(Palette.line).frame(width:60,height:44) }
            Text(item.map{world.inventory.entry($0).name} ?? title).font(.caption2)
        }.frame(width:105).contextMenu {
            if item != nil { Button("收回仓库") { act("/decorate",["slot":key]) } }
        }.accessibilityLabel(item.map{"\(title)：\(world.inventory.entry($0).name)"} ?? "\(title)，空位")
    }
    private var warehouse: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("随机物品 · 格子仓库").font(.headline)
            if let pending=world.inventory.pending {
                VStack(alignment:.leading,spacing:10) {
                    Label(pending.kind=="open" ? "盒子等待确认" : "点心等待挂件按键确认",systemImage:"clock")
                    Text("断连不会丢失这次操作。请连接原挂件后继续。").font(.caption)
                    Button("继续挂件操作") { Task { await store.continueItem() } }.buttonStyle(QuietButtonStyle()).disabled(store.hardwareBusy || world.busy)
                    #if DEBUG
                    if world.preview { Button("模拟挂件确认") { Task { await store.confirmPreviewItem() } }.buttonStyle(FilledButtonStyle()).accessibilityIdentifier("world.confirm") }
                    #endif
                }.padding(14).background(Palette.blush,in:PixelFrame())
            }
            Text("待开盒子 \(world.inventory.boxes.count)").font(.subheadline.bold())
            Text("宠物在挂件上、精力 ≥ 10 时可开盒，每次消耗 10 精力。").font(.caption).foregroundStyle(Palette.muted)
            LazyVGrid(columns:columns,spacing:10) {
                ForEach(world.inventory.boxes,id:\.self) { box in
                    Button { Task { await store.startItem(kind:"open",id:box) } } label: {
                        VStack(spacing:8) { Image(systemName:"shippingbox.fill").font(.largeTitle);Text("打开盒子").font(.caption2) }.frame(maxWidth:.infinity).frame(height:94).background(Palette.sage,in:PixelFrame())
                    }.buttonStyle(.plain).disabled(world.busy || store.hardwareBusy || world.inventory.pending != nil || store.session.residence != .device)
                        .accessibilityIdentifier("world.box")
                }
                ForEach(world.inventory.items) { item in
                    Button { selected=item } label: {
                        VStack(spacing:6) {
                            ItemGlyph(item:item,entry:world.inventory.entry(item)).frame(height:38)
                            Text(world.inventory.entry(item).name).font(.system(size:10))
                            Text("Lv\(item.level)\(world.inventory.room.values.contains(item.id) ? " · 已摆放":"")").font(.system(size:9)).foregroundStyle(Palette.muted)
                        }.frame(maxWidth:.infinity).frame(height:94).background(.white,in:PixelFrame()).overlay(PixelFrame().stroke(Palette.line,lineWidth:1))
                    }.buttonStyle(.plain).accessibilityIdentifier("world.item.\(item.kind)")
                }
            }
            if world.inventory.items.isEmpty && world.inventory.boxes.isEmpty { Text("仓库还空着。带着挂件去走走，等待下一份惊喜。").font(.footnote).padding(.vertical) }
        }
    }
    private var sea: some View {
        VStack(alignment:.leading,spacing:18) {
            ZStack {
                Rectangle().fill(Palette.room)
                VStack(spacing:15) {
                    Text("～  ～  ～  ～  ～").font(.title).foregroundStyle(Palette.muted)
                    PixelBottle().frame(width:58,height:70)
                    Text("放生海").font(.title2.bold())
                    Text("让不再需要的收藏，成为别人的惊喜。").font(.caption)
                }
            }.frame(height:210).overlay(PixelFrame().stroke(Palette.ink,lineWidth:2))
            Text("捞取机会 \(world.inventory.chances) / 3").font(.headline)
            Text("每 3 小时恢复一次，最多保留 3 次。不消耗宠物精力。").font(.caption).foregroundStyle(Palette.muted)
            if world.inventory.chances<3 && world.inventory.nextChanceAt>0 {
                Text("下次恢复：\(Date(timeIntervalSince1970:world.inventory.nextChanceAt).formatted(date:.omitted,time:.shortened))").font(.caption)
            }
            Button("捞一个漂流瓶") { act("/fish") }.buttonStyle(FilledButtonStyle()).disabled(world.busy).accessibilityIdentifier("world.fish")
            Text("仓库中选择闲置物品即可放生。真实海域需要连接小屋服务；不会捞到自己放生的物品。").font(.caption).foregroundStyle(Palette.muted)
        }
    }
    private func itemSheet(_ item:PomiItem) -> some View {
        let entry=world.inventory.entry(item)
        let placed=world.inventory.room.values.contains(item.id)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ItemGlyph(item:item,entry:entry).frame(height:70).frame(maxWidth:.infinity)
                Text("\(entry.name) · Lv\(item.level)").font(.title2.bold())
                if let slot=entry.slot {
                    Button(placed ? "收回仓库":"摆进小屋") { act("/decorate",placed ? ["slot":slot]:["slot":slot,"itemID":item.id]);selected=nil }.buttonStyle(FilledButtonStyle()).accessibilityIdentifier("world.decorate")
                }
                if entry.category=="food" {
                    Button("送到挂件，按键确认使用") { selected=nil;Task { await store.startItem(kind:"food",id:item.id) } }.buttonStyle(FilledButtonStyle()).accessibilityIdentifier("world.food").disabled(store.session.residence != .device || world.inventory.pending != nil)
                    Text("手机选择后不立即消耗；请在挂件上按 B1 确认。").font(.caption)
                }
                if item.level==1 { Button("三个相同 Lv1 合成 Lv2") { act("/merge",["itemID":item.id]);selected=nil }.buttonStyle(QuietButtonStyle()).disabled(placed) }
                if world.accountID != nil && !placed && world.inventory.pending?.itemID != item.id {
                    if listingItemID == item.id {
                        Text("想换的 Lv1 物品 · \(wantedKinds.count)/3")
                            .font(.subheadline.bold())
                        Text("好友给出其中一种即可交换。")
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                        ForEach(world.inventory.catalog) { entry in
                            let chosen = wantedKinds.contains(entry.id)
                            Button {
                                if chosen {
                                    wantedKinds.removeAll { $0 == entry.id }
                                } else {
                                    wantedKinds.append(entry.id)
                                }
                            } label: {
                                HStack {
                                    Text(entry.name)
                                    Spacer()
                                    Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                                }
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!chosen && wantedKinds.count >= 3)
                            .accessibilityAddTraits(chosen ? .isSelected : [])
                        }
                        Button("确认上架") { listItem(item) }
                            .buttonStyle(FilledButtonStyle())
                            .disabled(wantedKinds.isEmpty || world.busy)
                        Button("取消上架", action: resetListing)
                            .buttonStyle(.plain)
                            .disabled(world.busy)
                        if !listingError.isEmpty {
                            Text(listingError).font(.footnote).foregroundStyle(Palette.muted)
                        }
                    } else {
                        Button("上架到小卖部") { listingItemID = item.id }
                            .buttonStyle(QuietButtonStyle())
                            .disabled(world.busy)
                    }
                }
                if releasing?.id==item.id {
                    Text("放生后无法撤回，它会成为别人的惊喜。").font(.caption)
                    HStack {
                        Button("确认放生") { act("/release",["itemID":item.id]);releasing=nil;selected=nil }.buttonStyle(FilledButtonStyle())
                        Button("取消") { releasing=nil }.buttonStyle(QuietButtonStyle())
                    }
                } else {
                    Button("放入漂流瓶") { releasing=item }.buttonStyle(QuietButtonStyle()).accessibilityIdentifier("world.release").disabled(placed || world.inventory.pending?.itemID==item.id)
                }
                Button("返回") { selected=nil }.buttonStyle(.plain).disabled(world.busy)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Palette.ink)
        .presentationDetents([.large])
        .disabled(world.busy)

    }
    private func resetListing() {
        listingItemID = nil
        wantedKinds = []
        listingError = ""
    }

    private func listItem(_ item: PomiItem) {
        let kinds = wantedKinds
        listingError = ""
        Task {
            do {
                try await world.perform("/shop/list", ["itemID": item.id, "wantedKinds": kinds])
                world.message = "已上架，可在「串门」查看。"
                selected = nil
            } catch {
                listingError = error.localizedDescription
            }
        }
    }

    private func act(_ path:String,_ body:[String:Any]=[:]) {
        Task { do { _ = try await world.perform(path,body) } catch { world.message=error.localizedDescription } }
    }
}
/// Small code-native pixel objects, crisp at every scale.
struct ItemGlyph: View {
    let item:PomiItem
    let entry:PomiCatalogEntry
    private var rows:[String] {
        switch item.kind {
        case "plant": return ["0001000","0011100","0101010","0001000","0111110","0011100","0011100"]
        case "cushion": return ["0000000","0011100","0111110","1111111","1111111","0111110","0000000"]
        case "picture": return ["1111111","1000001","1010101","1001001","1011101","1111111","0000000"]
        case "shell": return ["0011100","0111110","1111111","1010101","0101010","0011100","0001000"]
        default: return ["0001000","0011100","0111110","1111111","1101011","0111110","0011100"]
        }
    }
    var body: some View {
        GeometryReader { g in
            let unit=floor(min(g.size.width,g.size.height)/7)
            Path { p in
                for (y,row) in rows.enumerated() { for (x,c) in row.enumerated() where c=="1" { p.addRect(CGRect(x:Double(x)*unit,y:Double(y)*unit,width:unit,height:unit)) } }
            }.fill(item.level==2 ? Color(red:0.1,green:0.55,blue:0.9):Palette.ink)
                .frame(width:unit*7,height:unit*7).frame(maxWidth:.infinity,maxHeight:.infinity)
        }.accessibilityLabel("\(entry.name)，等级\(item.level)")
    }
}

private struct PixelBottle: View {
    private let rows=["000111000","000111000","000101000","001101100","011000110","010000010","010111010","010101010","010111010","010000010","011111110"]
    var body: some View {
        GeometryReader { g in
            let u=floor(min(g.size.width/9,g.size.height/11))
            Path { path in
                for (y,row) in rows.enumerated() { for (x,c) in row.enumerated() where c=="1" {
                    path.addRect(CGRect(x:Double(x)*u,y:Double(y)*u,width:u,height:u))
                } }
            }.fill(Palette.ink).frame(width:u*9,height:u*11).frame(maxWidth:.infinity,maxHeight:.infinity)
        }.accessibilityHidden(true)
    }
}

// MARK: - Cat tower prototype
private enum TowerColors {
    static let ink = Palette.ink
    static let sky = Palette.blush
    static let cream = Palette.paper
    static let wood = Palette.ink
    static let green = Palette.coral
}

private final class TowerLocalStore: ObservableObject {
    @Published var tower: CatTower
    @Published var loadFailed = false
    private let key: String
    init(key: String) {
        self.key = "pomi.catTower.v1." + key
        if let data = UserDefaults.standard.data(forKey: self.key) {
            if let saved = try? JSONDecoder().decode(CatTower.self, from: data) { tower = saved }
            else { tower = CatTower(); loadFailed = true }
        } else { tower = CatTower() }
    }
    func change(_ update: (inout CatTower) -> Void) {
        guard !loadFailed else { return }
        var next = tower
        update(&next)
        guard next != tower, let data = try? JSONEncoder().encode(next) else { return }
        UserDefaults.standard.set(data, forKey: key)
        tower = next
    }
}

struct CatTowerEntrance: View {
    let session: CompanionSession
    private var name: String { session.name }
    @StateObject private var local: TowerLocalStore
    @State private var open = false
    @State private var adventureNotice = false
    init(session: CompanionSession) {
        self.session = session
        _local = StateObject(wrappedValue: TowerLocalStore(key: session.petID.uuidString))
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(name)的家").font(.system(size: 15, weight: .bold, design: .monospaced))
                Spacer()
                Label("塔主之家", systemImage: "leaf").font(.caption2)
            }.padding(14).background(TowerColors.cream)
            HStack(spacing: 0) {
                Button { open = true } label: {
                    ZStack(alignment: .bottomLeading) {
                        TowerRoomArt(home: true, cats: [], master: session)
                        Text("进屋看看 ↑")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(8).background(TowerColors.cream.opacity(0.95)).padding(10)
                    }.frame(height: 205).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("进入\(name)的猫塔")
                    .accessibilityIdentifier("tower.open")
                Button { adventureNotice = true } label: {
                    VStack(spacing: 13) {
                        Image(systemName: "arrow.right").font(.system(size: 21, weight: .bold))
                        Text("探\n险").font(.system(size: 12, weight: .bold))
                    }.frame(width: 43, height: 205)
                        .background(TowerColors.wood).foregroundStyle(TowerColors.cream)
                }.buttonStyle(.plain).accessibilityLabel("探险入口，尚未开放")
                    .accessibilityIdentifier("tower.adventure")
            }
            HStack(spacing: 6) {
                Circle().fill(TowerColors.green).frame(width: 5, height: 5)
                Text(local.tower.visitor == nil ? "一盏灯，等每个小伙伴回家" : "门口有一只小猫，正在等你")
                Spacer(minLength: 0)
            }.font(.system(size: 11)).padding(12).background(TowerColors.cream)
        }
        .foregroundStyle(TowerColors.ink)
        .clipShape(PixelFrame())
        .overlay(PixelFrame().stroke(Palette.ink, lineWidth: 2))
        .alert("下一段旅程", isPresented: $adventureNotice) {
            Button("回家吧", role: .cancel) {}
        } message: { Text("藤蔓的另一边，会通向哪里呢？探险模式还在准备中。") }
        #if os(iOS)
        .fullScreenCover(isPresented: $open) { CatTowerGame(session: session, local: local) }
        #else
        .sheet(isPresented: $open) { CatTowerGame(session: session, local: local).frame(minWidth: 390, minHeight: 750) }
        #endif
        .onAppear { local.change { $0.refresh() } }
    }
}

private struct TowerLiftRide: Identifiable {
    let id = UUID()
    let cat: CatTower.Resident
    let source: Int
    let destination: Int
}

private struct TowerStopPreference: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct TowerStopMarker: View {
    let stop: Int
    var fraction: CGFloat = 0.72
    var body: some View {
        GeometryReader { g in
            Color.clear.preference(key: TowerStopPreference.self,
                value: [stop: g.frame(in: .named("tower.shaft")).minY + g.size.height * fraction])
        }.allowsHitTesting(false)
    }
}

private struct CatTowerGame: View {
    let session: CompanionSession
    private var name: String { session.name }
    @ObservedObject var local: TowerLocalStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedFloor: Int?
    @State private var showResidents = false
    @State private var arrivalMessage = ""
    @State private var showConstruction = false
    @State private var showWarehouse = false
    @State private var showPurchaseNotice = false
    @State private var departingCat: CatTower.Resident?
    @State private var confirmDemolition = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stops: [Int: CGFloat] = [:]
    @State private var pendingRide: TowerLiftRide?
    @State private var ride: TowerLiftRide?
    @State private var liftProgress: CGFloat = 0
    @State private var returning = false
    @State private var liftStatus = ""
    private var panelIsOpen: Bool { showConstruction || showWarehouse || showResidents || selectedFloor != nil }
    private var liftBusy: Bool { pendingRide != nil || ride != nil }
    private var travellingCatID: UUID? { returning ? nil : (ride ?? pendingRide)?.cat.id }
    private let timer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(spacing: 0) {
            header
            if local.loadFailed {
                Text("小屋记录暂时无法读取，原记录已保留。请先返回，稍后再试。")
                    .font(.callout).padding().background(TowerColors.cream)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        roof
                        VStack(spacing: 0) {
                            ForEach(Array((1...local.tower.floors).reversed()), id: \.self) { floor in
                                floorView(floor).id(floor)
                            }
                            home.id("masterHome")
                            lobby.id(0)
                            doorstep.id("doorstep")
                        }
                        .padding(.trailing, 43)
                        .overlay(alignment: .trailing) {
                            TowerVine().frame(width: 38)
                        }
                        .overlay {
                            GeometryReader { g in
                                TowerLiftCar(coat: returning ? nil : ride?.cat.coat)
                                    .frame(width: 34, height: 52)
                                    .position(x: g.size.width - 19, y: liftPosition(fallback: g.size.height - 180))
                            }.allowsHitTesting(false)
                        }
                        .coordinateSpace(name: "tower.shaft")
                        .onPreferenceChange(TowerStopPreference.self) { stops = $0 }
                    }.padding(.horizontal, 14).padding(.top, 22).padding(.bottom, 24)
                        .frame(maxWidth: 520)
                        .frame(maxWidth: .infinity)
                        .background(TowerSky())
                }
                .scrollDisabled(liftBusy)
                .onAppear { proxy.scrollTo("doorstep", anchor: .bottom) }
                .task(id: ride?.id) {
                    guard let current = ride else { return }
                    await animateRide(current, proxy: proxy)
                }
                .onChange(of: local.tower.floors) { _, count in
                    withAnimation(.easeInOut(duration: 0.6)) { proxy.scrollTo(count, anchor: .top) }
                }
                .overlay(alignment: .bottomTrailing) {
                    Button { withAnimation { proxy.scrollTo("doorstep", anchor: .bottom) } } label: {
                        Label("回家", systemImage: "arrow.down").font(.caption.bold())
                            .padding(11).background(TowerColors.cream, in: Capsule())
                            .overlay(Capsule().stroke(TowerColors.wood, lineWidth: 1))
                    }.buttonStyle(.plain).padding(15).accessibilityIdentifier("tower.ground").disabled(liftBusy)
                }
            }
            HStack {
                if liftBusy {
                    Text(liftStatus.isEmpty ? "正在准备藤蔓电梯" : liftStatus)
                        .font(.system(size: 11)).accessibilityIdentifier("tower.lift.busy")
                        .accessibilityAddTraits(.updatesFrequently)
                } else {
                    Text(liftStatus.isEmpty ? "猫猫上岗后自动生产 · 原料全塔共享" : liftStatus)
                        .font(.system(size: 11)).accessibilityIdentifier("tower.lift.idle")
                }
                Spacer()
                Button { showResidents = true } label: { Label("居民 \(local.tower.residents.count)", systemImage: "pawprint") }
                    .font(.system(size: 12, weight: .bold)).accessibilityIdentifier("tower.residents")
                    .disabled(liftBusy)
            }.padding(14).background(Palette.sage)
        }
        .foregroundStyle(TowerColors.ink)
        .background(TowerColors.sky)
        .allowsHitTesting(!panelIsOpen)
        .accessibilityHidden(panelIsOpen)
        .overlay { towerPopup }
        .onChange(of: panelIsOpen) { _, open in if !open { beginPendingRide() } }
        .alert("和\(departingCat?.name ?? "猫猫")告别？", isPresented: Binding(get: { departingCat != nil && !showResidents }, set: { if !$0 { departingCat = nil } }), presenting: departingCat) { cat in
            Button("留下它", role: .cancel) { departingCat = nil }
            Button("花 \(CatTower.releaseCost) 喵币请它离开", role: .destructive) { releaseResident(cat) }
                .disabled(local.tower.coins < CatTower.releaseCost || local.loadFailed || liftBusy)
        } message: { _ in
            Text(local.tower.coins < CatTower.releaseCost
                ? "送别需要 \(CatTower.releaseCost) 喵币，当前余额 \(local.tower.coins)，余额不足。"
                : "将花费 \(CatTower.releaseCost) 喵币为它准备路费。离开后无法找回这只猫；如有工作岗位，岗位将空出。")
        }
        .onReceive(timer) { _ in if scenePhase == .active { local.change { $0.refresh() } } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { local.change { $0.refresh() } }
            else { finishInterruptedRide() }
        }
        .onDisappear { finishInterruptedRide() }
    }

    private func closePopup() {
        showConstruction = false
        showWarehouse = false
        showResidents = false
        selectedFloor = nil
    }

    @ViewBuilder private var towerPopup: some View {
        if panelIsOpen {
            GeometryReader { geometry in
                let side = max(1, min(520, min(geometry.size.width - 28, geometry.size.height - 28)))
                ZStack {
                    Palette.ink.opacity(0.38)
                        .contentShape(Rectangle())
                        .onTapGesture { closePopup() }
                        .accessibilityLabel("关闭弹窗")
                        .accessibilityAddTraits(.isButton)
                    Group {
                        if showConstruction { constructionPanel }
                        else if showWarehouse { warehousePanel }
                        else if showResidents { residentsPanel }
                        else if let floor = selectedFloor { assignmentPanel(floor) }
                    }
                    .frame(width: side, height: side)
                    .background(Palette.paper)
                    .clipShape(PixelFrame())
                    .overlay(PixelFrame().stroke(Palette.ink, lineWidth: 2))
                    .shadow(color: Palette.ink.opacity(0.2), radius: 16, y: 8)
                    .accessibilityAddTraits(.isModal)
                    .accessibilityIdentifier("tower.popup")
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func releaseResident(_ cat: CatTower.Resident) {
        var released = false
        local.change { released = $0.release(cat.id) }
        liftStatus = released ? "\(cat.name)带着路费离开了猫塔" : "未能送别，请检查喵币余额"
        departingCat = nil
    }

    private func prepareRide(_ cat: CatTower.Resident, to destination: Int?) {
        guard !liftBusy, !local.loadFailed, cat.floor != destination else { return }
        var accepted = false
        // Reserve and persist the destination first. Interrupted animations can never lose a resident.
        local.change { tower in
            if let destination { accepted = tower.assign(cat.id, to: destination) }
            else { tower.unassign(cat.id); accepted = true }
        }
        guard accepted else { return }
        arrivalMessage = ""
        pendingRide = TowerLiftRide(cat: cat, source: cat.floor ?? 0, destination: destination ?? 0)
        liftStatus = "\(cat.name)准备乘坐藤蔓电梯"
        selectedFloor = nil
        showResidents = false
    }

    private func beginPendingRide() {
        guard ride == nil, let next = pendingRide else { return }
        returning = false
        liftProgress = 0
        ride = next
        pendingRide = nil
    }

    private func liftPosition(fallback: CGFloat) -> CGFloat {
        guard let ride else { return stops[0] ?? fallback }
        let start = stops[returning ? ride.destination : ride.source] ?? fallback
        let end = stops[returning ? 0 : ride.destination] ?? fallback
        return start + (end - start) * liftProgress
    }

    @MainActor private func animateRide(_ current: TowerLiftRide, proxy: ScrollViewProxy) async {
        let destinationName = current.destination == 0 ? "大厅" : "第\(current.destination)层"
        if reduceMotion {
            proxy.scrollTo(current.destination, anchor: .center)
            liftStatus = "\(current.cat.name)已到达\(destinationName)"
            ride = nil
            return
        }
        do {
            withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(current.source, anchor: .center) }
            liftStatus = "\(current.cat.name)上电梯啦"
            try await Task.sleep(nanoseconds: 700_000_000)
            let duration = min(5.5, 1.6 + Double(abs(current.destination - current.source)) * 0.45)
            liftStatus = "正在送\(current.cat.name)去\(destinationName)"
            withAnimation(.linear(duration: duration)) {
                liftProgress = 1
                proxy.scrollTo(current.destination, anchor: .center)
            }
            try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            liftStatus = "\(current.cat.name)已到达\(destinationName)"
            // Reveal the resident in its room, then send the empty basket back to the lobby.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { returning = true; liftProgress = 0 }
            try await Task.sleep(nanoseconds: 450_000_000)
            let returnDuration = min(3.5, 0.8 + Double(current.destination) * 0.25)
            withAnimation(.easeInOut(duration: returnDuration)) { liftProgress = 1 }
            try await Task.sleep(nanoseconds: UInt64(returnDuration * 1_000_000_000))
            ride = nil
            returning = false
            liftProgress = 0
        } catch {
            // Assignment is already durable; cancellation only ends its presentation.
            if ride?.id == current.id { finishInterruptedRide() }
        }
    }

    private func finishInterruptedRide() {
        if let current = ride ?? pendingRide {
            liftStatus = "\(current.cat.name)的楼层安排已保存"
        }
        ride = nil
        pendingRide = nil
        liftProgress = 0
        returning = false
    }

    private var lobby: some View {
        let waiting = local.tower.lobbyResidents.filter { $0.id != travellingCatID }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("底层大厅", systemImage: "door.left.hand.open")
                Spacer()
                Text("\(waiting.count) 位等候").accessibilityIdentifier("tower.lobby.count")
            }.font(.system(size: 13, weight: .semibold)).padding(12)
                .background(Palette.ink).foregroundStyle(Palette.paper)
            if waiting.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "pawprint").font(.title2)
                    Text("收留的小伙伴会先在大厅休息")
                    Text("等你为它安排一个合适的楼层")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }.font(.system(size: 12)).frame(maxWidth: .infinity).frame(height: 122)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(waiting) { cat in
                            VStack(spacing: 5) {
                                Button { showResidents = true } label: {
                                    VStack(spacing: 5) {
                                        TowerCat(coat: cat.coat).frame(width: 44, height: 36)
                                        Text(cat.name).font(.system(size: 12, weight: .semibold))
                                        Text("等待分配").font(.system(size: 10)).foregroundStyle(Palette.muted)
                                    }
                                }.buttonStyle(.plain).accessibilityIdentifier("tower.lobby.\(cat.name)")
                                Button("请走 · \(CatTower.releaseCost) 喵币", role: .destructive) { departingCat = cat }
                                    .font(.system(size: 10, weight: .semibold))
                                    .accessibilityIdentifier("tower.lobby.release.\(cat.id)")
                            }.frame(width: 96, height: 105).background(Palette.sage, in: PixelFrame())
                                .disabled(liftBusy || local.loadFailed)
                        }
                    }.padding(10)
                }.frame(height: 125)
            }
        }.background(Palette.paper)
            .overlay(PixelFrame().stroke(Palette.ink, lineWidth: 2))
            .background(TowerStopMarker(stop: 0, fraction: 0.64))
            .padding(.top, 6)
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "chevron.left").font(.title3.bold()).frame(width: 40, height: 42) }
                .accessibilityLabel("返回小屋窗口").accessibilityIdentifier("tower.close")
            VStack(alignment: .leading, spacing: 3) {
                Text("\(name)的猫塔").font(.system(size: 20, weight: .bold, design: .monospaced))
                Text("向上长一点，多一个家").font(.system(size: 11))
            }
            Spacer()
            Button { showWarehouse = true } label: {
                Text("◈ \(local.tower.coins) 喵币 · 仓库")
            }
                .font(.system(size: 11, weight: .medium)).padding(.trailing, 14)
        }.padding(.vertical, 6).background(TowerColors.cream)
    }
    private var roof: some View {
        VStack(spacing: 10) {
            Image(systemName: "leaf.fill").font(.title).foregroundStyle(TowerColors.green)
            Text("下一层，会住进怎样的故事？").font(.system(size: 12)).foregroundStyle(Palette.muted)
            Button {
                showConstruction = true
            } label: {
                Label(local.tower.floors >= CatTower.maximumFloors ? "已经长到云朵旁啦" : "扩建 · \(local.tower.expansionCost) 喵币起", systemImage: "plus")
                    .font(.system(size: 14, weight: .bold)).padding(.horizontal, 20).padding(.vertical, 12)
                    .background(TowerColors.cream, in: PixelFrame())
                    .overlay(PixelFrame().stroke(Palette.ink, lineWidth: 2))
            }.buttonStyle(.plain).disabled(liftBusy || local.loadFailed || local.tower.floors >= CatTower.maximumFloors)
                .accessibilityIdentifier("tower.expand")
            Text("选择产业，连接原料与店铺").font(.system(size: 10)).foregroundStyle(Palette.muted)
        }.padding(.bottom, 26)
    }
    private func floorView(_ floor: Int) -> some View {
        let cats = local.tower.residents.filter { $0.floor == floor && $0.id != travellingCatID }
        return Button { selectedFloor = floor } label: {
                VStack(spacing: 0) {
                    HStack {
                        Text(String(format: "%02d", floor)).font(.system(size: 12, weight: .bold, design: .monospaced))
                        Text(local.tower.facilities[floor]?.title ?? "待建设").font(.system(size: 13, weight: .bold, design: .monospaced))
                        Spacer()
                        Text("\(cats.count)/\(CatTower.capacity)").font(.system(size: 11))
                        Image(systemName: "chevron.right").font(.system(size: 10))
                    }.padding(10).background(TowerColors.wood).foregroundStyle(TowerColors.cream)
                    ZStack(alignment: .bottom) {
                        TowerFacilityArt(facility: local.tower.facilities[floor], cats: cats.map(\.coat), active: local.tower.status(at: floor).hasPrefix("正在"))
                        Text(local.tower.status(at: floor))
                            .font(.system(size: 10, weight: .medium)).padding(5)
                            .background(TowerColors.cream.opacity(0.94)).padding(.bottom, 8)
                    }.frame(height: 184)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("tower.floor.\(floor)")
                .accessibilityLabel("第\(floor)层，\(cats.count)位居民，点击安排")
            .background(Palette.paper)
            .overlay(PixelFrame().stroke(Palette.ink, lineWidth: 2))
            .background(TowerStopMarker(stop: floor))
            .disabled(liftBusy)
            .padding(.bottom, 6)
    }
    private var home: some View {
        VStack(spacing: 0) {
            Text("塔主之家 · \(name)").font(.system(size: 14, weight: .bold)).padding(10)
                .frame(maxWidth: .infinity).background(TowerColors.wood).foregroundStyle(TowerColors.cream)
            TowerRoomArt(home: true, cats: [], master: session).frame(height: 210)
        }.overlay(PixelFrame().stroke(Palette.ink, lineWidth: 2))
    }
    private var doorstep: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                TowerCat(coat: local.tower.visitor?.coat ?? 2).frame(width: 46, height: 50)
                    .opacity(local.tower.visitor == nil ? 0.35 : 1)
                VStack(alignment: .leading, spacing: 5) {
                    Text(local.tower.visitor.map { "\($0.name)在门口等候" } ?? "门前的小路，静悄悄的")
                        .font(.system(size: 15, weight: .bold))
                    Text(local.tower.visitor.map { "\($0.specialty.title)专长 · \($0.skillTitle) · \($0.personality.title)" } ?? "每 10 分钟来访一只，来客会在门口等你。")
                        .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if local.tower.visitor != nil {
                Button {
                    let cat = local.tower.visitor?.name ?? "小猫"
                    local.change { if $0.welcome() { arrivalMessage = "\(cat)已在底层大厅休息，去为它安排楼层吧。" } }
                } label: {
                    Text(local.tower.residents.count >= CatTower.maximumFloors * 3 ? "先扩建，再多留一个位置" : "欢迎住进来")
                        .font(.system(size: 14, weight: .bold)).frame(maxWidth: .infinity).padding(13)
                        .background(Palette.ink, in: PixelFrame()).foregroundStyle(.white)
                }.buttonStyle(.plain).disabled(local.loadFailed || local.tower.residents.count >= CatTower.maximumFloors * 3)
                    .accessibilityIdentifier("tower.welcome")
            }
            if !arrivalMessage.isEmpty { Text(arrivalMessage).font(.caption).accessibilityIdentifier("tower.welcomeMessage") }
        }.padding(20).background(TowerColors.cream).padding(.top, 7)
    }
    private var constructionPanel: some View {
        NavigationStack {
            List {
                Section("余额 \(local.tower.coins) 喵币 · 扩建费 \(local.tower.expansionCost)") {
                    Text("每增加一层，下一层扩建费约增长 35%。设施费另计。第一层餐厅固定保留。")
                        .font(.caption)
                }
                ForEach(CatTower.Industry.allCases, id: \.self) { industry in
                    Section(industry.title + "产业") {
                        ForEach(CatTower.Facility.allCases.filter { $0.industry == industry }, id: \.self) { facility in
                            Button {
                                var built = false
                                local.change { built = $0.expand(facility: facility) }
                                if built { showConstruction = false }
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("\(facility.title) · \(local.tower.expansionCost + facility.fee) 喵币").font(.headline)
                                    Text(facility.recipe).font(.caption)
                                    if let prerequisite = facility.prerequisite {
                                        Text("前置：\(prerequisite.title)").font(.caption2)
                                    }
                                }
                            }.accessibilityIdentifier("tower.build.\(facility.rawValue)")
                            .disabled(!local.tower.canBuild(facility) || local.tower.coins < local.tower.expansionCost + facility.fee || local.tower.floors >= CatTower.maximumFloors)
                        }
                    }
                }
            }.navigationTitle("建造新楼层")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showConstruction = false } } }
        }
    }
    private var warehousePanel: some View {
        NavigationStack {
            List {
                Section("喵币") {
                    Text("余额：\(local.tower.coins)")
                    Button("购买喵币 · 尚未开放") { showPurchaseNotice = true }
                }
                Section("全塔共享仓库") {
                    ForEach(CatTower.Material.allCases, id: \.self) { material in
                        HStack { Text(material.title); Spacer(); Text("\(local.tower.inventory[material, default: 0]) / \(CatTower.storageCapacity)") }
                    }
                }
                Section { Text("每分钟结算生产；原料自动供应。离线最多结算 8 小时，无猫不生产。熟练度来自完成的生产轮次。") .font(.footnote) }
            }.navigationTitle("喵币与仓库")
                .alert("喵币商店尚未开放", isPresented: $showPurchaseNotice) { Button("知道了", role: .cancel) {} } message: { Text("目前可通过经营赚取喵币。充值将在 App Store 商品配置完成后开放。") }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showWarehouse = false } } }
        }
    }
    private var residentsPanel: some View {
        NavigationStack {
            List {
                if local.tower.residents.isEmpty { Text("还没有居民。先去门口认识第一只小猫吧。") }
                ForEach(local.tower.residents) { cat in
                    HStack {
                        TowerCat(coat: cat.coat).frame(width: 38, height: 42)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(cat.name).font(.headline)
                            Text(cat.floor.map { "在第\($0)层工作" } ?? "大厅待岗").font(.caption)
                            Text("\(cat.specialty.title) · \(cat.skillTitle) · \(cat.personality.title)").font(.caption2)
                            Text(cat.personality.detail).font(.caption2).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Menu("安排") {
                            ForEach(1...local.tower.floors, id: \.self) { floor in
                                Button("第\(floor)层 · \(local.tower.facilities[floor]?.title ?? "待建设")") { prepareRide(cat, to: floor) }
                                    .disabled(local.tower.facilities[floor] == nil || cat.floor != floor && local.tower.residents.filter { $0.floor == floor }.count >= CatTower.capacity)
                            }
                            if cat.floor != nil { Button("暂时回到大厅") { prepareRide(cat, to: nil) } }
                            Button("请它离开 · \(CatTower.releaseCost) 喵币", role: .destructive) { departingCat = cat }
                        }.disabled(local.loadFailed)
                    }
                }
                Section { Text("每层一个岗位。专长匹配提高效率，工作积累熟练度；没有猫或原料时暂停。") .font(.footnote) }
            }.navigationTitle("猫塔居民")
        .alert("和\(departingCat?.name ?? "猫猫")告别？", isPresented: Binding(get: { departingCat != nil && showResidents }, set: { if !$0 { departingCat = nil } }), presenting: departingCat) { cat in
            Button("留下它", role: .cancel) { departingCat = nil }
            Button("花 \(CatTower.releaseCost) 喵币请它离开", role: .destructive) { releaseResident(cat) }
                .disabled(local.tower.coins < CatTower.releaseCost || local.loadFailed || liftBusy)
        } message: { _ in
            Text(local.tower.coins < CatTower.releaseCost
                ? "送别需要 \(CatTower.releaseCost) 喵币，当前余额 \(local.tower.coins)，余额不足。"
                : "将花费 \(CatTower.releaseCost) 喵币为它准备路费。离开后无法找回这只猫；如有工作岗位，岗位将空出。")
        }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showResidents = false } } }
        }
    }
    private func assignmentPanel(_ floor: Int) -> some View {
        NavigationStack {
            List {
                Section("第\(floor)层 · \(local.tower.facilities[floor]?.title ?? "待建设")") {
                    Text(local.tower.status(at: floor))
                    if let facility = local.tower.facilities[floor] { Text(facility.recipe).font(.caption) }
                    if floor > 1 {
                        Menu("改装设施 · 40 喵币起") {
                            ForEach(CatTower.Facility.allCases, id: \.self) { facility in
                                Button("\(facility.title) · \(40 + facility.fee) 喵币") {
                                    var changed = false
                                    local.change { changed = $0.remodel(floor, facility: facility) }
                                    arrivalMessage = changed ? "改装完成" : "无法改装：请检查余额和产业前置关系"
                                }.disabled(!local.tower.canBuild(facility) || local.tower.coins < 40 + facility.fee)
                            }
                        }
                        if !arrivalMessage.isEmpty { Text(arrivalMessage).font(.caption) }
                    }
                }
                ForEach(local.tower.residents) { cat in
                    let here = cat.floor == floor
                    Button {
                        prepareRide(cat, to: here ? nil : floor)
                    } label: {
                        HStack {
                            TowerCat(coat: cat.coat).frame(width: 38, height: 40)
                            VStack(alignment: .leading) {
                                Text(cat.name).font(.headline)
                                Text("\(cat.specialty.title) · \(cat.skillTitle) · \(cat.personality.title)").font(.caption2)
                                Text(here ? "已在本层 · 点击回大厅" : cat.floor.map { "从第\($0)层调入" } ?? "从大厅安排到这里").font(.caption)
                            }
                            Spacer()
                            Image(systemName: here ? "checkmark.circle.fill" : "plus.circle")
                        }
                    }.disabled(local.loadFailed || local.tower.facilities[floor] == nil || (!here && local.tower.residents.filter { $0.floor == floor }.count >= CatTower.capacity))
                        .accessibilityIdentifier("tower.assign.\(cat.name)")
                }
                if local.tower.residents.isEmpty { Text("先到门口收留一位小伙伴，再为它安排楼层。") }
                Section("拆除楼层") {
                    if let reason = local.tower.demolitionBlockReason(floor) {
                        Text(reason).font(.caption).foregroundStyle(Palette.muted)
                    } else {
                        Button("拆除顶层 · 返还 \(local.tower.demolitionRefund) 喵币", role: .destructive) { confirmDemolition = true }
                            .disabled(local.loadFailed || liftBusy)
                            .accessibilityIdentifier("tower.demolish")
                        Text("返还该层实际建造费用的 50%，向下取整。改装费不返还；旧存档未记录建造费用的楼层返还 0 喵币。")
                            .font(.caption).foregroundStyle(Palette.muted)
                    }
                }
            }.navigationTitle("安排居民")
                .alert("拆除第\(floor)层？", isPresented: $confirmDemolition) {
                    Button("保留楼层", role: .cancel) {}
                    Button("确认拆除", role: .destructive) {
                        let refund = local.tower.demolitionRefund
                        var removed = false
                        local.change { removed = $0.demolish(floor) }
                        if removed {
                            selectedFloor = nil
                            liftStatus = "顶层已拆除，返还 \(refund) 喵币，猫猫已回大厅"
                        }
                    }
                } message: { Text("将返还 \(local.tower.demolitionRefund) 喵币。楼层无法恢复，需要重新建造；工作人员回到大厅，共享库存保留。") }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { selectedFloor = nil } } }
        }
    }
}

/// This background belongs to the scroll content, so the scenery and building move as one world.
private struct TowerSky: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.blush))
            func block(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
                context.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(color))
            }
            for y in stride(from: CGFloat(0), through: size.height, by: 24) {
                for x in stride(from: CGFloat(0), through: size.width, by: 24) {
                    block(x, y, 2, 2, Palette.line.opacity(0.65))
                }
            }
            for level in 0..<Int(size.height / 240) + 1 {
                let y = CGFloat(level) * 240 + 30
                let x: CGFloat = level % 2 == 0 ? 5 : size.width - 85
                block(x, y + 8, 72, 12, Palette.paper)
                block(x + 12, y, 24, 8, Palette.paper)
                block(x + 33, y + 3, 23, 5, Palette.paper)
                block(size.width - 13, y + 105, 2, 70, Palette.line)
                block(size.width - 20, y + 112, 16, 2, Palette.line)
            }
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}

/// One continuous shaft runs from the topmost room down to the doorstep.
/// It is never instantiated per floor: the stem and lift cannot break at floor boundaries.
private struct TowerVine: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: reduceMotion || AppRuntime.isUITesting || scenePhase != .active)) { time in
            Canvas { context, size in
                func block(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
                    context.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(color))
                }
                let ground = floor(size.height - 16)
                block(1, 0, size.width - 2, size.height, Palette.sage.opacity(0.75))
                block(0, 0, 2, size.height, Palette.line)
                block(size.width - 2, 0, 2, size.height, Palette.line)
                // A single pixel stem with leaves staggered continuously from the ground.
                for y in stride(from: CGFloat(0), through: ground, by: 3) {
                    let x = floor(size.width / 2 + sin(Double(ground - y) * 0.038) * 5)
                    block(x, y, 3, 3, Palette.ink)
                    block(x + 1, y, 1, 3, Palette.coral)
                }
                for step in 0..<max(1, Int(ground / 27)) {
                    let y = ground - CGFloat(step) * 27 - 15
                    let x = floor(size.width / 2 + sin(Double(ground - y) * 0.038) * 5)
                    let left = step % 2 == 0
                    let lx = left ? x - 9 : x + 3
                    block(lx, y, 9, 5, Palette.ink)
                    block(lx + 2, y - 3, 5, 3, Palette.ink)
                    block(lx + 2, y, 5, 2, Palette.coral)
                }
                block(7, 0, 1, ground, Palette.muted)
                block(size.width - 8, 0, 1, ground, Palette.muted)
                block(1, ground, size.width - 2, 3, Palette.ink)
                block(9, ground - 10, 21, 10, Palette.ink)
                block(12, ground - 8, 15, 3, Palette.coral)
            }
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}

private struct TowerLiftCar: View {
    let coat: Int?
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                if let coat { TowerCat(coat: coat).frame(width: 27, height: 26) }
            }.frame(height: 29)
            ZStack {
                Rectangle().fill(Palette.paper)
                VStack(spacing: 5) {
                    Rectangle().fill(Palette.line).frame(height: 2)
                    Rectangle().fill(Palette.line).frame(height: 2)
                }.padding(.horizontal, 2)
                HStack { Spacer(); Rectangle().fill(Palette.line).frame(width: 2); Spacer(); Rectangle().fill(Palette.line).frame(width: 2); Spacer() }
            }.frame(height: 19).overlay(Rectangle().stroke(Palette.ink, lineWidth: 2))
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}

/// Blue/white line art uses the same palette, pixel grid and square corners as RoomBackdrop.
private struct TowerRoomArt: View {
    let home: Bool
    let cats: [Int]
    var master: CompanionSession? = nil
    var variant = 0
    var body: some View {
        GeometryReader { g in
            ZStack {
                Canvas { context, size in
                    let unit = max(1, floor(size.width / 160))
                    let width = floor(size.width / unit)
                    let height = floor(size.height / unit)
                    context.scaleBy(x: unit, y: unit)
                    func block(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
                        context.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(color))
                    }
                    func outline(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ fill: Color = Palette.paper) {
                        block(x, y, w, h, Palette.ink)
                        block(x + 1, y + 1, w - 2, h - 2, fill)
                    }
                    let floorY = floor(height * 0.78)
                    block(0, 0, width, height, Palette.paper)
                    for x in stride(from: CGFloat(7), through: width, by: 16) {
                        for y in stride(from: CGFloat(7), through: floorY, by: 16) { block(x, y, 1, 1, Palette.line) }
                    }
                    block(0, floorY, width, height - floorY, Palette.blush)
                    block(0, floorY, width, 1, Palette.ink)
                    for y in stride(from: floorY + 9, through: height, by: 11) {
                        block(0, y, width, 1, Palette.line)
                        for x in stride(from: CGFloat(Int(y) % 22), through: width, by: 32) { block(x, y - 8, 1, 8, Palette.line) }
                    }
                    // Window: the exact line weight and four-pane treatment used in the home screen.
                    outline(12, 15, 36, 34, Palette.sage)
                    block(29, 16, 1, 32, Palette.ink)
                    block(13, 31, 34, 1, Palette.ink)
                    block(35, 20, 6, 6, Palette.coral)
                    block(10, 49, 40, 2, Palette.ink)
                    // Architectural frame, shelves and tiny collectable objects.
                    block(0, 0, width, 2, Palette.line)
                    block(3, 2, 1, floorY - 2, Palette.line)
                    block(width - 5, 2, 1, floorY - 2, Palette.line)
                    let shelfX = width - 57
                    block(shelfX, 32, 43, 2, Palette.ink)
                    outline(shelfX + 3, 22, 7, 10, Palette.blush)
                    outline(shelfX + 12, 19, 5, 13, Palette.sage)
                    outline(shelfX + 28, 19, 11, 13)
                    block(shelfX + 31, 23, 5, 5, Palette.coral)
                    // Ceiling lamp and trailing blue plant.
                    block(width * 0.51, 2, 1, 8, Palette.ink)
                    outline(width * 0.51 - 5, 10, 12, 5, Palette.sage)
                    block(width * 0.51 - 2, 15, 6, 2, Palette.line)
                    outline(width - 29, floorY - 12, 15, 12, Palette.sage)
                    block(width - 23, floorY - 32, 2, 20, Palette.ink)
                    block(width - 30, floorY - 29, 8, 3, Palette.coral)
                    block(width - 21, floorY - 24, 9, 3, Palette.coral)
                    block(width - 27, floorY - 19, 6, 3, Palette.coral)
                    if home {
                        // Stepped bed, pillow, blanket, bedside table and framed portrait.
                        outline(10, floorY - 18, 39, 18, Palette.sage)
                        block(9, floorY - 25, 2, 27, Palette.ink)
                        outline(13, floorY - 21, 11, 5)
                        block(26, floorY - 15, 20, 1, Palette.line)
                        block(26, floorY - 10, 20, 1, Palette.line)
                        block(26, floorY - 5, 20, 1, Palette.line)
                        block(11, floorY, 2, 5, Palette.ink)
                        block(45, floorY, 2, 5, Palette.ink)
                        outline(55, floorY - 11, 15, 11)
                        block(58, floorY - 8, 9, 1, Palette.line)
                        block(62, floorY - 7, 2, 2, Palette.ink)
                        outline(57, floorY - 22, 10, 11, Palette.blush)
                        block(61, floorY - 19, 2, 5, Palette.coral)
                    } else if variant % 2 == 0 {
                        outline(11, floorY - 12, 30, 12, Palette.sage)
                        block(14, floorY - 8, 24, 1, Palette.line)
                        block(24, floorY - 5, 3, 2, Palette.ink)
                        outline(54, floorY - 10, 13, 10)
                    } else {
                        block(13, floorY - 14, 34, 2, Palette.ink)
                        block(16, floorY - 12, 2, 15, Palette.ink)
                        block(42, floorY - 12, 2, 15, Palette.ink)
                        outline(20, floorY - 20, 12, 6, Palette.sage)
                        outline(54, floorY - 9, 12, 9, Palette.blush)
                    }
                    // Empty middle keeps the pet silhouette readable.
                    outline(width * 0.47, floorY + 5, 30, 8, Palette.paper)
                    block(width * 0.47 + 3, floorY + 8, 24, 1, Palette.line)
                }
                if let master {
                    PixelPet(session: master)
                        .frame(width: 152, height: 90)
                        .position(x: g.size.width * 0.58, y: g.size.height * 0.61)
                }
                ForEach(Array(cats.enumerated()), id: \.offset) { index, coat in
                    TowerCat(coat: coat)
                        .frame(width: 46, height: 46)
                        .position(x: g.size.width * (0.47 + Double(index) * 0.18), y: g.size.height * 0.69)
                }
            }
        }.clipped().accessibilityHidden(true).allowsHitTesting(false)
    }
}

/// Residents reuse the same CPetCore bitmap as the app's PixelPet, rather than a second cat design.
private struct TowerCat: View {
    let coat: Int
    private static let state = FirmwareState()
    var body: some View {
        Canvas { context, size in
            let pixels = Self.state.pixels(animationTime: 0, feedbackAge: 100)
            var points: [(Int, Int)] = []
            for y in 19..<64 {
                for x in 30..<106 where pixels[y / 8 * 128 + x] & (1 << (y % 8)) != 0 {
                    points.append((x, y))
                }
            }
            guard let minX = points.map({ $0.0 }).min(), let maxX = points.map({ $0.0 }).max(),
                  let minY = points.map({ $0.1 }).min(), let maxY = points.map({ $0.1 }).max() else { return }
            let unit = max(1, floor(min(size.width / CGFloat(maxX - minX + 1), size.height / CGFloat(maxY - minY + 1))))
            let left = floor((size.width - CGFloat(maxX - minX + 1) * unit) / 2)
            let top = floor((size.height - CGFloat(maxY - minY + 1) * unit) / 2)
            var path = Path()
            for (x, y) in points {
                path.addRect(CGRect(x: left + CGFloat(x - minX) * unit, y: top + CGFloat(y - minY) * unit, width: unit, height: unit))
            }
            context.fill(path, with: .color(coat % 2 == 0 ? Palette.ink : Palette.coral))
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}

/// All workshops share the app palette and bitmap cats, with function-specific pixel furniture.
private struct TowerFacilityArt: View {
    let facility: CatTower.Facility?
    let cats: [Int]
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: !active || reduceMotion)) { timeline in
            GeometryReader { g in
                let pulse = active && !reduceMotion ? Int(timeline.date.timeIntervalSinceReferenceDate * 2) % 2 : 0
                ZStack {
                    Canvas { context, size in
                        let scale = size.width / 160
                        func block(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: Color = Palette.ink) {
                            context.fill(Path(CGRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale)), with: .color(c))
                        }
                        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: Color = Palette.paper) {
                            block(x, y, w, h); block(x + 1, y + 1, w - 2, h - 2, c)
                        }
                        func bench(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat) {
                            box(x, y, w, 5, Palette.sage); block(x + 2, y + 5, 2, 12); block(x + w - 4, y + 5, 2, 12)
                        }
                        block(0, 0, 160, 110, Palette.paper)
                        block(0, 70, 160, 40, Palette.blush)
                        block(0, 70, 160, 1)
                        for y in stride(from: CGFloat(80), through: 110, by: 10) { block(0, y, 160, 1, Palette.line) }
                        box(65, 8, 30, 23, Palette.sage); block(79, 9, 1, 21); block(66, 19, 28, 1)
                        switch facility {
                        case .garden, .cottonGarden:
                            for x in stride(from: CGFloat(8), through: 110, by: 36) {
                                box(x, 57, 29, 16, Palette.sage)
                                for dx in [CGFloat(6), 19] {
                                    block(x + dx, 42, 2, 17, Palette.coral)
                                    block(x + dx - 4, 46 + CGFloat(pulse), 6, 3, Palette.sage)
                                    block(x + dx + 2, 50, 5, 3, Palette.sage)
                                    if facility == .cottonGarden { box(x + dx - 3, 37, 9, 7) }
                                    else { block(x + dx - 2, 39, 6, 5, Palette.coral) }
                                }
                            }
                            box(130, 60, 20, 14, Palette.blush)
                        case .mill:
                            box(12, 35, 38, 35, Palette.sage); box(18, 23, 26, 13, Palette.blush)
                            box(18, 43, 26, 20); block(29 + CGFloat(pulse * 5), 44, 3, 18)
                            box(57, 56, 16, 17, Palette.paper); box(120, 48, 24, 25, Palette.blush)
                            if active { block(62, 48 + CGFloat(pulse * 3), 2, 2, Palette.line) }
                        case .restaurant:
                            bench(8, 57, 49); box(12, 41, 16, 16, Palette.sage); box(32, 44, 20, 12)
                            if active { block(35, 35 - CGFloat(pulse * 3), 2, 6, Palette.line); block(44, 33 + CGFloat(pulse * 2), 2, 7, Palette.line) }
                            bench(108, 61, 36); box(115, 56, 11, 4); box(131, 55, 8, 5)
                            box(12, 10, 30, 22, Palette.blush); block(17, 16, 20, 2); block(17, 23, 15, 2)
                        case .textile:
                            box(9, 27, 50, 43, Palette.sage)
                            for x in stride(from: CGFloat(15), through: 51, by: 5) { block(x, 32, 1, 30, Palette.line) }
                            block(13, 40 + CGFloat(pulse * 10), 42, 4, Palette.coral)
                            bench(108, 60, 36)
                            for x in [CGFloat(112), 123, 134] { box(x, 46, 7, 14, Palette.blush) }
                        case .clothingShop:
                            block(10, 30, 48, 2); block(12, 30, 2, 43); block(54, 30, 2, 43)
                            for x in [CGFloat(18), 35] {
                                block(x + 5, 32, 1, 5); box(x, 37, 15, 20, Palette.sage)
                                block(x - 3, 39, 4, 7, Palette.coral); block(x + 14, 39, 4, 7, Palette.coral)
                            }
                            bench(111, 58, 35); box(130, 46, 12, 12, Palette.blush)
                            if active { box(114 + CGFloat(pulse * 3), 50, 10, 8) }
                        case .mine:
                            for i in 0..<5 { box(CGFloat(i * 10 + 4), CGFloat(20 + (i % 2) * 10), 17, 42, Palette.sage) }
                            block(6, 76, 145, 2); block(6, 82, 145, 2)
                            for x in stride(from: CGFloat(10), through: 146, by: 12) { block(x, 74, 2, 11) }
                            let x = CGFloat(105 + pulse * 5)
                            box(x, 58, 28, 15, Palette.blush); box(x + 3, 72, 6, 6); box(x + 20, 72, 6, 6)
                            box(x + 5, 51, 9, 8, Palette.sage); box(x + 14, 48, 9, 11)
                        case .smelter:
                            box(12, 24, 42, 48, Palette.sage); box(23, 9, 16, 16, Palette.blush)
                            box(19, 43, 28, 24)
                            if active { block(24, 53 - CGFloat(pulse * 5), 6, 13, Palette.coral); block(33, 49 + CGFloat(pulse * 3), 7, 17, Palette.coral) }
                            bench(109, 59, 38)
                            for x in [CGFloat(113), 129] { box(x, 51, 12, 8, Palette.sage) }
                        case .craftShop:
                            bench(8, 57, 47); box(15, 45, 12, 12, Palette.sage)
                            block(38 + CGFloat(pulse * 3), 40, 3, 14); block(34 + CGFloat(pulse * 3), 38, 11, 4)
                            box(109, 21, 39, 51, Palette.blush)
                            for y in [CGFloat(37), 54] {
                                block(110, y, 37, 2); box(116, y - 11, 8, 11, Palette.sage); box(132, y - 9, 9, 9)
                            }
                        case nil:
                            box(16, 50, 25, 23, Palette.blush); box(22, 43, 25, 8)
                            block(29, 51, 1, 20); box(117, 54, 26, 19, Palette.sage)
                        }
                    }
                    ForEach(Array(cats.enumerated()), id: \.offset) { index, coat in
                        TowerCat(coat: coat).frame(width: 46, height: 46)
                            .offset(y: active && !reduceMotion ? CGFloat(pulse * -2) : 0)
                            .position(x: g.size.width * (0.52 + Double(index) * 0.15), y: g.size.height * 0.68)
                    }
                }
            }
        }.clipped().accessibilityHidden(true).allowsHitTesting(false)
    }
}
