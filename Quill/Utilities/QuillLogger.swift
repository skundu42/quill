import OSLog

enum QuillLogger {
    static let app = Logger(subsystem: "com.quill.voice", category: "app")
    static let audio = Logger(subsystem: "com.quill.voice", category: "audio")
    static let network = Logger(subsystem: "com.quill.voice", category: "network")
    static let insertion = Logger(subsystem: "com.quill.voice", category: "insertion")
}
