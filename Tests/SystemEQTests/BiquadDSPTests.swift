import XCTest
@testable import SystemEQ

final class BiquadDSPTests: XCTestCase {
    func testIdentityFilterDoesNotChangeSamples() {
        var state = BiquadState()
        let input: [Float] = [-0.8, -0.2, 0, 0.25, 0.9]
        let output = input.map { state.process($0, coefficients: .identity) }
        XCTAssertEqual(input, output)
    }

    func testFlatProcessorDoesNotChangeSamples() {
        let processor = EQProcessor(frequencies: [100, 1_000, 10_000], sampleRate: 48_000)
        let input: [Float] = [-0.75, -0.1, 0, 0.2, 0.8]
        let output = input.map { processor.process($0, channel: 0) }
        XCTAssertEqual(input, output)
    }

    func testProcessorAcceptsUpdatedCenterFrequencies() {
        let processor = EQProcessor(frequencies: [100, 1_000], sampleRate: 48_000)
        processor.update(
            frequencies: [80, 2_500],
            filterTypes: [.lowShelf, .notch],
            gains: [6, -4],
            qualities: [0.71, 2],
            preamp: -6,
            sampleRate: 48_000,
            bypassed: false
        )

        let output = (0..<128).map { index in
            processor.process(sinf(Float(index) * 0.1), channel: 0)
        }
        XCTAssertTrue(output.allSatisfy(\.isFinite))
    }

    func testEveryFilterProducesFiniteCoefficients() {
        for filterType in EQFilterType.allCases {
            let coefficients = BiquadCoefficients.filter(
                type: filterType,
                frequency: 1_000,
                gain: 6,
                quality: 1.41,
                sampleRate: 48_000
            )
            XCTAssertTrue(
                [coefficients.b0, coefficients.b1, coefficients.b2, coefficients.a1, coefficients.a2]
                    .allSatisfy(\.isFinite),
                "Non-finite coefficients for \(filterType.name)"
            )
        }
    }

    func testProcessorResizesItsFilterBank() {
        let processor = EQProcessor(frequencies: [100, 1_000], sampleRate: 48_000)
        let frequencies: [Float] = [60, 250, 1_000, 4_000, 12_000]
        processor.update(
            frequencies: frequencies,
            filterTypes: Array(repeating: .peaking, count: frequencies.count),
            gains: [2, -1, 3, -2, 1],
            qualities: [0.7, 1, 1.4, 2, 3],
            preamp: -3,
            sampleRate: 48_000,
            bypassed: false
        )

        let output = (0..<128).map { index in
            processor.process(sinf(Float(index) * 0.08), channel: 1)
        }
        XCTAssertTrue(output.allSatisfy(\.isFinite))
    }

    func testPeakingCoefficientsStayFinite() {
        let coefficients = BiquadCoefficients.peaking(
            frequency: 1_000,
            gain: 12,
            sampleRate: 48_000
        )
        XCTAssertTrue([coefficients.b0, coefficients.b1, coefficients.b2, coefficients.a1, coefficients.a2].allSatisfy(\.isFinite))
    }
}
