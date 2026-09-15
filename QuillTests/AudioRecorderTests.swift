import AudioToolbox
import AVFoundation
import CoreAudio
import XCTest
@testable import Quill

final class AudioRecorderTests: XCTestCase {
    func testConverterPreservesSpeechOnSecondStereoChannel() throws {
        let inputFormat = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        ))
        let converter = try AudioRecorder.makeConverter(from: inputFormat)
        let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 1_024))
        input.frameLength = 1_024
        let channels = try XCTUnwrap(input.floatChannelData)
        for frame in 0..<Int(input.frameLength) {
            channels[0][frame] = 0
            channels[1][frame] = 0.5
        }
        let output = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: 343))
        var suppliedInput = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outputStatus in
            outputStatus.pointee = suppliedInput ? .noDataNow : .haveData
            defer { suppliedInput = true }
            return suppliedInput ? nil : input
        }

        XCTAssertNotEqual(status, .error)
        XCTAssertNil(error)
        XCTAssertGreaterThan(output.frameLength, 0)
        let samples = try XCTUnwrap(output.int16ChannelData).pointee
        XCTAssertTrue(UnsafeBufferPointer(start: samples, count: Int(output.frameLength)).contains { $0 != 0 })
    }

    func testPreparingDefaultAndFallbackReplacesThePreviousDevice() throws {
        let hardware = CoreAudioInputDeviceProvider()
        let devices = try hardware.inputDevices()
        let defaultID = try hardware.defaultInputDeviceID()
        guard let defaultDevice = devices.first(where: { $0.deviceID == defaultID }),
              let alternate = devices.first(where: { $0.deviceID != defaultID }) else {
            throw XCTSkip("This route integration check requires two available input devices.")
        }
        let provider = FakeAudioInputDeviceProvider(devices: devices, defaultDeviceID: defaultID)
        let engine = AVAudioEngine()
        let recorder = AudioRecorder(deviceProvider: provider, engine: engine)
        let preference = MicrophonePreference(uid: alternate.uid, name: alternate.name)
        let audioUnit = try XCTUnwrap(engine.inputNode.audioUnit)

        func currentDeviceID() throws -> AudioDeviceID {
            var identifier = AudioDeviceID(kAudioObjectUnknown)
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            let status = AudioUnitGetProperty(
                audioUnit, kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global, 0, &identifier, &size
            )
            XCTAssertEqual(status, noErr)
            return identifier
        }

        try recorder.prewarm(microphone: preference)
        XCTAssertEqual(try currentDeviceID(), alternate.deviceID)

        try recorder.prewarm(microphone: nil)
        XCTAssertEqual(try currentDeviceID(), defaultID)

        provider.defaultDeviceID = alternate.deviceID
        try recorder.prewarm(microphone: nil)
        XCTAssertEqual(try currentDeviceID(), alternate.deviceID)

        provider.devices = [defaultDevice]
        provider.defaultDeviceID = defaultID
        XCTAssertTrue(try recorder.prewarm(microphone: preference).usedFallback)
        XCTAssertEqual(try currentDeviceID(), defaultID)
    }
}
