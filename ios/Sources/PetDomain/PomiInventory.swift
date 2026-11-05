import Foundation

public struct PomiItem: Codable, Identifiable, Equatable {
    public var id: String
    public var kind: String
    public var level: Int
    public init(id: String = UUID().uuidString, kind: String, level: Int = 1) { self.id=id;self.kind=kind;self.level=level }
}
public struct PomiCatalogEntry: Codable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var category: String
    public var symbol: String
    public var slot: String?
    public static let initial: [Self] = [
        .init(id:"berry",name:"蓝莓点心",category:"food",symbol:"carrot",slot:nil),
        .init(id:"cushion",name:"云朵坐垫",category:"decor",symbol:"square.fill",slot:"floor"),
        .init(id:"plant",name:"窗边小草",category:"decor",symbol:"leaf.fill",slot:"corner"),
        .init(id:"picture",name:"海边挂画",category:"decor",symbol:"photo",slot:"wall"),
        .init(id:"shell",name:"散步贝壳",category:"souvenir",symbol:"sparkles",slot:"table")]
}
public struct PomiMoment: Codable, Identifiable, Equatable {
    public var id: String
    public var text: String
    public var date: Double
}
public struct PomiOperation: Codable, Equatable {
    public var id: String
    public var kind: String
    public var boxID: String?
    public var itemID: String?
    public var petID: String
    public var reward: PomiItem?
    public var level: Int
    public init(id:String,kind:String,boxID:String?,itemID:String?,petID:String,reward:PomiItem?,level:Int) {
        self.id=id;self.kind=kind;self.boxID=boxID;self.itemID=itemID;self.petID=petID;self.reward=reward;self.level=level
    }
}
public struct PomiInventory: Codable, Equatable {
    public var catalog = PomiCatalogEntry.initial
    public var boxes: [String] = []
    public var items: [PomiItem] = []
    public var room: [String:String] = [:]
    public var log: [PomiMoment] = []
    public var pending: PomiOperation?
    public var chances = 3
    public var nextChanceAt: Double = 0
    public var preferences: [String:Int] = [:]
    public init() {}
    public func entry(_ item: PomiItem) -> PomiCatalogEntry { catalog.first { $0.id==item.kind } ?? catalog[0] }
    public mutating func note(_ text: String, now: Date = Date()) {
        log.insert(.init(id:UUID().uuidString,text:text,date:now.timeIntervalSince1970),at:0)
        log=Array(log.prefix(100))
    }
    public mutating func merge(_ id: String) throws {
        guard let item=items.first(where:{$0.id==id}),item.level==1 else { throw PhysicalError.message("首版最高为 Lv2") }
        let matches=items.filter { $0.kind==item.kind && $0.level==1 && !room.values.contains($0.id) && pending?.itemID != $0.id }
        guard matches.count>=3 else { throw PhysicalError.message("需要三个相同的闲置 Lv1 物品") }
        let ids=Set(matches.prefix(3).map(\.id));items.removeAll { ids.contains($0.id) };items.append(.init(kind:item.kind,level:2))
        note("三个小收藏合成了 Lv2")
    }
    public mutating func decorate(_ id: String?, slot: String) throws {
        guard ["floor","corner","wall","table"].contains(slot) else { throw CompanionError.invalidState }
        if let id {
            guard let item=items.first(where:{$0.id==id}),entry(item).slot==slot,pending?.itemID != id else { throw CompanionError.invalidState }
            room[slot]=id
        } else { room.removeValue(forKey:slot) }
        note("为小屋换了一点风景")
    }
    public static func preview() -> Self {
        var s=Self();s.boxes=[UUID().uuidString,UUID().uuidString]
        s.items=[.init(kind:"berry"),.init(kind:"plant"),.init(kind:"cushion"),.init(kind:"picture"),.init(kind:"shell")]
        s.note("欢迎来到预览小屋，物品与真实仓库独立")
        return s
    }
}
