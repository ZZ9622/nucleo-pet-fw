import Foundation

/// Self-contained tower economy; amounts are deliberately independent of the adventure wallet.
public struct CatTower: Codable, Equatable {
    public enum Industry: String, Codable, CaseIterable {
        case food, clothing, craft
        public var title: String { switch self { case .food: return "餐饮"; case .clothing: return "服装"; case .craft: return "工艺" } }
    }
    public enum Material: String, Codable, CaseIterable {
        case crops, flour, cotton, cloth, ore, metal
        public var title: String { switch self { case .crops: return "作物"; case .flour: return "面粉"; case .cotton: return "棉花"; case .cloth: return "布料"; case .ore: return "矿石"; case .metal: return "金属" } }
    }
    public enum Facility: String, Codable, CaseIterable {
        case restaurant, garden, mill, cottonGarden, textile, clothingShop, mine, smelter, craftShop
        public var title: String {
            switch self {
            case .restaurant: return "餐厅"; case .garden: return "种植园"; case .mill: return "磨坊"
            case .cottonGarden: return "棉花园"; case .textile: return "纺织店"; case .clothingShop: return "服装店"
            case .mine: return "矿场"; case .smelter: return "冶炼坊"; case .craftShop: return "工艺店"
            }
        }
        public var industry: Industry {
            switch self { case .restaurant, .garden, .mill: return .food; case .cottonGarden, .textile, .clothingShop: return .clothing; default: return .craft }
        }
        public var prerequisite: Facility? {
            switch self { case .mill: return .garden; case .textile: return .cottonGarden; case .clothingShop: return .textile; case .smelter: return .mine; case .craftShop: return .smelter; default: return nil }
        }
        public var input: Material? {
            switch self { case .restaurant, .mill: return .crops; case .textile: return .cotton; case .clothingShop: return .cloth; case .smelter: return .ore; case .craftShop: return .metal; default: return nil }
        }
        public var output: Material? {
            switch self { case .garden: return .crops; case .mill: return .flour; case .cottonGarden: return .cotton; case .textile: return .cloth; case .mine: return .ore; case .smelter: return .metal; default: return nil }
        }
        public var fee: Int { prerequisite == nil ? 0 : (output == nil ? 80 : 40) }
        public var recipe: String {
            if self == .restaurant { return "1 作物 → 8 喵币 / 1 面粉 → 16 喵币" }
            return "\(input.map { "1 " + $0.title } ?? "自动采集") → \(output.map { "2 " + $0.title } ?? "24 喵币")"
        }
    }
    public enum Merchant: String, Codable {
        case regular, mint

        // Saturday 08:00 UTC every week; mint merchant every second Wednesday at 16:00 UTC.
        public var startOffset: Int { self == .regular ? 0 : 4 * 86400 + 8 * 3600 }
        public var duration: Int { self == .regular ? 43200 : 1800 }
        public var period: Int { self == .regular ? 604800 : 1209600 }
        public var title: String { self == .regular ? "流浪商人" : "喵星薄荷商人" }
        public var stock: [(kind: String, price: Int)] {
            self == .regular ? [("recordPlayer", 480), ("shellLamp", 360)] : [("starWindow", 1400), ("nebulaCushion", 1800)]
        }
        public func lastArrival(at date: Date) -> Int {
            let anchor = 1763193600 + startOffset
            let epoch = Int(date.timeIntervalSince1970)
            return anchor + Int(floor(Double(epoch - anchor) / Double(period))) * period
        }
    }

    public struct InventoryAction: Codable, Equatable {
        public enum Kind: String, Codable { case build, sell, buy, swap }
        public let requestID: String
        public let owner: String
        public let kind: Kind
        public let itemIDs: [String]
        public let product: String?
        public let facility: Facility?
        public let merchant: Merchant?
        public let arrival: Int?
        public let coins: Int

        public init(owner: String, kind: Kind, itemIDs: [String] = [], product: String? = nil,
                    facility: Facility? = nil, merchant: Merchant? = nil, arrival: Int? = nil, coins: Int = 0) {
            requestID = UUID().uuidString
            self.owner = owner
            self.kind = kind
            self.itemIDs = itemIDs
            self.product = product
            self.facility = facility
            self.merchant = merchant
            self.arrival = arrival
            self.coins = coins
        }
    }

