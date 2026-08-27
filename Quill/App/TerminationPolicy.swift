struct TerminationPolicy {
    private var statusMenuQuitRequested = false

    mutating func requestStatusMenuQuit() {
        statusMenuQuitRequested = true
    }

    func shouldTerminate(updaterIsRelaunching: Bool) -> Bool {
        statusMenuQuitRequested || updaterIsRelaunching
    }
}
