import AppKit
import Combine
import Foundation

@MainActor
final class AudioController: ObservableObject {
    static let minimumBandCount = 1
    static let maximumBandCount = 24

    @Published private(set) var state: EngineState = .off
    @Published var bands: [EQBand]
    @Published var preamp: Float = 0
    @Published var automaticHeadroom = true
    @Published var bypassed = false
    @Published var selectedPresetID = "flat"
    @Published private(set) var userPresets: [EQPreset]

    private let engine = SystemAudioEngine()
    private let presetStore: EQPresetStore
    private var updateTask: Task<Void, Never>?
    private var nextBandID = EQPreset.defaultFrequencies.count

    init(presetStore: EQPresetStore = EQPresetStore()) {
        self.presetStore = presetStore
        self.userPresets = presetStore.load()
        bands = EQPreset.defaultFrequencies.enumerated().map {
            EQBand(id: $0.offset, frequency: $0.element, gain: 0, filterType: .peaking)
        }
    }

    var effectivePreamp: Float {
        guard automaticHeadroom else { return preamp }
        let activeGains = bands.filter { $0.filterType.usesGain }.map(\.gain)
        return preamp - max(0, activeGains.max() ?? 0)
    }

    var canAddBand: Bool { bands.count < Self.maximumBandCount }
    var canRemoveBand: Bool { bands.count > Self.minimumBandCount }

    func toggleEngine() {
        state.isRunning ? stop() : start()
    }

    func start() {
        guard !state.isRunning else { return }
        state = .starting
        do {
            try engine.start(
                frequencies: bands.map(\.frequency),
                filterTypes: bands.map(\.filterType),
                gains: bands.map(\.gain),
                qualities: bands.map(\.quality),
                preamp: effectivePreamp,
                bypassed: bypassed
            )
            state = .running(deviceName: engine.outputDeviceName)
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    func stop() {
        updateTask?.cancel()
        updateTask = nil
        engine.stop()
        state = .off
    }

    func setGain(_ gain: Float, at index: Int) {
        guard bands.indices.contains(index) else { return }
        bands[index].gain = gain
        selectedPresetID = "custom"
        scheduleEngineUpdate()
    }

    func setFrequency(_ frequency: Float, at index: Int) {
        guard bands.indices.contains(index) else { return }
        bands[index].frequency = min(max(frequency, 10), 20_000)
        selectedPresetID = "custom"
        scheduleEngineUpdate()
    }

    func setFilterType(_ filterType: EQFilterType, at index: Int) {
        guard bands.indices.contains(index) else { return }
        bands[index].filterType = filterType
        selectedPresetID = "custom"
        scheduleEngineUpdate()
    }

    func setQuality(_ quality: Float, at index: Int) {
        guard bands.indices.contains(index) else { return }
        bands[index].quality = min(max(quality, 0.1), 20)
        selectedPresetID = "custom"
        scheduleEngineUpdate()
    }

    func addBand() {
        guard canAddBand else { return }
        let frequency = frequencyForNewBand()
        bands.append(EQBand(id: nextBandID, frequency: frequency, gain: 0, filterType: .peaking))
        nextBandID += 1
        bands.sort { $0.frequency < $1.frequency }
        selectedPresetID = "custom"
        scheduleEngineUpdate()
    }

    func removeLastBand() {
        guard canRemoveBand else { return }
        bands.removeLast()
        selectedPresetID = "custom"
        scheduleEngineUpdate()
    }

    func applyPreset(_ preset: EQPreset) {
        guard !preset.gains.isEmpty,
              preset.gains.count <= Self.maximumBandCount,
              preset.frequencies.count == preset.gains.count,
              preset.filterTypes.count == preset.gains.count,
              preset.qualities.count == preset.gains.count else { return }
        selectedPresetID = preset.id
        if bands.count == preset.gains.count {
            for index in bands.indices {
                bands[index].frequency = preset.frequencies[index]
                bands[index].filterType = preset.filterTypes[index]
                bands[index].gain = preset.gains[index]
                bands[index].quality = preset.qualities[index]
            }
        } else {
            bands = preset.gains.indices.map { index in
                defer { nextBandID += 1 }
                return EQBand(
                    id: nextBandID,
                    frequency: preset.frequencies[index],
                    gain: preset.gains[index],
                    filterType: preset.filterTypes[index],
                    quality: preset.qualities[index]
                )
            }
        }
        preamp = preset.preamp
        automaticHeadroom = preset.automaticHeadroom
        scheduleEngineUpdate()
    }

    func preset(withID id: String) -> EQPreset? {
        EQPreset.builtIn.first(where: { $0.id == id })
            ?? userPresets.first(where: { $0.id == id })
    }

    func savePreset(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        if let index = userPresets.firstIndex(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) {
            let existingID = userPresets[index].id
            userPresets[index] = currentPreset(id: existingID, name: name)
            selectedPresetID = existingID
        } else {
            let preset = currentPreset(id: UUID().uuidString, name: name)
            userPresets.append(preset)
            userPresets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            selectedPresetID = preset.id
        }
        presetStore.save(userPresets)
    }

    func deleteSelectedPreset() {
        guard userPresets.contains(where: { $0.id == selectedPresetID }) else { return }
        userPresets.removeAll { $0.id == selectedPresetID }
        presetStore.save(userPresets)
        selectedPresetID = "custom"
    }

    func controlsChanged(markPresetCustom: Bool = true) {
        if markPresetCustom {
            selectedPresetID = "custom"
        }
        scheduleEngineUpdate()
    }

    private func currentPreset(id: String, name: String) -> EQPreset {
        EQPreset(
            id: id,
            name: name,
            frequencies: bands.map(\.frequency),
            filterTypes: bands.map(\.filterType),
            gains: bands.map(\.gain),
            qualities: bands.map(\.quality),
            preamp: preamp,
            automaticHeadroom: automaticHeadroom
        )
    }

    private func frequencyForNewBand() -> Float {
        let sortedFrequencies = bands.map(\.frequency).sorted()
        let boundaries = [Float(10)] + sortedFrequencies + [Float(20_000)]
        guard boundaries.count >= 2 else { return 1_000 }

        var widestGap = (lower: boundaries[0], upper: boundaries[1])
        var widestRatio = widestGap.upper / widestGap.lower
        for index in 1..<(boundaries.count - 1) {
            let lower = boundaries[index]
            let upper = boundaries[index + 1]
            let ratio = upper / max(lower, 1)
            if ratio > widestRatio {
                widestRatio = ratio
                widestGap = (lower, upper)
            }
        }
        return sqrtf(widestGap.lower * widestGap.upper)
    }

    private func scheduleEngineUpdate() {
        guard state.isRunning else { return }
        updateTask?.cancel()
        updateTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(20))
            guard !Task.isCancelled, let self else { return }
            self.engine.update(
                frequencies: self.bands.map(\.frequency),
                filterTypes: self.bands.map(\.filterType),
                gains: self.bands.map(\.gain),
                qualities: self.bands.map(\.quality),
                preamp: self.effectivePreamp,
                bypassed: self.bypassed
            )
        }
    }
}