    public enum Personality: String, Codable, CaseIterable {
        case diligent, careful, social
        public var title: String { switch self { case .diligent: return "勤快"; case .careful: return "细心"; case .social: return "合群" } }
        public var detail: String { switch self { case .diligent: return "生产速度 +10%"; case .careful: return "每十轮额外产出一次"; case .social: return "同产业另有猫工作时速度 +10%" } }
    }
    public struct Resident: Codable, Identifiable, Equatable {
        public let id: UUID
        public let name: String
        public let coat: Int
        public var floor: Int?
        public var specialty: Industry = .food
        public var personality: Personality = .diligent
        public var experience: Int = 0
        public var skillTitle: String { experience >= 300 ? "精通" : experience >= 60 ? "熟练" : "生疏" }
        public init(id: UUID = UUID(), name: String, coat: Int, floor: Int? = nil, specialty: Industry = .food, personality: Personality = .diligent, experience: Int = 0) {
            self.id = id; self.name = name; self.coat = coat; self.floor = floor
            self.specialty = specialty; self.personality = personality; self.experience = experience
        }
        private enum CodingKeys: String, CodingKey { case id, name, coat, floor, specialty, personality, experience }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
            coat = try c.decode(Int.self, forKey: .coat); floor = try c.decodeIfPresent(Int.self, forKey: .floor)
            specialty = try c.decodeIfPresent(Industry.self, forKey: .specialty) ?? .food
            personality = try c.decodeIfPresent(Personality.self, forKey: .personality) ?? .diligent
            experience = try c.decodeIfPresent(Int.self, forKey: .experience) ?? 0
        }
    }
    public private(set) var floors = 1
    public private(set) var residents: [Resident] = []
    public private(set) var visitor: Resident?
    public private(set) var nextVisit: Date
    public private(set) var coins = 100
    public private(set) var facilities: [Int: Facility] = [1: .restaurant]
    public private(set) var inventory: [Material: Int] = [.crops: 20]
    private var progress: [Int: Double] = [:] // Legacy floor progress, migrated when loading.
    private var workerProgress: [UUID: Double] = [:]
    private var constructionCosts: [Int: Int] = [:]
    private var lastProduction: Date
    private var arrivals = 0
    public private(set) var pendingInventoryAction: InventoryAction?
    public private(set) var pomiLocation: Int?
    private var lastPomiReturn: UInt64?
    private var nextPomiWalk: Date?
    public private(set) var merchantTrackingSince = Date()
    public private(set) var merchantSeen: [Merchant: Int] = [:]
    public private(set) var merchantTrades: [Merchant: Int] = [:]
    public private(set) var purchasedStock: [String: Int] = [:]

    public var unfinishedFloor: Int? { (2...max(2, floors)).first { $0 <= floors && facilities[$0] == nil } }
    public mutating func seeMerchant(_ merchant: Merchant, arrival: Int) {
        merchantSeen[merchant] = arrival
    }

    public var unlockedPomiLocations: [Int] { [-1, 0] + facilities.keys.sorted() }

    public func requiredItem(for facility: Facility, floor: Int) -> String? {
        switch facility {
        case .garden: floor == 2 ? nil : "wheatSeed"
        case .cottonGarden: "cottonSeed"
        case .mine: "oreSample"
        default: nil
        }
    }

    @discardableResult public mutating func unlockFloor(now: Date = Date()) -> Bool {
        refresh(now: now)
        let cost = expansionCost
        guard pendingInventoryAction == nil, unfinishedFloor == nil,
              floors < Self.maximumFloors, coins >= cost else { return false }
        coins -= cost
        floors += 1
        constructionCosts[floors] = cost
        return true
    }

    @discardableResult public mutating func finishFloor(_ facility: Facility) -> Bool {
        guard let floor = unfinishedFloor, requiredItem(for: facility, floor: floor) == nil,
              pendingInventoryAction == nil else { return false }
        return finishFloor(facility, at: floor)
    }

    private mutating func finishFloor(_ facility: Facility, at floor: Int) -> Bool {
        guard canBuild(facility), coins >= facility.fee else { return false }
        coins -= facility.fee
        constructionCosts[floor, default: 0] += facility.fee
        facilities[floor] = facility
        return true
    }

    @discardableResult public mutating func prepareInventoryAction(_ action: InventoryAction) -> Bool {
        guard pendingInventoryAction == nil else { return false }
        if action.kind == .build {
            guard let floor = unfinishedFloor, let facility = action.facility,
                  action.itemIDs.count == 1, requiredItem(for: facility, floor: floor) != nil,
                  canBuild(facility), coins >= facility.fee else { return false }
        }
        if action.kind == .buy {
            guard action.coins > 0, coins >= action.coins else { return false }
            coins -= action.coins
        }
        pendingInventoryAction = action
        return true
    }

    public mutating func rejectInventoryAction(_ id: String) {
        guard let action = pendingInventoryAction, action.requestID == id else { return }
        if action.kind == .buy { coins += action.coins }
        pendingInventoryAction = nil
    }

    public mutating func completeInventoryAction(_ id: String) {
        guard let action = pendingInventoryAction, action.requestID == id else { return }
        if action.kind == .build, let facility = action.facility, let floor = unfinishedFloor {
            guard finishFloor(facility, at: floor) else { return }
        }
        if action.kind == .sell { coins += action.coins }
        if let merchant = action.merchant, let arrival = action.arrival {
            merchantTrades[merchant] = arrival
            if action.kind == .buy, let product = action.product { purchasedStock[product] = arrival }
        }
        pendingInventoryAction = nil
    }

    public mutating func updatePomi(residence: Residence, revision: UInt64, now: Date = Date()) {
        guard residence == .phone else { return }
        if lastPomiReturn != revision || !unlockedPomiLocations.contains(pomiLocation ?? Int.min) {
            lastPomiReturn = revision
            pomiLocation = unlockedPomiLocations.randomElement()
            nextPomiWalk = now.addingTimeInterval(75)
        } else if now >= nextPomiWalk ?? .distantPast {
            pomiLocation = unlockedPomiLocations.filter { $0 != pomiLocation }.randomElement()
            nextPomiWalk = now.addingTimeInterval(75)
        }
    }

    public var lobbyResidents: [Resident] { residents.filter { $0.floor == nil } }
    public static let visitInterval: TimeInterval = 10 * 60
    /// A uniform integer in 0..<100 yields exactly 70/25/5 initial skill weights.
    public static func initialExperience(skillRoll: Int) -> Int {
        precondition((0..<100).contains(skillRoll))
        return skillRoll < 70 ? 0 : skillRoll < 95 ? 60 : 300
    }
    public static let capacity = 3
    public static let maximumFloors = 12
    public static let storageCapacity = 200
    public var expansionCost: Int { Int((100 * pow(1.35, Double(floors - 1))).rounded()) }
    public init(now: Date = Date()) {
        residents = [Resident(name: "麦麦", coat: 0, floor: 1)]
        visitor = Resident(name: "芝麻", coat: 1, experience: Self.initialExperience(skillRoll: Int.random(in: 0..<100)))
        nextVisit = now; lastProduction = now; merchantTrackingSince = now
    }
    public func canBuild(_ facility: Facility) -> Bool {
        facility.prerequisite.map { facilities.values.contains($0) } ?? true
    }
    public func status(at floor: Int) -> String {
        guard let facility = facilities[floor] else { return "空楼层 · 请选择设施" }
        let cats = residents.filter { $0.floor == floor }
        guard !cats.isEmpty else { return "等待安排猫猫" }
        let batchSize = cats.map { cat in
            2 + (cat.personality == .careful && (cat.experience + 1) % 10 == 0 ? 1 : 0)
        }.min() ?? 2
        if let output = facility.output, inventory[output, default: 0] + batchSize > Self.storageCapacity { return "仓库已满" }
        if facility == .restaurant, inventory[.flour, default: 0] > 0 { return "正在制作面粉餐点" }
        if let input = facility.input, inventory[input, default: 0] == 0 { return "等待" + input.title }
        return "正在生产"
    }
    public mutating func refresh(now: Date = Date()) {
        // Fixed simulation steps preserve supply ordering and make reopening equivalent to staying online.
        let elapsed = max(0, Int(now.timeIntervalSince(lastProduction) / 60))
        let ticks = min(480, elapsed)
        if ticks > 0 {
            for _ in 0..<ticks { produceMinute() }
            lastProduction = lastProduction.addingTimeInterval(Double(ticks) * 60)
            if elapsed > 480 { lastProduction = now }
        }
        guard visitor == nil, now >= nextVisit else { return }
        let names = ["芝麻", "奶糖", "栗子", "小雨", "豆包", "麦麦", "云朵", "橘子"]
        visitor = Resident(name: names.randomElement()!, coat: Int.random(in: 0..<4), specialty: Industry.allCases.randomElement()!, personality: Personality.allCases.randomElement()!, experience: Self.initialExperience(skillRoll: Int.random(in: 0..<100)))
    }
    private mutating func produceMinute() {
        // Sales and processing first: newly produced materials are available the following minute.
        for floor in facilities.keys.sorted(by: { (facilities[$0]!.output == nil ? 0 : 1, $0) < (facilities[$1]!.output == nil ? 0 : 1, $1) }) {
            guard let f = facilities[floor] else { continue }
            for catIndex in residents.indices.filter({ residents[$0].floor == floor }) {
                let cat = residents[catIndex]
                var rate = cat.specialty == f.industry ? (cat.experience >= 300 ? 1.4 : cat.experience >= 60 ? 1.25 : 1.1) : 1
                if cat.personality == .diligent { rate += 0.1 }
                if cat.personality == .social && residents.contains(where: { $0.id != cat.id && $0.floor.flatMap { facilities[$0]?.industry } == f.industry }) { rate += 0.1 }
                // Keep at most one ready batch while blocked; no work accumulates without supplies.
                workerProgress[cat.id] = min(2, workerProgress[cat.id, default: 0] + rate)
                while workerProgress[cat.id, default: 0] >= 1 {
                    let input: Material? = f == .restaurant && inventory[.flour, default: 0] > 0 ? .flour : f.input
                    let bonus = cat.personality == .careful && (residents[catIndex].experience + 1) % 10 == 0 ? 1 : 0
                    if let input, inventory[input, default: 0] < 1 { workerProgress[cat.id] = min(1, workerProgress[cat.id, default: 0]); break }
                    if let output = f.output, inventory[output, default: 0] + 2 + bonus > Self.storageCapacity { workerProgress[cat.id] = min(1, workerProgress[cat.id, default: 0]); break }
                    if let input { inventory[input, default: 0] -= 1 }
                    if let output = f.output { inventory[output, default: 0] += 2 + bonus }
                    else { coins += (f == .restaurant ? (input == .flour ? 16 : 8) : 24) * (1 + bonus) }
                    residents[catIndex].experience += 1
                    workerProgress[cat.id, default: 0] -= 1
                }
            }
        }
    }
    @discardableResult public mutating func welcome(now: Date = Date()) -> Bool {
        refresh(now: now)
        guard var cat = visitor, residents.count < Self.maximumFloors * 3 else { return false }
        cat.floor = nil; residents.append(cat); visitor = nil; arrivals += 1
        nextVisit = now.addingTimeInterval(Self.visitInterval)
        return true
    }
    @discardableResult public mutating func assign(_ id: UUID, to floor: Int, now: Date = Date()) -> Bool {
        refresh(now: now)
        guard facilities[floor] != nil, let index = residents.firstIndex(where: { $0.id == id }),
              residents.filter({ $0.floor == floor && $0.id != id }).count < Self.capacity else { return false }
        if residents[index].floor == floor { return true }
        residents[index].floor = floor; workerProgress.removeValue(forKey: id)
        return true
    }
    public mutating func unassign(_ id: UUID, now: Date = Date()) {
        refresh(now: now)
        guard let index = residents.firstIndex(where: { $0.id == id }) else { return }
        workerProgress.removeValue(forKey: id)
        residents[index].floor = nil
    }
    @discardableResult public mutating func expand(facility: Facility = .garden, now: Date = Date()) -> Bool {
        refresh(now: now)
        let cost = expansionCost + facility.fee
        guard pendingInventoryAction == nil, unfinishedFloor == nil, floors < Self.maximumFloors, canBuild(facility), coins >= cost else { return false }
        coins -= cost; floors += 1; facilities[floors] = facility; constructionCosts[floors] = cost
        return true
    }
    @discardableResult public mutating func remodel(_ floor: Int, facility: Facility, now: Date = Date()) -> Bool {
        refresh(now: now)
        guard pendingInventoryAction == nil, floor > 1, floor <= floors, facilities[floor] != facility, canBuild(facility), coins >= 40 + facility.fee else { return false }
        // A prerequisite may not be removed while a dependent building still uses it.
        if let old = facilities[floor], facilities.values.contains(where: { $0.prerequisite == old }), facilities.values.filter({ $0 == old }).count == 1 { return false }
        coins -= 40 + facility.fee; facilities[floor] = facility
        for cat in residents where cat.floor == floor { workerProgress.removeValue(forKey: cat.id) }
        return true
    }
    public static let releaseCost = 5
    /// Leaving removes this individual permanently; future visitors are independent cats.
    @discardableResult public mutating func release(_ id: UUID, now: Date = Date()) -> Bool {
        guard let index = residents.firstIndex(where: { $0.id == id }) else { return false }
        refresh(now: now)
        guard coins >= Self.releaseCost else { return false }
        coins -= Self.releaseCost
        workerProgress.removeValue(forKey: id)
        residents.remove(at: index)
        return true
    }
    public var demolitionRefund: Int { constructionCosts[floors, default: 0] / 2 }
    public func demolitionBlockReason(_ floor: Int) -> String? {
        guard pendingInventoryAction == nil else { return "请先确认待处理的仓库交易" }
        guard floor > 1 else { return "第一层赠送餐厅不能拆除" }
        guard floor == floors else { return "只能从最高层开始拆除" }
        if let old = facilities[floor],
           facilities.contains(where: { $0.key != floor && $0.value.prerequisite == old }),
           !facilities.contains(where: { $0.key != floor && $0.value == old }) {
            return "其他楼层仍依赖这里，请先改装或拆除依赖它的设施"
        }
        return nil
    }
    @discardableResult public mutating func demolish(_ floor: Int, now: Date = Date()) -> Bool {
        guard demolitionBlockReason(floor) == nil else { return false }
        refresh(now: now)
        coins += demolitionRefund
        for index in residents.indices where residents[index].floor == floor {
            workerProgress.removeValue(forKey: residents[index].id)
            residents[index].floor = nil
        }
        facilities.removeValue(forKey: floor)
        progress.removeValue(forKey: floor)
        constructionCosts.removeValue(forKey: floor)
        floors -= 1
        return true
    }
    private enum CodingKeys: String, CodingKey { case floors, residents, visitor, nextVisit, arrivals, coins, facilities, inventory, progress, lastProduction, constructionCosts, workerProgress, pendingInventoryAction, pomiLocation, lastPomiReturn, nextPomiWalk, merchantTrackingSince, merchantSeen, merchantTrades, purchasedStock }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        floors = try c.decode(Int.self, forKey: .floors)
        residents = try c.decode([Resident].self, forKey: .residents)
        visitor = try c.decodeIfPresent(Resident.self, forKey: .visitor)
        nextVisit = try c.decode(Date.self, forKey: .nextVisit)
        arrivals = try c.decodeIfPresent(Int.self, forKey: .arrivals) ?? 0
        coins = try c.decodeIfPresent(Int.self, forKey: .coins) ?? 100
        facilities = try c.decodeIfPresent([Int: Facility].self, forKey: .facilities) ?? [1: .restaurant]
        inventory = try c.decodeIfPresent([Material: Int].self, forKey: .inventory) ?? [.crops: 20]
        progress = try c.decodeIfPresent([Int: Double].self, forKey: .progress) ?? [:]
        lastProduction = try c.decodeIfPresent(Date.self, forKey: .lastProduction) ?? Date()
        constructionCosts = try c.decodeIfPresent([Int: Int].self, forKey: .constructionCosts) ?? [:]
        pendingInventoryAction = try c.decodeIfPresent(InventoryAction.self, forKey: .pendingInventoryAction)
        pomiLocation = try c.decodeIfPresent(Int.self, forKey: .pomiLocation)
        lastPomiReturn = try c.decodeIfPresent(UInt64.self, forKey: .lastPomiReturn)
        nextPomiWalk = try c.decodeIfPresent(Date.self, forKey: .nextPomiWalk)
        merchantTrackingSince = try c.decodeIfPresent(Date.self, forKey: .merchantTrackingSince) ?? Date()
        merchantSeen = try c.decodeIfPresent([Merchant: Int].self, forKey: .merchantSeen) ?? [:]
        merchantTrades = try c.decodeIfPresent([Merchant: Int].self, forKey: .merchantTrades) ?? [:]
        purchasedStock = try c.decodeIfPresent([String: Int].self, forKey: .purchasedStock) ?? [:]
        // Preserve old cats and floors, moving excess occupants into the lobby.
        var occupied: [Int: Int] = [:]
        for i in residents.indices {
            if let floor = residents[i].floor {
                if facilities[floor] == nil || occupied[floor, default: 0] >= Self.capacity { residents[i].floor = nil }
                else { occupied[floor, default: 0] += 1 }
            }
        }
        if let saved = try c.decodeIfPresent([UUID: Double].self, forKey: .workerProgress) {
            let workingIDs = Set(residents.filter { $0.floor != nil }.map(\.id))
            workerProgress = saved.filter { workingIDs.contains($0.key) }
        } else {
            // Credit each legacy floor's partial batch only once, to its first worker.
            for (floor, value) in progress {
                if let cat = residents.first(where: { $0.floor == floor }) { workerProgress[cat.id] = value }
            }
        }
        progress.removeAll()
    }
}
