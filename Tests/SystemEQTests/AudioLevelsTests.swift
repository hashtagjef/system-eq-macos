import XCTest
@testable import SystemEQ

final class AudioLevelsTests: XCTestCase {
    func testConvertsLinearAmplitudeToDecibels() {
        XCTAssertEqual(BandAudioLevels.decibels(for: 1), 0, accuracy: 0.001)
        XCTAssertEqual(BandAudioLevels.decibels(for: 0.5), -6.0206, accuracy: 0.001)
        XCTAssertEqual(BandAudioLevels.decibels(for: 0), BandAudioLevels.floorDecibels)
    }

    func testDecibelsAreClampedToMeterRange() {
        XCTAssertEqual(BandAudioLevels.decibels(for: 2), 0)
        XCTAssertEqual(BandAudioLevels.decibels(for: 0.000_001), BandAudioLevels.floorDecibels)
        XCTAssertEqual(BandAudioLevels.decibels(for: .infinity), BandAudioLevels.floorDecibels)
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

    func testBandAnalyzerSeparatesCenterFrequencies() {
        let sampleRate: Float = 48_000
        let analyzer = BandLevelAnalyzer(frequencies: [100, 1_000, 10_000], sampleRate: sampleRate)

        for frame in 0..<48_000 {
            let sample = sinf(2 * .pi * 1_000 * Float(frame) / sampleRate)
            analyzer.process(sample, channel: 0)
            analyzer.process(sample, channel: 1)
        }

        let levels = analyzer.takeLevels()
        XCTAssertEqual(levels.rms.count, 3)
        XCTAssertGreaterThan(levels.rms[1], levels.rms[0] * 5)
        XCTAssertGreaterThan(levels.rms[1], levels.rms[2] * 5)
    }
}
