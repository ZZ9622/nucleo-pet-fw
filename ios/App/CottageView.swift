import SwiftUI
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
    private let columns=[GridItem(.adaptive(minimum:86),spacing:10)]
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                PageHeader(eyebrow:"Pomi / LITTLE COLLECTIONS",title:"把日子装进小屋",subtitle:"出门遇见惊喜，回家留下一点风景。")
                if world.preview { Text("独立预览 · 模拟物品与放生海").font(.caption.bold()).padding(10).background(Palette.blush) }
                room
                Picker("小屋内容",selection:$section) {
                    Text("仓库").tag(0);Text("放生海").tag(1)
                }.pickerStyle(.segmented).accessibilityIdentifier("cottage.section")
                if section==0 { warehouse } else { sea }
                if !world.message.isEmpty { Text(world.message).font(.footnote).foregroundStyle(Palette.muted).accessibilityIdentifier("world.message") }
                if !world.preview {
                    Button("同步真实仓库") { Task { await world.connect() } }.buttonStyle(QuietButtonStyle()).disabled(world.busy)
                    Button("小屋服务设置") { showService.toggle() }.buttonStyle(QuietButtonStyle())
                    if showService {
                        TextField("https://你的服务地址",text:$world.serviceURL).textFieldStyle(.roundedBorder).autocorrectionDisabled()
                        Text("身份保存在本机钥匙串。换手机前请先保留身份；当前版本尚无账号找回功能。").font(.caption).foregroundStyle(Palette.muted)
                        Button("连接并同步仓库") { Task { await world.connect() } }.buttonStyle(FilledButtonStyle()).disabled(world.busy)
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
        .sheet(item:$selected) { item in itemSheet(item) }

    }
    private var room: some View {
        VStack(spacing:0) {
            HStack { Text("\(store.session.name)的小屋").font(.headline);Spacer();Image(systemName:"square.grid.3x3.fill") }.padding(16)
            ZStack {
                Rectangle().fill(Palette.room)
                PixelGrid()
                VStack(spacing:24) {
                    HStack { slot("wall","墙面");Spacer();slot("corner","角落") }
                    Rectangle().fill(Palette.line).frame(height:2)
                    HStack { slot("floor","地面");Spacer();slot("table","桌面") }
                }.padding(22)
            }.frame(height:225)
            Text(world.inventory.room.isEmpty ? "毛坯房也很可爱。从仓库挑一件物品摆上吧。" : "长按摆放位置，可以将装饰收回仓库。")
                .font(.caption).foregroundStyle(Palette.muted).padding(14)
        }.background(Palette.paper,in:PixelFrame()).overlay(PixelFrame().stroke(Palette.ink,lineWidth:2))
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
        return VStack(alignment:.leading,spacing:20) {
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
            if releasing?.id==item.id {
                Text("放生后无法撤回，它会成为别人的惊喜。").font(.caption)
                HStack {
                    Button("确认放生") { act("/release",["itemID":item.id]);releasing=nil;selected=nil }.buttonStyle(FilledButtonStyle())
                    Button("取消") { releasing=nil }.buttonStyle(QuietButtonStyle())
                }
            } else {
                Button("放入漂流瓶") { releasing=item }.buttonStyle(QuietButtonStyle()).accessibilityIdentifier("world.release").disabled(placed || world.inventory.pending?.itemID==item.id)
            }
            Button("返回") { selected=nil }.buttonStyle(.plain)
        }.padding(28).foregroundStyle(Palette.ink).presentationDetents([.large])

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
