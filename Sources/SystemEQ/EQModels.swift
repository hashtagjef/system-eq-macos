import Foundation

enum FrequencyText {
    static func format(_ frequency: Float) -> String {
        if frequency >= 1_000 {
            let kilohertz = frequency / 1_000
            return kilohertz.rounded() == kilohertz
                ? "\(Int(kilohertz))k"
                : String(format: "%.1fk", kilohertz)
        }
        return frequency.rounded() == frequency
            ? "\(Int(frequency))"
            : String(format: "%.1f", frequency)
    }

    static func parse(_ input: String) -> Float? {
        var normalized = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: ",", with: "")
        let multiplier: Float
        if normalized.hasSuffix("khz") {
            normalized.removeLast(3)
            multiplier = 1_000
        } else if normalized.hasSuffix("k") {
            normalized.removeLast()
            multiplier = 1_000
        } else if normalized.hasSuffix("hz") {
            normalized.removeLast(2)
            multiplier = 1
        } else {
            multiplier = 1
        }
        guard let value = Float(normalized.trimmingCharacters(in: .whitespaces)) else { return nil }
        let frequency = value * multiplier
        return 10...20_000 ~= frequency ? frequency : nil
    }
}

enum QualityText {
    static func format(_ quality: Float) -> String {
        var value = String(format: "%.2f", quality)
        while value.last == "0" { value.removeLast() }
        if value.last == "." { value.removeLast() }
        return value
    }

    static func parse(_ input: String) -> Float? {
        guard let quality = Float(input.trimmingCharacters(in: .whitespacesAndNewlines)),
              0.1...20 ~= quality else { return nil }
        return quality
    }
}

enum EQFilterType: String, Codable, CaseIterable, Identifiable {
    case peaking
    case lowShelf
    case highShelf
    case lowPass
    case highPass
    case notch
    case bandPass

    var id: String { rawValue }

    var name: String {
        switch self {
        case .peaking: "Bell"
        case .lowShelf: "Low shelf"
        case .highShelf: "High shelf"
        case .lowPass: "Low-pass"
        case .highPass: "High-pass"
        case .notch: "Notch"
        case .bandPass: "Band-pass"
        }
    }

    var abbreviation: String {
        switch self {
        case .peaking: "BEL"
        case .lowShelf: "LS"
        case .highShelf: "HS"
        case .lowPass: "LP"
        case .highPass: "HP"
        case .notch: "NOT"
        case .bandPass: "BP"
        }
    }

    var usesGain: Bool {
        switch self {
        case .peaking, .lowShelf, .highShelf: true
        case .lowPass, .highPass, .notch, .bandPass: false
        }
    }
}

struct EQBand: Identifiable, Equatable {
    let id: Int
    var frequency: Float
    var gain: Float
    var filterType: EQFilterType = .peaking
    var quality: Float = 1.41

    var label: String {
        FrequencyText.format(frequency)
    }
}

struct EQPreset: Identifiable, Codable, Equatable {
    static let defaultFrequencies: [Float] = [
        31, 62, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000
    ]

    let id: String
    let name: String
    let frequencies: [Float]
    let filterTypes: [EQFilterType]
    let gains: [Float]
    let qualities: [Float]
    let preamp: Float
    let automaticHeadroom: Bool

    init(
        id: String,
        name: String,
        frequencies: [Float] = EQPreset.defaultFrequencies,
        filterTypes: [EQFilterType]? = nil,
        gains: [Float],
        qualities: [Float]? = nil,
        preamp: Float = 0,
        automaticHeadroom: Bool = true
    ) {
        self.id = id
        self.name = name
        self.frequencies = frequencies
        self.filterTypes = filterTypes ?? Array(repeating: .peaking, count: gains.count)
        self.gains = gains
        self.qualities = qualities ?? Array(repeating: 1.41, count: gains.count)
        self.preamp = preamp
        self.automaticHeadroom = automaticHeadroom
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, frequencies, filterTypes, gains, qualities, preamp, automaticHeadroom
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        gains = try container.decode([Float].self, forKey: .gains)
        frequencies = try container.decodeIfPresent([Float].self, forKey: .frequencies)
            ?? Self.defaultFrequencies
        filterTypes = try container.decodeIfPresent([EQFilterType].self, forKey: .filterTypes)
            ?? Array(repeating: .peaking, count: gains.count)
        qualities = try container.decodeIfPresent([Float].self, forKey: .qualities)
            ?? Array(repeating: 1.41, count: gains.count)
        preamp = try container.decodeIfPresent(Float.self, forKey: .preamp) ?? 0
        automaticHeadroom = try container.decodeIfPresent(Bool.self, forKey: .automaticHeadroom) ?? true
    }

    static let builtIn: [EQPreset] = [
        EQPreset(id: "flat", name: "Flat", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        EQPreset(id: "bass", name: "Bass Boost", gains: [5, 4, 3, 2, 1, 0, 0, 0, 0, 0]),
        EQPreset(id: "vocal", name: "Vocal", gains: [-2, -1, 0, 1, 3, 4, 3, 1, 0, -1]),
        EQPreset(id: "clarity", name: "Clarity", gains: [-1, -1, 0, 0, 1, 2, 3, 3, 2, 1]),
        EQPreset(id: "late-night", name: "Late Night", gains: [2, 2, 1, 0, 0, 1, 2, 2, 1, 0])
    ]
}

struct EQPresetStore {
    private static let defaultKey = "savedEQPresets"

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [EQPreset] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([EQPreset].self, from: data)) ?? []
    }

    func save(_ presets: [EQPreset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: key)
    }
}

enum EngineState: Equatable {
    case off
    case starting
    case running(deviceName: String)
    case failed(message: String)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}
