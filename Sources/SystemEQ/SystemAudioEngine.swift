import CoreAudio
import Foundation

final class SystemAudioEngine {
    private let audioQueue = DispatchQueue(label: "com.local.SystemEQ.audio", qos: .userInteractive)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var processor: EQProcessor?
    private var sampleRate: Float = 48_000
    private(set) var outputDeviceName = ""

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
        }
    }

    func stop() {
        if let ioProcID {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            self.ioProcID = nil
        }
        processor = nil

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
            for channel in 0..<channels {
                guard let sourceData = inputs[channel].mData, let destinationData = outputs[channel].mData else { continue }
                let frames = min(inputs[channel].mDataByteSize, outputs[channel].mDataByteSize) / UInt32(MemoryLayout<Float>.size)
                let source = sourceData.assumingMemoryBound(to: Float.self)
                let destination = destinationData.assumingMemoryBound(to: Float.self)
                for frame in 0..<Int(frames) {
                    destination[frame] = processor.process(source[frame], channel: channel)
                }
            }
            return
        }

        guard let sourceData = inputs[0].mData, let destinationData = outputs[0].mData else { return }
        let channels = max(1, min(Int(inputs[0].mNumberChannels), Int(outputs[0].mNumberChannels)))
        let samples = min(inputs[0].mDataByteSize, outputs[0].mDataByteSize) / UInt32(MemoryLayout<Float>.size)
        let source = sourceData.assumingMemoryBound(to: Float.self)
        let destination = destinationData.assumingMemoryBound(to: Float.self)
        for sampleIndex in 0..<Int(samples) {
            destination[sampleIndex] = processor.process(source[sampleIndex], channel: sampleIndex % channels)
        }
    }
}
