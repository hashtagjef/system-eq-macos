import CoreAudio
import Foundation

final class SystemAudioEngine {
    private let audioQueue = DispatchQueue(label: "com.local.SystemEQ.audio", qos: .userInteractive)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var processor: EQProcessor?
    private var levelAnalyzer: BandLevelAnalyzer?
    private var sampleRate: Float = 48_000
    private var isMeteringEnabled = false
    private var meterFramesSinceUpdate = 0
    private(set) var outputDeviceName = ""
    var levelHandler: ((BandAudioLevels) -> Void)?

    var isRunning: Bool { ioProcID != nil }

    func start(
        frequencies: [Float],
        filterTypes: [EQFilterType],
        gains: [Float],
        qualities: [Float],
        preamp: Float,
        bypassed: Bool
    ) throws {
        guard #available(macOS 14.2, *) else {
            throw CoreAudioError(operation: "System EQ requires macOS 14.2 or later", status: kAudioHardwareUnsupportedOperationError)
        }
        guard !isRunning else { return }

        do {
            let outputDevice = try defaultOutputDevice()
            let outputUID = try audioCFStringProperty(
                objectID: outputDevice,
                selector: kAudioDevicePropertyDeviceUID
            )
            outputDeviceName = try audioCFStringProperty(
                objectID: outputDevice,
                selector: kAudioObjectPropertyName
            )

            let format: AudioStreamBasicDescription = try audioProperty(
                objectID: outputDevice,
                selector: kAudioDevicePropertyStreamFormat,
                scope: kAudioDevicePropertyScopeOutput,
                defaultValue: AudioStreamBasicDescription()
            )
            try validate(format: format)
            sampleRate = Float(format.mSampleRate)

            let ownProcessObjectID = try audioProcessObjectID(for: ProcessInfo.processInfo.processIdentifier)
            let excludedProcesses = ownProcessObjectID == kAudioObjectUnknown ? [] : [ownProcessObjectID]
            let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: excludedProcesses)
            tapDescription.name = "System EQ Global Tap"
            tapDescription.uuid = UUID()
            tapDescription.isPrivate = true
            tapDescription.muteBehavior = .mutedWhenTapped

            try checkOSStatus(
                AudioHardwareCreateProcessTap(tapDescription, &tapID),
                "Create system audio tap"
            )

