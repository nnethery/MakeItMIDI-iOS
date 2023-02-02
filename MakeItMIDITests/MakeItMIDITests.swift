//
//  MakeItMIDITests.swift
//  MakeItMIDITests
//
//  Created by Noah Nethery on 11/17/22.
//

import XCTest
import Matft

final class MakeItMIDITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testViterbiDecoding() throws {
        let frameProbs = MfArray([[0.2, 0.1], [0.5, 0.1], [0.5, 0.1], [0.8, 0.1]])
        let onsetProbs = MfArray([[0.1, 0.1], [0.1, 0.1], [0.9, 0.1], [0.1, 0.1]])
        
        let pianoroll = SoundClassifier.probsToPianorollViterbi(_frames: frameProbs, _onsets: onsetProbs).flatten().toArray() as! [Bool]
        
        let expected = [false, false, false, false, true, false, true, false]
        
        XCTAssertEqual(pianoroll, expected, "Vitberi decoding is incorrect with alpha 0.5")
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        measure {
            // Put the code you want to measure the time of here.
        }
    }

}
