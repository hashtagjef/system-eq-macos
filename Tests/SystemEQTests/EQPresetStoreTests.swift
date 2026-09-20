import XCTest
@testable import SystemEQ

final class EQPresetStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SystemEQTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSavedPresetsRoundTrip() {
        let store = EQPresetStore(defaults: defaults, key: "presets")
        let preset = EQPreset(
            id: "test-id",
            name: "Desk Speakers",
            frequencies: [80, 900, 12_000],
            filterTypes: [.lowShelf, .peaking, .highShelf],
            gains: [1, 2, 3],
            qualities: [0.71, 2, 1.2],
            preamp: -2.5,
            automaticHeadroom: false
        )

        store.save([preset])

        XCTAssertEqual(store.load(), [preset])
    }

    func testLegacyPresetUsesDefaultFrequencies() throws {
        let legacyJSON = """
        [{"id":"legacy","name":"Old preset","gains":[0,0,0,0,0,0,0,0,0,0],"preamp":0,"automaticHeadroom":true}]
        """
        defaults.set(try XCTUnwrap(legacyJSON.data(using: .utf8)), forKey: "presets")
        let store = EQPresetStore(defaults: defaults, key: "presets")

        XCTAssertEqual(store.load().first?.frequencies, EQPreset.defaultFrequencies)
        XCTAssertEqual(store.load().first?.filterTypes, Array(repeating: .peaking, count: 10))
        XCTAssertEqual(store.load().first?.qualities, Array(repeating: 1.41, count: 10))
    }

    func testMissingDataReturnsEmptyList() {
        let store = EQPresetStore(defaults: defaults, key: "presets")
        XCTAssertEqual(store.load(), [])
    }
}
