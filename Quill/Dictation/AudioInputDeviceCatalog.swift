import CoreAudio
import Foundation

enum AudioDeviceProviderError: LocalizedError {
    case coreAudio(OSStatus)

    var errorDescription: String? {
        switch self {
        case .coreAudio(let status):
            "Quill could not read audio devices (Core Audio error \(status))."
        }
    }
}

protocol AudioInputDeviceProviding: AnyObject {
    func inputDevices() throws -> [AudioInputDevice]
    func defaultInputDeviceID() throws -> AudioDeviceID
    func startObserving(_ handler: @escaping @Sendable () -> Void)
    func stopObserving()
}

final class CoreAudioInputDeviceProvider: AudioInputDeviceProviding {
    private let listenerQueue = DispatchQueue(label: "com.quill.voice.audio-devices")
    private var listener: AudioObjectPropertyListenerBlock?

    func inputDevices() throws -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ))
        var identifiers = [AudioDeviceID](
            repeating: kAudioObjectUnknown,
            count: Int(size) / MemoryLayout<AudioDeviceID>.size
        )
        try check(AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &identifiers
        ))

        return identifiers.compactMap { identifier in
            do {
                guard try hasInputStreams(identifier) else { return nil }
                return AudioInputDevice(
                    deviceID: identifier,
                    uid: try stringProperty(kAudioDevicePropertyDeviceUID, on: identifier),
                    name: try stringProperty(kAudioObjectPropertyName, on: identifier)
                )
            } catch {
                QuillLogger.audio.error("Skipping unreadable audio device \(identifier): \(error.localizedDescription)")
                return nil
            }
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func defaultInputDeviceID() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var identifier = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        try check(AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &identifier
        ))
        return identifier
    }

    func startObserving(_ handler: @escaping @Sendable () -> Void) {
        stopObserving()
        let listener: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        self.listener = listener
        for var address in Self.observedAddresses {
            let status = AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                listenerQueue,
                listener
            )
            if status != noErr {
                QuillLogger.audio.error("Unable to observe audio device changes: \(status)")
            }
        }
    }

    func stopObserving() {
        guard let listener else { return }
        for var address in Self.observedAddresses {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                listenerQueue,
                listener
            )
        }
        self.listener = nil
    }

    deinit {
        stopObserving()
    }

    private func hasInputStreams(_ identifier: AudioDeviceID) throws -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(identifier, &address, 0, nil, &size))
        return size >= UInt32(MemoryLayout<AudioStreamID>.size)
    }

    private func stringProperty(
        _ selector: AudioObjectPropertySelector,
        on identifier: AudioObjectID
    ) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(identifier, &address, 0, nil, &size, &value))
        guard let value else { throw AudioDeviceProviderError.coreAudio(kAudioHardwareUnspecifiedError) }
        return value.takeRetainedValue() as String
    }

    private func check(_ status: OSStatus) throws {
        guard status == noErr else { throw AudioDeviceProviderError.coreAudio(status) }
    }

    private static let observedAddresses = [
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        ),
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    ]
}

struct AudioInputResolution: Equatable {
    let device: AudioInputDevice
    let usedFallback: Bool

    static func resolve(
        preference: MicrophonePreference?,
        devices: [AudioInputDevice],
        defaultDeviceID: AudioDeviceID
    ) -> AudioInputResolution? {
        if let preference, let preferred = devices.first(where: { $0.uid == preference.uid }) {
            return AudioInputResolution(device: preferred, usedFallback: false)
        }
        guard let fallback = devices.first(where: { $0.deviceID == defaultDeviceID }) ?? devices.first else {
            return nil
        }
        return AudioInputResolution(device: fallback, usedFallback: preference != nil)
    }
}

struct ActiveAudioInputSelection: Equatable {
    let device: AudioInputDevice
    let followsSystemDefault: Bool

    init(preference: MicrophonePreference?, resolution: AudioInputResolution) {
        device = resolution.device
        followsSystemDefault = preference == nil || resolution.usedFallback
    }

    var requiresExplicitDeviceConfiguration: Bool {
        !followsSystemDefault
    }

    func matchesCurrentRoute(
        devices: [AudioInputDevice],
        defaultDeviceID: AudioDeviceID,
        audioUnitDeviceID: AudioDeviceID?
    ) -> Bool {
        if followsSystemDefault {
            return devices.first(where: { $0.deviceID == defaultDeviceID })?.uid == device.uid
        }
        return devices.contains(where: {
            $0.uid == device.uid && $0.deviceID == audioUnitDeviceID
        })
    }
}

@MainActor
final class AudioInputDeviceCatalog: ObservableObject {
    @Published private(set) var devices: [AudioInputDevice] = []
    @Published private(set) var defaultDeviceID: AudioDeviceID = kAudioObjectUnknown
    @Published private(set) var lastError: String?

    private let provider: any AudioInputDeviceProviding

    init(provider: any AudioInputDeviceProviding = CoreAudioInputDeviceProvider()) {
        self.provider = provider
        refresh()
        provider.startObserving { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit {
        provider.stopObserving()
    }

    var defaultDevice: AudioInputDevice? {
        devices.first(where: { $0.deviceID == defaultDeviceID })
    }

    func device(withUID uid: String) -> AudioInputDevice? {
        devices.first(where: { $0.uid == uid })
    }

    func resolution(for preference: MicrophonePreference?) -> AudioInputResolution? {
        .resolve(preference: preference, devices: devices, defaultDeviceID: defaultDeviceID)
    }

    func refresh() {
        do {
            let devices = try provider.inputDevices()
            let defaultDeviceID = try provider.defaultInputDeviceID()
            self.devices = devices
            self.defaultDeviceID = defaultDeviceID
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
