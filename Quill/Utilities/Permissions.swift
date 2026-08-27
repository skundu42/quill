import ApplicationServices
import AVFoundation
import Foundation

enum Permissions {
    static var hasAccessibilityAccess: Bool {
        AXIsProcessTrusted() || CGPreflightPostEventAccess()
    }

    @discardableResult
    static func requestAccessibilityAccess() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let axGranted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        return axGranted || CGRequestPostEventAccess()
    }

    static var microphoneStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static func requestMicrophoneAccess() async -> Bool {
        switch microphoneStatus {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted: false
        @unknown default: false
        }
    }
}
