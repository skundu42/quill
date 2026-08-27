import CoreAudio
import XCTest
@testable import Quill

final class AudioInputDeviceTests: XCTestCase {
    private let builtIn = AudioInputDevice(deviceID: 10, uid: "built-in", name: "MacBook Microphone")
    private let studio = AudioInputDevice(deviceID: 20, uid: "studio", name: "Studio Mic")

    func testSelectedDeviceWinsWhenAvailable() {
        let resolution = AudioInputResolution.resolve(
            preference: MicrophonePreference(uid: studio.uid, name: studio.name),
            devices: [builtIn, studio],
            defaultDeviceID: builtIn.deviceID
        )

        XCTAssertEqual(resolution, AudioInputResolution(device: studio, usedFallback: false))
    }

    func testMissingPreferredDeviceFallsBackWithoutChangingPreference() {
        let preference = MicrophonePreference(uid: "missing", name: "Travel Mic")
        let resolution = AudioInputResolution.resolve(
            preference: preference,
            devices: [builtIn, studio],
            defaultDeviceID: builtIn.deviceID
        )

        XCTAssertEqual(resolution, AudioInputResolution(device: builtIn, usedFallback: true))
        XCTAssertEqual(preference.uid, "missing")
    }

    func testSystemDefaultUsesDefaultDevice() {
        let resolution = AudioInputResolution.resolve(
            preference: nil,
            devices: [studio, builtIn],
            defaultDeviceID: builtIn.deviceID
        )

        XCTAssertEqual(resolution, AudioInputResolution(device: builtIn, usedFallback: false))
    }

    func testNoInputsReturnsNil() {
        XCTAssertNil(AudioInputResolution.resolve(
            preference: nil,
            devices: [],
            defaultDeviceID: kAudioObjectUnknown
        ))
    }
}

@MainActor
final class AudioInputDeviceCatalogTests: XCTestCase {
    func testCatalogRefreshesWhenProviderReportsADeviceChange() async {
        let builtIn = AudioInputDevice(deviceID: 10, uid: "built-in", name: "MacBook Microphone")
        let studio = AudioInputDevice(deviceID: 20, uid: "studio", name: "Studio Mic")
        let provider = FakeAudioInputDeviceProvider(devices: [builtIn], defaultDeviceID: builtIn.deviceID)
        let catalog = AudioInputDeviceCatalog(provider: provider)
        XCTAssertEqual(catalog.devices, [builtIn])

        provider.devices = [builtIn, studio]
        provider.defaultDeviceID = studio.deviceID
        provider.reportChange()
        await Task.yield()

        XCTAssertEqual(catalog.devices, [builtIn, studio])
        XCTAssertEqual(catalog.defaultDevice, studio)
    }
}

private final class FakeAudioInputDeviceProvider: AudioInputDeviceProviding, @unchecked Sendable {
    var devices: [AudioInputDevice]
    var defaultDeviceID: AudioDeviceID
    private var handler: (@Sendable () -> Void)?

    init(devices: [AudioInputDevice], defaultDeviceID: AudioDeviceID) {
        self.devices = devices
        self.defaultDeviceID = defaultDeviceID
    }

    func inputDevices() throws -> [AudioInputDevice] { devices }
    func defaultInputDeviceID() throws -> AudioDeviceID { defaultDeviceID }
    func startObserving(_ handler: @escaping @Sendable () -> Void) { self.handler = handler }
    func stopObserving() { handler = nil }
    func reportChange() { handler?() }
}
