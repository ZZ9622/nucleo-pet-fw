import XCTest
@testable import PetDomain

final class MotionPreviewTests: XCTestCase {
    func testWalkStopAndFiniteShakeResumePreviousBehavior() {
        var preview = MotionPreview()
        preview.send(.walk, at: 10)
        XCTAssertEqual(preview.behavior(at: 500), .walking)
        XCTAssertNotEqual(preview.pixels(at: 10), preview.pixels(at: 10.4))
        preview.send(.shake, at: 501)
        XCTAssertEqual(preview.behavior(at: 501.4), .surprised)
        XCTAssertEqual(preview.behavior(at: 502), .walking)
        preview.send(.stop, at: 503)
        XCTAssertEqual(preview.behavior(at: 503), .idle)
        XCTAssertEqual(preview.behavior(at: 9999), .idle)
        preview.send(.shake, at: 10000)
        XCTAssertEqual(preview.behavior(at: 10000), .surprised)
        XCTAssertEqual(preview.behavior(at: 10001), .idle)
    }
    func testStopOverridesShakeAndRepeatedShakeRestartsReaction() {
        var preview = MotionPreview()
        preview.send(.walk, at: 0)
        preview.send(.shake, at: 1)
        preview.send(.shake, at: 1.8)
        XCTAssertEqual(preview.behavior(at: 2.5), .surprised)
        XCTAssertEqual(preview.behavior(at: 2.8), .walking)
        preview.send(.stop, at: 3)
        preview.send(.shake, at: 4)
        preview.send(.stop, at: 4.1)
        XCTAssertEqual(preview.behavior(at: 4.2), .idle)
        XCTAssertEqual(preview.behavior(at: 50), .idle)
    }
    func testPixelFramesAreBoundedDeterministicAndReduceMotionIsStatic() {
        var preview = MotionPreview()
        let idle = preview.pixels(at: 0)
        preview.send(.shake, at: 2)
        XCTAssertNotEqual(preview.pixels(at: 2.2), idle)
        XCTAssertEqual(preview.pixels(at: 2.2), preview.pixels(at: 2.2))
        XCTAssertEqual(preview.pixels(at: 2.1, reduceMotion: true), preview.pixels(at: 2.5, reduceMotion: true))
        preview.send(.walk, at: 3)
        XCTAssertEqual(preview.pixels(at: 3, reduceMotion: true), preview.pixels(at: 5, reduceMotion: true))
        for action in MotionPreview.Action.allCases {
            preview.send(action, at: 20)
            for offset in stride(from: 0.0, through: 4, by: 0.05) {
                XCTAssertEqual(preview.pixels(at: 20 + offset).count, 1024)
            }
        }
    }
    func testInvalidTimeDoesNotReplaceCurrentActionAndInstanceIsIndependent() {
        var first = MotionPreview()
        let second = MotionPreview()
        first.send(.walk, at: 4)
        first.send(.stop, at: .nan)
        XCTAssertEqual(first.behavior(at: 5), .walking)
        XCTAssertEqual(first.eventNumber, 1)
        XCTAssertEqual(second.behavior(at: 5), .idle)
        XCTAssertEqual(first.pixels(at: .nan).count, 1024)
        XCTAssertEqual(first.pixels(at: -50).count, 1024)
    }
}
