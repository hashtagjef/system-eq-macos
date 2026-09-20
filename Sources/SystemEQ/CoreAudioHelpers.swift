import CoreAudio
import Foundation

struct CoreAudioError: LocalizedError {
    let operation: String
    let status: OSStatus

    var errorDescription: String? {
        let bytes: [UInt8] = [
            UInt8((UInt32(bitPattern: status) >> 24) & 0xff),
            UInt8((UInt32(bitPattern: status) >> 16) & 0xff),
            UInt8((UInt32(bitPattern: status) >> 8) & 0xff),
            UInt8(UInt32(bitPattern: status) & 0xff)
        ]
        let code = bytes.allSatisfy { $0 >= 32 && $0 < 127 }
            ? String(bytes: bytes, encoding: .ascii) ?? "\(status)"
            : "\(status)"
        return "\(operation) failed (\(code))."
    }
}

@inline(__always)
func checkOSStatus(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else { throw CoreAudioError(operation: operation, status: status) }
}

func audioProperty<T>(
    objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
    defaultValue: T
) throws -> T {
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    var value = defaultValue
    var size = UInt32(MemoryLayout<T>.size)
    let status = withUnsafeMutableBytes(of: &value) { bytes in
        AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, bytes.baseAddress!)
    }
    try checkOSStatus(status, "Read Core Audio property")
    return value
}

func audioCFStringProperty(
    objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) throws -> String {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain
    )
    var value: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    try checkOSStatus(
        withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, $0)
        },
        "Read Core Audio string property"
    )
    return value as String
}

func audioProcessObjectID(for pid: pid_t) throws -> AudioObjectID {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var processID = pid
    var objectID = AudioObjectID(kAudioObjectUnknown)
    var objectIDSize = UInt32(MemoryLayout<AudioObjectID>.size)
    try checkOSStatus(
        withUnsafePointer(to: &processID) { processIDPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<pid_t>.size),
                processIDPointer,
                &objectIDSize,
                &objectID
            )
        },
        "Identify the EQ audio process"
    )
    return objectID
}