            let tapUID = try audioCFStringProperty(objectID: tapID, selector: kAudioTapPropertyUID)
            let aggregateDescription: [String: Any] = [
                kAudioAggregateDeviceNameKey: "System EQ Private Device",
                kAudioAggregateDeviceUIDKey: "com.local.SystemEQ.aggregate.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceSubDeviceListKey: [
                    [kAudioSubDeviceUIDKey: outputUID]
                ],
                kAudioAggregateDeviceTapListKey: [
                    [
                        kAudioSubTapUIDKey: tapUID,
                        kAudioSubTapDriftCompensationKey: true
                    ]
                ]
            ]

            try checkOSStatus(
                AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateDeviceID),
                "Create private audio route"
            )

            let processor = EQProcessor(frequencies: frequencies, sampleRate: sampleRate)
            processor.update(
                frequencies: frequencies,
                filterTypes: filterTypes,
                gains: gains,
                qualities: qualities,
                preamp: preamp,
                sampleRate: sampleRate,
                bypassed: bypassed
            )
            self.processor = processor
            levelAnalyzer = BandLevelAnalyzer(frequencies: frequencies, sampleRate: sampleRate)

            var createdIOProc: AudioDeviceIOProcID?
            try checkOSStatus(
                AudioDeviceCreateIOProcIDWithBlock(
                    &createdIOProc,
                    aggregateDeviceID,
                    audioQueue
                ) { [weak self] _, inputData, _, outputData, _ in
                    self?.render(inputData: inputData, outputData: outputData)
                },
                "Create real-time audio callback"
            )
            ioProcID = createdIOProc

            try checkOSStatus(
                AudioDeviceStart(aggregateDeviceID, createdIOProc),
                "Start system EQ"
            )
        } catch {
            stop()
            throw error
        }
    }

    func update(
        frequencies: [Float],
        filterTypes: [EQFilterType],
        gains: [Float],
        qualities: [Float],
        preamp: Float,
        bypassed: Bool
    ) {
        let rate = sampleRate
        audioQueue.async { [weak self] in
            self?.processor?.update(
                frequencies: frequencies,
                filterTypes: filterTypes,
                gains: gains,
                qualities: qualities,
                preamp: preamp,
                sampleRate: rate,
                bypassed: bypassed
            )
            self?.levelAnalyzer?.update(frequencies: frequencies, sampleRate: rate)
        }
    }

    func setMeteringEnabled(_ enabled: Bool) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.isMeteringEnabled = enabled
            if !enabled {
                self.resetMeterAccumulators()
            }
        }
    }

    func stop() {
        if let ioProcID {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            self.ioProcID = nil
        }
        processor = nil
        levelAnalyzer = nil
        resetMeterAccumulators()

        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            if #available(macOS 14.2, *) {
                AudioHardwareDestroyProcessTap(tapID)
            }
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private func defaultOutputDevice() throws -> AudioObjectID {
        let device: AudioObjectID = try audioProperty(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDefaultOutputDevice,
            defaultValue: AudioObjectID(kAudioObjectUnknown)
        )
        guard device != kAudioObjectUnknown else {
            throw CoreAudioError(operation: "Find default output device", status: kAudioHardwareBadDeviceError)
        }
        return device
    }

    private func validate(format: AudioStreamBasicDescription) throws {
        let isPCM = format.mFormatID == kAudioFormatLinearPCM
        let isFloat = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let is32Bit = format.mBitsPerChannel == 32
        guard isPCM, isFloat, is32Bit else {
            throw CoreAudioError(operation: "Unsupported output format", status: kAudioHardwareUnsupportedOperationError)
        }
    }

    private func render(inputData: UnsafePointer<AudioBufferList>, outputData: UnsafeMutablePointer<AudioBufferList>) {
        guard let processor else { return }

        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        let outputs = UnsafeMutableAudioBufferListPointer(outputData)
        guard !inputs.isEmpty, !outputs.isEmpty else { return }

        if inputs.count >= 2, outputs.count >= 2 {
            let channels = min(2, min(inputs.count, outputs.count))
            var frameCount = 0
            for channel in 0..<channels {
                guard let sourceData = inputs[channel].mData, let destinationData = outputs[channel].mData else { continue }
                let frames = min(inputs[channel].mDataByteSize, outputs[channel].mDataByteSize) / UInt32(MemoryLayout<Float>.size)
                let source = sourceData.assumingMemoryBound(to: Float.self)
                let destination = destinationData.assumingMemoryBound(to: Float.self)
                frameCount = max(frameCount, Int(frames))
                for frame in 0..<Int(frames) {
                    let output = processor.process(source[frame], channel: channel)
                    destination[frame] = output
                    if isMeteringEnabled {
                        levelAnalyzer?.process(output, channel: channel)
                    }
                }
            }
            publishMeterIfNeeded(frameCount: frameCount)
            return
        }

        guard let sourceData = inputs[0].mData, let destinationData = outputs[0].mData else { return }
        let channels = max(1, min(Int(inputs[0].mNumberChannels), Int(outputs[0].mNumberChannels)))
        let samples = min(inputs[0].mDataByteSize, outputs[0].mDataByteSize) / UInt32(MemoryLayout<Float>.size)
        let source = sourceData.assumingMemoryBound(to: Float.self)
        let destination = destinationData.assumingMemoryBound(to: Float.self)
        for sampleIndex in 0..<Int(samples) {
            let channel = sampleIndex % channels
            let output = processor.process(source[sampleIndex], channel: channel)
            destination[sampleIndex] = output
            if isMeteringEnabled {
                levelAnalyzer?.process(output, channel: min(channel, 1))
            }
        }
        publishMeterIfNeeded(frameCount: Int(samples) / channels)
    }

    private func publishMeterIfNeeded(frameCount: Int) {
        guard isMeteringEnabled, let levelAnalyzer else { return }
        meterFramesSinceUpdate += frameCount

        let updateInterval = max(Int(sampleRate / 30), 1)
        guard meterFramesSinceUpdate >= updateInterval else { return }

        levelHandler?(levelAnalyzer.takeLevels())
        resetMeterAccumulators()
    }

    private func resetMeterAccumulators() {
        levelAnalyzer?.resetLevels()
        meterFramesSinceUpdate = 0
    }
}

final class BandLevelAnalyzer {
    private var coefficients: [BiquadCoefficients] = []
    private var states: [[BiquadState]] = []
    private var accumulators: [LevelAccumulator] = []
    private var frequencies: [Float] = []
    private var sampleRate: Float = 0

    init(frequencies: [Float], sampleRate: Float) {
        update(frequencies: frequencies, sampleRate: sampleRate)
    }

    func update(frequencies: [Float], sampleRate: Float) {
        guard frequencies != self.frequencies || sampleRate != self.sampleRate else { return }
        self.frequencies = frequencies
        self.sampleRate = sampleRate
        coefficients = frequencies.map {
            BiquadCoefficients.filter(
                type: .bandPass,
                frequency: $0,
                gain: 0,
                quality: 1.41,
                sampleRate: sampleRate
            )
        }
        states = Array(
            repeating: Array(repeating: BiquadState(), count: frequencies.count),
            count: 2
        )
        resetLevels()
    }

    @inline(__always)
    func process(_ sample: Float, channel: Int) {
        let analyzerChannel = min(max(channel, 0), states.count - 1)
        for band in coefficients.indices {
            let filtered = states[analyzerChannel][band].process(sample, coefficients: coefficients[band])
            accumulators[band].add(filtered)
        }
    }

    func takeLevels() -> BandAudioLevels {
        let levels = BandAudioLevels(
            rms: accumulators.map(\.rootMeanSquare),
            peaks: accumulators.map(\.peak)
        )
        resetLevels()
        return levels
    }

    func resetLevels() {
        accumulators = Array(repeating: LevelAccumulator(), count: coefficients.count)
    }
}

struct LevelAccumulator {
    private(set) var sumOfSquares: Float = 0
    private(set) var peak: Float = 0
    private(set) var sampleCount = 0

    var rootMeanSquare: Float {
        guard sampleCount > 0 else { return 0 }
        return sqrtf(sumOfSquares / Float(sampleCount))
    }

    mutating func add(_ sample: Float) {
        guard sample.isFinite else { return }
        sumOfSquares += sample * sample
        peak = max(peak, abs(sample))
        sampleCount += 1
    }

}
