import Foundation

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var phase: DictationPhase = .idle
    @Published var interimTranscript = ""
    @Published var lastTranscript = ""
    @Published var lastError: String?
    @Published var audioLevel = 0.0

    private init() {}

    func resetTranscript() {
        interimTranscript = ""
        lastError = nil
        audioLevel = 0
    }
}
