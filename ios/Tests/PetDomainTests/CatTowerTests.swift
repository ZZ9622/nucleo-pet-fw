import XCTest
@testable import PetDomain

final class CatTowerTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_000)
    func testStarterRestaurantAndPaidExpansion() throws {
        var tower = CatTower(now: start)
        XCTAssertEqual(tower.facilities[1], .restaurant)
        XCTAssertEqual(tower.residents.first?.floor, 1)
        XCTAssertEqual(tower.expansionCost, 100)
        XCTAssertFalse(tower.expand(facility: .clothingShop, now: start))
        XCTAssertTrue(tower.expand(facility: .garden, now: start))
        XCTAssertEqual(tower.coins, 0)
        XCTAssertEqual(tower.expansionCost, 135)
        XCTAssertFalse(tower.expand(now: start))
        XCTAssertEqual(tower.floors, 2)
    }
    func testWelcomeLobbyCapacityAndLiftDestinationPersistence() throws {
        var tower = CatTower(now: start)
        XCTAssertTrue(tower.expand(now: start))
        XCTAssertTrue(tower.welcome(now: start))
        XCTAssertFalse(tower.welcome(now: start))
        let cat = try XCTUnwrap(tower.lobbyResidents.first)
        XCTAssertFalse(tower.assign(cat.id, to: 0, now: start))
        XCTAssertTrue(tower.assign(cat.id, to: 2, now: start))
        var restored = try JSONDecoder().decode(CatTower.self, from: JSONEncoder().encode(tower))
        XCTAssertEqual(restored, tower)
        restored.unassign(cat.id, now: start)
        XCTAssertEqual(restored.lobbyResidents.map(\.id), [cat.id])
        restored.refresh(now: start.addingTimeInterval(600))
        XCTAssertNotNil(restored.visitor)
    }
    func testNoWorkerNoOutputAndSupplyFeedsRestaurant() throws {
        var tower = CatTower(now: start)
        XCTAssertTrue(tower.expand(now: start))
        tower.refresh(now: start.addingTimeInterval(60))
        XCTAssertEqual(tower.inventory[.crops], 19)
        XCTAssertEqual(tower.coins, 8)
        XCTAssertEqual(tower.status(at: 2), "等待安排猫猫")
        XCTAssertTrue(tower.welcome(now: start.addingTimeInterval(60)))
        let worker = try XCTUnwrap(tower.lobbyResidents.first)
        XCTAssertTrue(tower.assign(worker.id, to: 2, now: start.addingTimeInterval(60)))
        tower.refresh(now: start.addingTimeInterval(120))
        XCTAssertEqual(tower.inventory[.crops], 20)
        tower.unassign(worker.id, now: start.addingTimeInterval(120))
        tower.refresh(now: start.addingTimeInterval(180))
        XCTAssertEqual(tower.inventory[.crops], 19)
    }
    func testProductionStopsWithoutIngredients() {
        var tower = CatTower(now: start)
        tower.refresh(now: start.addingTimeInterval(3600))
        XCTAssertEqual(tower.coins, 260)
        XCTAssertEqual(tower.inventory[.crops], 0)
        XCTAssertEqual(tower.status(at: 1), "等待作物")
        tower.refresh(now: start.addingTimeInterval(7200))
        XCTAssertEqual(tower.coins, 260)
    }
    func testClothIsRequiredAndConsumedByClothingShop() throws {
        var tower = try fixture(facilities: [1: .restaurant, 2: .cottonGarden, 3: .textile, 4: .clothingShop], inventory: [.cotton: 1])
        XCTAssertTrue(tower.welcome(now: start))
        let worker = try XCTUnwrap(tower.lobbyResidents.first)
        XCTAssertTrue(tower.assign(worker.id, to: 3, now: start))
        tower.refresh(now: start.addingTimeInterval(60))
        XCTAssertEqual(tower.inventory[.cotton], 0)
        XCTAssertEqual(tower.inventory[.cloth], 2)
        XCTAssertTrue(tower.assign(worker.id, to: 4, now: start.addingTimeInterval(60)))
        tower.refresh(now: start.addingTimeInterval(120))
        XCTAssertEqual(tower.inventory[.cloth], 1)
        XCTAssertEqual(tower.coins, 124)
    }
    func testOfflineCapCannotBeClaimedTwice() throws {
        var tower = try fixture(facilities: [1: .restaurant], inventory: [.flour: 10000])
        var eightHours = tower
        eightHours.refresh(now: start.addingTimeInterval(8 * 3600))
        let now = start.addingTimeInterval(24 * 3600)
        tower.refresh(now: now)
        XCTAssertEqual(tower.coins, eightHours.coins)
        XCTAssertEqual(tower.inventory, eightHours.inventory)
        XCTAssertEqual(tower.residents, eightHours.residents)
        let settled = tower
        tower.refresh(now: now)
        XCTAssertEqual(tower, settled)
    }
    func testLegacySaveKeepsUpToThreeCatsPerFloor() throws {
        let ids = [UUID(), UUID()]
        let old: [String: Any] = ["floors": 2, "residents": ids.map { ["id": $0.uuidString, "name": "旧居民", "coat": 0, "floor": 1] }, "nextVisit": 0, "arrivals": 2]
        let tower = try JSONDecoder().decode(CatTower.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertEqual(tower.residents.map(\.id), ids)
        XCTAssertEqual(tower.lobbyResidents.count, 0)
        XCTAssertEqual(tower.facilities[1], .restaurant)
        XCTAssertNil(tower.facilities[2])
    }
    func testCannotRemoveOnlySupplierAndWarehouseDoesNotOverflow() throws {
        var tower = try fixture(facilities: [1: .restaurant, 2: .cottonGarden, 3: .textile], inventory: [.cotton: 199])
        XCTAssertFalse(tower.remodel(2, facility: .mine, now: start))
        XCTAssertTrue(tower.welcome(now: start))
        let worker = try XCTUnwrap(tower.lobbyResidents.first)
        XCTAssertTrue(tower.assign(worker.id, to: 2, now: start))
        tower.refresh(now: start.addingTimeInterval(600))
        XCTAssertEqual(tower.inventory[.cotton], 199)
    }
    func testReleaseWorkingCatStopsProductionAndCannotRepeat() throws {
        var tower = CatTower(now: start)
        let cat = try XCTUnwrap(tower.residents.first)
        XCTAssertTrue(tower.release(cat.id, now: start))
        XCTAssertFalse(tower.release(cat.id, now: start))
        tower.refresh(now: start.addingTimeInterval(600))
        XCTAssertEqual(tower.coins, 95)
        XCTAssertEqual(tower.inventory[.crops], 20)
        XCTAssertEqual(tower.status(at: 1), "等待安排猫猫")
        let restored = try JSONDecoder().decode(CatTower.self, from: JSONEncoder().encode(tower))
        XCTAssertTrue(restored.residents.isEmpty)
    }
    func testDemolitionRefundReturnsWorkerAndDoesNotDuplicate() throws {
        var tower = CatTower(now: start)
        XCTAssertTrue(tower.expand(now: start))
        XCTAssertTrue(tower.welcome(now: start))
        let cat = try XCTUnwrap(tower.lobbyResidents.first)
        XCTAssertTrue(tower.assign(cat.id, to: 2, now: start))
        let stock = tower.inventory
        XCTAssertEqual(tower.demolitionRefund, 50)
        tower = try JSONDecoder().decode(CatTower.self, from: JSONEncoder().encode(tower))
        XCTAssertEqual(tower.demolitionRefund, 50)
        XCTAssertTrue(tower.demolish(2, now: start))
        XCTAssertEqual(tower.coins, 50)
        XCTAssertEqual(tower.floors, 1)
        XCTAssertEqual(tower.inventory, stock)
        XCTAssertEqual(tower.lobbyResidents.map(\.id), [cat.id])
        XCTAssertNil(tower.facilities[2])
        XCTAssertFalse(tower.demolish(2, now: start))
        XCTAssertFalse(tower.demolish(1, now: start))
        XCTAssertEqual(tower.coins, 50)
        XCTAssertEqual(tower.expansionCost, 100)
    }
    func testDemolitionOnlyTopAndProtectsRemodeledDependency() throws {
        var tower = try fixture(facilities: [1: .restaurant, 2: .clothingShop, 3: .textile], inventory: [:])
        XCTAssertFalse(tower.demolish(2, now: start))
        XCTAssertFalse(tower.demolish(3, now: start))
        XCTAssertNotNil(tower.demolitionBlockReason(3))
        // Legacy floors without a purchase record must not mint coins.
        var legacy = try fixture(facilities: [1: .restaurant, 2: .garden], inventory: [:])
        XCTAssertEqual(legacy.demolitionRefund, 0)
        XCTAssertTrue(legacy.demolish(2, now: start))
        XCTAssertEqual(legacy.coins, 100)
    }
    func testLobbyReleaseChargesOnceAndInsufficientFundsKeepCat() throws {
        var tower = CatTower(now: start)
        XCTAssertTrue(tower.welcome(now: start))
        let cat = try XCTUnwrap(tower.lobbyResidents.first)
        XCTAssertTrue(tower.release(cat.id, now: start))
        XCTAssertEqual(tower.coins, 95)
        XCTAssertFalse(tower.release(cat.id, now: start))
        XCTAssertEqual(tower.coins, 95)
        var poor = CatTower(now: start)
        XCTAssertTrue(poor.expand(now: start))
        XCTAssertTrue(poor.welcome(now: start))
        let waiting = try XCTUnwrap(poor.lobbyResidents.first)
        XCTAssertFalse(poor.release(waiting.id, now: start))
        XCTAssertEqual(poor.coins, 0)
        XCTAssertEqual(poor.lobbyResidents.map(\.id), [waiting.id])
    }
    func testVisitorSkillWeightsAndTenMinuteSchedule() throws {
        let experiences = (0..<100).map { CatTower.initialExperience(skillRoll: $0) }
        XCTAssertEqual(experiences.filter { $0 == 0 }.count, 70)
        XCTAssertEqual(experiences.filter { $0 == 60 }.count, 25)
        XCTAssertEqual(experiences.filter { $0 == 300 }.count, 5)
        var tower = CatTower(now: start)
        XCTAssertTrue(tower.welcome(now: start))
        XCTAssertEqual(tower.nextVisit, start.addingTimeInterval(600))
        tower.refresh(now: start.addingTimeInterval(599))
        XCTAssertNil(tower.visitor)
        tower = try JSONDecoder().decode(CatTower.self, from: JSONEncoder().encode(tower))
        tower.refresh(now: start.addingTimeInterval(600))
        let visitor = try XCTUnwrap(tower.visitor)
        XCTAssertTrue([0, 60, 300].contains(visitor.experience))
        tower.refresh(now: start.addingTimeInterval(1200))
        XCTAssertEqual(tower.visitor, visitor, "A waiting cat must not be replaced or rerolled")
        XCTAssertTrue(tower.welcome(now: start.addingTimeInterval(1200)))
        XCTAssertEqual(tower.residents.last?.experience, visitor.experience)
        XCTAssertEqual(tower.nextVisit, start.addingTimeInterval(1800))
    }
    func testThreeWorkersProduceAndFourthAssignmentIsRejected() throws {
        let cats = (0..<4).map { CatTower.Resident(name: "工友\($0)", coat: $0, floor: $0 < 3 ? 1 : nil, specialty: .craft, personality: .careful) }
        var tower = try fixture(facilities: [1: .restaurant], inventory: [.crops: 20], residents: cats)
        XCTAssertFalse(tower.assign(cats[3].id, to: 1, now: start))
        XCTAssertTrue(tower.assign(cats[0].id, to: 1, now: start))
        tower.refresh(now: start.addingTimeInterval(60))
        XCTAssertEqual(tower.coins, 124)
        XCTAssertEqual(tower.inventory[.crops], 17)
        XCTAssertEqual(tower.residents.prefix(3).map(\.experience), [1, 1, 1])
        tower = try JSONDecoder().decode(CatTower.self, from: JSONEncoder().encode(tower))
        XCTAssertEqual(tower.residents.filter { $0.floor == 1 }.count, 3)
        tower.unassign(cats[0].id, now: start.addingTimeInterval(60))
        XCTAssertTrue(tower.assign(cats[3].id, to: 1, now: start.addingTimeInterval(60)))
    }
    func testSharedMaterialsAreNotConsumedMoreThanAvailable() throws {
        let cats = (0..<3).map { CatTower.Resident(name: "工友\($0)", coat: $0, floor: 1, specialty: .craft, personality: .careful) }
        var tower = try fixture(facilities: [1: .restaurant], inventory: [.crops: 1], residents: cats)
        tower.refresh(now: start.addingTimeInterval(60))
        XCTAssertEqual(tower.coins, 108)
        XCTAssertEqual(tower.inventory[.crops], 0)
        XCTAssertEqual(tower.residents.map(\.experience).reduce(0, +), 1)
    }
    func testWorkersKeepIndividualPartialProgressAcrossReloadAndDeparture() throws {
        let cats = (0..<3).map { CatTower.Resident(name: "工友\($0)", coat: $0, floor: 2, specialty: .food, personality: .diligent) }
        var uninterrupted = try fixture(facilities: [1: .restaurant, 2: .garden], inventory: [:], residents: cats)
        uninterrupted.refresh(now: start.addingTimeInterval(120))
        var restored = try JSONDecoder().decode(CatTower.self, from: JSONEncoder().encode(uninterrupted))
        uninterrupted.refresh(now: start.addingTimeInterval(240))
        restored.refresh(now: start.addingTimeInterval(240))
        XCTAssertEqual(restored, uninterrupted)
        XCTAssertTrue(restored.release(cats[0].id, now: start.addingTimeInterval(240)))
        restored.refresh(now: start.addingTimeInterval(300))
        XCTAssertEqual(restored.residents.map(\.experience), [6, 6])
        XCTAssertEqual(restored.residents.count, 2)
        XCTAssertEqual(restored.residents.filter { $0.floor == 2 }.count, 2)
    }
    private func fixture(facilities: [Int: CatTower.Facility], inventory: [CatTower.Material: Int], residents: [CatTower.Resident]? = nil) throws -> CatTower {
        let data = try JSONEncoder().encode(CatTower(now: start))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        if let residents { object["residents"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(residents)) }
        object["floors"] = facilities.count
        object["facilities"] = Dictionary(uniqueKeysWithValues: facilities.map { (String($0.key), $0.value.rawValue) })
        // Non-string enum dictionaries use alternating key/value arrays in Codable.
        object["inventory"] = inventory.flatMap { [$0.key.rawValue as Any, $0.value as Any] }
        return try JSONDecoder().decode(CatTower.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
