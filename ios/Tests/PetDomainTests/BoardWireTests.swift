import XCTest
@testable import PetDomain

final class BoardWireTests: XCTestCase {
    let id = UUID(uuidString:"00112233-4455-6677-8899-aabbccddeeff")!
    func response(id: UUID? = nil, words: [UInt32]? = nil, motion: [String: Any]? = nil) throws -> Data {
        let state: [UInt32] = words ?? [80,75,12,3,1,0,0,0,123,12,0,456,12345678,0]
        var value: [String:Any] = ["v":2,"requestID":BoardWire.hex(id ?? self.id),"ok":true,"error":"",
            "petID":"0069002a323551033434383100000001","phase":0,"revision":4,
            "transferID":String(repeating:"0",count:32),"payloadHash":0,"state":state]
        if let motion { value["motion"] = motion }
        let data=try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys])
        return data + Data(String(format:"|%08x\n",BoardWire.crc32(data)).utf8)
    }
    func testCRCAndCompleteStateDecode() throws {
        XCTAssertEqual(BoardWire.crc32(Data("123456789".utf8)),0xcbf43926)
        let value=try BoardWire.decode(response(),requestID:id)
        XCTAssertEqual(value.petID.uuidString.lowercased(),"0069002a-3235-5103-3434-383100000001")
        XCTAssertEqual(value.state.gameTimeSeconds,456)
        XCTAssertEqual(value.state.secondsSinceFeed,123)
        XCTAssertEqual(value.state.rngState,12345678)
        XCTAssertEqual(value.state.experience,12)
    }
    func testFragmentationAndRecoveryAfterOversizeLine() throws {
        let data=try response();var buffer=BoardLineBuffer();var lines:[Data]=[]
        for start in stride(from:0,to:data.count,by:20){lines += buffer.append(data.subdata(in:start..<min(data.count,start+20)))}
        XCTAssertEqual(lines.count,1)
        XCTAssertEqual(try BoardWire.decode(lines[0],requestID:id).revision,4)
        XCTAssertTrue(buffer.append(Data(repeating:65,count:5000)).isEmpty)
        XCTAssertTrue(buffer.append(Data("\n".utf8)).isEmpty)
        XCTAssertEqual(buffer.append(data).count,1)
    }
    func testWrongIDCorruptionAndInvalidStateCannotActivatePet() throws {
        XCTAssertThrowsError(try BoardWire.decode(response(id:UUID()),requestID:id))
        var bad=try response();bad[5] ^= 1
        XCTAssertThrowsError(try BoardWire.decode(bad,requestID:id))
        XCTAssertThrowsError(try BoardWire.decode(response(words:[101,75,0,0,1,0,0,0,0,0,0,0,0,0]),requestID:id))
        XCTAssertThrowsError(try BoardWire.decode(Data("H=100 E=86".utf8),requestID:id))
    }
    func testOptionalMotionTelemetryAndRangeValidation() throws {
        XCTAssertNil(try BoardWire.decode(response(), requestID: id).motion)
        var motion: [String: Any] = [
            "connected": true, "xMg": 250, "yMg": -970, "zMg": 320,
            "behavior": 1, "samples": 25, "ageMs": 20, "activeMs": 1000
        ]
        let record = try BoardWire.decode(response(motion: motion), requestID: id)
        XCTAssertEqual(record.motion?.yMg, -970)
        XCTAssertEqual(record.motion?.title, "活动")
        XCTAssertTrue(record.motion?.isFresh == true)
        motion["connected"] = false
        let disconnected = try BoardWire.decode(response(motion: motion), requestID: id)
        XCTAssertFalse(disconnected.motion!.isFresh)
        motion["xMg"] = 30000
        XCTAssertThrowsError(try BoardWire.decode(response(motion: motion), requestID: id))
        motion["xMg"] = 0
        motion["behavior"] = 3
        XCTAssertThrowsError(try BoardWire.decode(response(motion: motion), requestID: id))
    }

    func testReturnFrameCarriesFullSnapshotAndStableIdentity() throws {
        let state=FirmwareState()
        let intent=PhysicalIntent(id:id,destination:.device,baseRevision:4,snapshot:state,released:true)
        let frame=try BoardWire.request(path:"/handoff/return/stage",requestID:id,intent:intent,petID:id)
        let fields=String(decoding:frame,as:UTF8.self).trimmingCharacters(in:.newlines).split(separator:"|",omittingEmptySubsequences:false)
        XCTAssertEqual(fields[1],"RETURN_STAGE")
        XCTAssertEqual(fields[2],Substring(BoardWire.hex(id)))
        XCTAssertEqual(fields[3],Substring(BoardWire.hex(id)))
        XCTAssertEqual(fields[5].split(separator:",").count,14)
        XCTAssertEqual(UInt32(fields[6],radix:16),BoardWire.crc32(Data(fields[0...5].joined(separator:"|").utf8)))
    }
}
