import CoreAudio
import Foundation

struct BiquadCoefficients {
    var b0: Float
    var b1: Float
    var b2: Float
    var a1: Float
    var a2: Float

    static let identity = BiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)

    static func filter(
        type: EQFilterType,
        frequency: Float,
        gain: Float,
        quality: Float,
        sampleRate: Float
    ) -> Self {
        let q = min(max(quality, 0.1), 20)
        switch type {
        case .peaking:
            return peaking(frequency: frequency, gain: gain, sampleRate: sampleRate, q: q)
        case .lowShelf:
            return shelf(frequency: frequency, gain: gain, quality: q, sampleRate: sampleRate, isHigh: false)
        case .highShelf:
            return shelf(frequency: frequency, gain: gain, quality: q, sampleRate: sampleRate, isHigh: true)
        case .lowPass:
            return pass(frequency: frequency, quality: q, sampleRate: sampleRate, isHigh: false)
        case .highPass:
            return pass(frequency: frequency, quality: q, sampleRate: sampleRate, isHigh: true)
        case .notch:
            return notch(frequency: frequency, sampleRate: sampleRate, q: q)
        case .bandPass:
            return bandPass(frequency: frequency, sampleRate: sampleRate, q: q)
        }
    }

    static func peaking(frequency: Float, gain: Float, sampleRate: Float, q: Float = 1.4) -> Self {
        guard abs(gain) > 0.001, sampleRate > 0 else { return .identity }

        let clampedFrequency = min(frequency, sampleRate * 0.45)
        let amplitude = powf(10, gain / 40)
        let omega = 2 * Float.pi * clampedFrequency / sampleRate
        let alpha = sinf(omega) / (2 * q)
        let cosine = cosf(omega)
        let a0 = 1 + alpha / amplitude

        return BiquadCoefficients(
            b0: (1 + alpha * amplitude) / a0,
            b1: (-2 * cosine) / a0,
            b2: (1 - alpha * amplitude) / a0,
            a1: (-2 * cosine) / a0,
            a2: (1 - alpha / amplitude) / a0
        )
    }

    private static func pass(frequency: Float, quality: Float, sampleRate: Float, isHigh: Bool) -> Self {
        guard sampleRate > 0 else { return .identity }
        let omega = normalizedOmega(frequency: frequency, sampleRate: sampleRate)
        let cosine = cosf(omega)
        let alpha = sinf(omega) / (2 * quality)
        let a0 = 1 + alpha
        let base = isHigh ? (1 + cosine) : (1 - cosine)
        return normalized(
            b0: base / 2,
            b1: isHigh ? -base : base,
            b2: base / 2,
            a0: a0,
            a1: -2 * cosine,
            a2: 1 - alpha
        )
    }

    private static func notch(frequency: Float, sampleRate: Float, q: Float = 1.4) -> Self {
        guard sampleRate > 0 else { return .identity }
        let omega = normalizedOmega(frequency: frequency, sampleRate: sampleRate)
        let cosine = cosf(omega)
        let alpha = sinf(omega) / (2 * q)
        return normalized(
            b0: 1,
            b1: -2 * cosine,
            b2: 1,
            a0: 1 + alpha,
            a1: -2 * cosine,
            a2: 1 - alpha
        )
    }

    private static func bandPass(frequency: Float, sampleRate: Float, q: Float = 1.4) -> Self {
        guard sampleRate > 0 else { return .identity }
        let omega = normalizedOmega(frequency: frequency, sampleRate: sampleRate)
        let cosine = cosf(omega)
        let alpha = sinf(omega) / (2 * q)
        return normalized(
            b0: alpha,
            b1: 0,
            b2: -alpha,
            a0: 1 + alpha,
            a1: -2 * cosine,
            a2: 1 - alpha
        )
    }

    private static func shelf(
        frequency: Float,
        gain: Float,
        quality: Float,
        sampleRate: Float,
        isHigh: Bool
    ) -> Self {
        guard abs(gain) > 0.001, sampleRate > 0 else { return .identity }
        let amplitude = powf(10, gain / 40)
        let omega = normalizedOmega(frequency: frequency, sampleRate: sampleRate)
        let cosine = cosf(omega)
        let alpha = sinf(omega) / (2 * quality)
        let twoRootAAlpha = 2 * sqrtf(amplitude) * alpha
        let aPlus = amplitude + 1
        let aMinus = amplitude - 1

        if isHigh {
            return normalized(
                b0: amplitude * (aPlus + aMinus * cosine + twoRootAAlpha),
                b1: -2 * amplitude * (aMinus + aPlus * cosine),
                b2: amplitude * (aPlus + aMinus * cosine - twoRootAAlpha),
                a0: aPlus - aMinus * cosine + twoRootAAlpha,
                a1: 2 * (aMinus - aPlus * cosine),
                a2: aPlus - aMinus * cosine - twoRootAAlpha
            )
        }

        return normalized(
            b0: amplitude * (aPlus - aMinus * cosine + twoRootAAlpha),
            b1: 2 * amplitude * (aMinus - aPlus * cosine),
            b2: amplitude * (aPlus - aMinus * cosine - twoRootAAlpha),
            a0: aPlus + aMinus * cosine + twoRootAAlpha,
            a1: -2 * (aMinus + aPlus * cosine),
            a2: aPlus + aMinus * cosine - twoRootAAlpha
        )
    }

    private static func normalizedOmega(frequency: Float, sampleRate: Float) -> Float {
        2 * Float.pi * min(max(frequency, 10), sampleRate * 0.45) / sampleRate
    }

    private static func normalized(
        b0: Float,
        b1: Float,
        b2: Float,
        a0: Float,
        a1: Float,
        a2: Float
    ) -> Self {
        BiquadCoefficients(
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0
        )
    }
}

