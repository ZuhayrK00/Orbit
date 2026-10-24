import CoreAudio
import AppKit

enum AudioProperties {
    static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }
    static func scalar<T: BitwiseCopyable>(_ object: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: UInt32 = 0, initial: T) -> T? {
        var address = address(selector, scope: scope, element: element), result = initial, size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &result) == noErr else { return nil }; return result
    }
    static func string(_ object: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector), result: Unmanaged<CFString>?, size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &result) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
        guard status == noErr, let result else { return nil }; return result.takeRetainedValue() as String
    }
    static func list(_ object: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var address = address(selector, scope: scope), size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var result = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let status = result.withUnsafeMutableBytes { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0.baseAddress!) }
        return status == noErr ? result : []
    }
    static func set<T: BitwiseCopyable>(_ object: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: UInt32 = 0, value: T) -> OSStatus {
        var address = address(selector, scope: scope, element: element), copy = value
        return AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), &copy)
    }
    static func hasOutput(_ device: AudioObjectID) -> Bool { !list(device, selector: kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput).isEmpty }
    static func volume(_ device: AudioObjectID, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeOutput) -> Float? {
        if let main: Float = scalar(device, selector: kAudioDevicePropertyVolumeScalar, scope: scope, initial: Float(0)) { return main }
        let channels: [Float] = [UInt32(1), 2].compactMap { scalar(device, selector: kAudioDevicePropertyVolumeScalar, scope: scope, element: $0, initial: Float(0)) }
        return channels.isEmpty ? nil : channels.reduce(0, +) / Float(channels.count)
    }
}
