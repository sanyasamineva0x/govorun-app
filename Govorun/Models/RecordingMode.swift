enum RecordingMode: String, Codable, Sendable, CaseIterable {
    case pushToTalk
    case toggle

    var title: String {
        switch self {
        case .pushToTalk: "Push to Talk"
        case .toggle: "Toggle"
        }
    }

    var description: String {
        switch self {
        case .pushToTalk: "Удерживайте клавишу для записи, отпустите для остановки"
        case .toggle: "Нажмите для начала записи, нажмите ещё раз для остановки"
        }
    }
}