struct BiquadState {
    var z1: Float = 0
    var z2: Float = 0

    mutating func process(_ sample: Float, coefficients: BiquadCoefficients) -> Float {
        let output = coefficients.b0 * sample + z1
        z1 = coefficients.b1 * sample - coefficients.a1 * output + z2
        z2 = coefficients.b2 * sample - coefficients.a2 * output
        return output
    }
}

final class EQProcessor {
    private var coefficients: [BiquadCoefficients]
    private var states: [[BiquadState]]
    private var linearGain: Float = 1
    private var isBypassed = false
    private let channelCount: Int

    init(frequencies: [Float], sampleRate: Float, channelCount: Int = 2) {
        self.channelCount = max(channelCount, 1)
        self.coefficients = Array(repeating: .identity, count: frequencies.count)
        self.states = Array(
            repeating: Array(repeating: BiquadState(), count: frequencies.count),
            count: max(channelCount, 1)
        )
        update(
            frequencies: frequencies,
            filterTypes: Array(repeating: .peaking, count: frequencies.count),
            gains: Array(repeating: 0, count: frequencies.count),
            qualities: Array(repeating: 1.41, count: frequencies.count),
            preamp: 0,
            sampleRate: sampleRate,
            bypassed: false
        )
    }

    func update(
        frequencies: [Float],
        filterTypes: [EQFilterType],
        gains: [Float],
        qualities: [Float],
        preamp: Float,
        sampleRate: Float,
        bypassed: Bool
    ) {
        guard !frequencies.isEmpty,
              filterTypes.count == frequencies.count,
              gains.count == frequencies.count,
              qualities.count == frequencies.count else { return }
        if coefficients.count != frequencies.count {
            coefficients = Array(repeating: .identity, count: frequencies.count)
            states = Array(
                repeating: Array(repeating: BiquadState(), count: frequencies.count),
                count: channelCount
            )
        }
        isBypassed = bypassed
        linearGain = powf(10, preamp / 20)
        coefficients = frequencies.indices.map { index in
            BiquadCoefficients.filter(
                type: filterTypes[index],
                frequency: frequencies[index],
                gain: gains[index],
                quality: qualities[index],
                sampleRate: sampleRate
            )
        }
    }

    func reset() {
        for channel in states.indices {
            for band in states[channel].indices {
                states[channel][band] = BiquadState()
            }
        }
    }

    @inline(__always)
    func process(_ input: Float, channel: Int) -> Float {
        guard !isBypassed else { return input }
        let stateChannel = min(channel, channelCount - 1)
        var sample = input * linearGain
        for band in coefficients.indices {
            sample = states[stateChannel][band].process(sample, coefficients: coefficients[band])
        }

        // A transparent ceiling is preferable to wrapping or sending invalid samples downstream.
        return min(max(sample, -0.999), 0.999)
    }
}
