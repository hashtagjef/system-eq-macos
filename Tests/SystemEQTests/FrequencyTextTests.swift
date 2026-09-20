import XCTest
@testable import SystemEQ

final class FrequencyTextTests: XCTestCase {
    func testParsesHertzAndKilohertz() {
        XCTAssertEqual(FrequencyText.parse("80"), 80)
        XCTAssertEqual(FrequencyText.parse("1.5k"), 1_500)
        XCTAssertEqual(FrequencyText.parse("12 kHz"), 12_000)
    }

    func testRejectsInvalidAndOutOfRangeValues() {
        XCTAssertNil(FrequencyText.parse("loud"))
        XCTAssertNil(FrequencyText.parse("9"))
        XCTAssertNil(FrequencyText.parse("22k"))
    }

    func testFormatsCompactDisplayValues() {
        XCTAssertEqual(FrequencyText.format(80), "80")
        XCTAssertEqual(FrequencyText.format(1_500), "1.5k")
        XCTAssertEqual(FrequencyText.format(16_000), "16k")
    }

    func testQualityParsingAndFormatting() {
        XCTAssertEqual(QualityText.parse("2.99"), 2.99)
        XCTAssertNil(QualityText.parse("0"))
        XCTAssertEqual(QualityText.format(1.40), "1.4")
    }
}
