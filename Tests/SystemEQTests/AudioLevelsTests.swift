import XCTest
@testable import SystemEQ

final class AudioLevelsTests: XCTestCase {
    func testConvertsLinearAmplitudeToDecibels() {
        XCTAssertEqual(AudioLevels.decibels(for: 1), 0, accuracy: 0.001)
        XCTAssertEqual(AudioLevels.decibels(for: 0.5), -6.0206, accuracy: 0.001)
        XCTAssertEqual(AudioLevels.decibels(for: 0), AudioLevels.floorDecibels)
    }

    func testDecibelsAreClampedToMeterRange() {
        XCTAssertEqual(AudioLevels.decibels(for: 2), 0)
        XCTAssertEqual(AudioLevels.decibels(for: 0.000_001), AudioLevels.floorDecibels)
        XCTAssertEqual(AudioLevels.decibels(for: .infinity), AudioLevels.floorDecibels)
    }

    func testLevelAccumulatorMeasuresRMSAndPeak() {
        var accumulator = LevelAccumulator()
        accumulator.add(1)
        accumulator.add(-1)
        accumulator.add(0)
        accumulator.add(0)

        XCTAssertEqual(accumulator.rootMeanSquare, sqrtf(0.5), accuracy: 0.000_1)
        XCTAssertEqual(accumulator.peak, 1)
        XCTAssertEqual(accumulator.sampleCount, 4)
    }
}
