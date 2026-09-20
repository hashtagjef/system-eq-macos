import XCTest
@testable import SystemEQ

@MainActor
final class AudioControllerTests: XCTestCase {
    func testAddingAndRemovingBands() {
        let controller = makeController()
        let originalCount = controller.bands.count

        controller.addBand()

        XCTAssertEqual(controller.bands.count, originalCount + 1)
        XCTAssertEqual(controller.bands.map(\.frequency), controller.bands.map(\.frequency).sorted())

        controller.removeLastBand()
        XCTAssertEqual(controller.bands.count, originalCount)
    }

    func testApplyingPresetRestoresItsBandCount() {
        let controller = makeController()
        let preset = EQPreset(
            id: "three-band",
            name: "Three Band",
            frequencies: [100, 1_000, 10_000],
            filterTypes: [.lowShelf, .peaking, .highShelf],
            gains: [2, -1, 3],
            qualities: [0.71, 2, 1.2]
        )

        controller.applyPreset(preset)

        XCTAssertEqual(controller.bands.count, 3)
        XCTAssertEqual(controller.bands.map(\.filterType), preset.filterTypes)
        XCTAssertEqual(controller.bands.map(\.quality), preset.qualities)
    }

    private func makeController() -> AudioController {
        let suite = "SystemEQTests.AudioController.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AudioController(presetStore: EQPresetStore(defaults: defaults, key: "presets"))
    }
}
