// MARK: - Режим записи

enum RecordingMode: String, Codable, Sendable, CaseIterable {
    case pushToTalk
    case toggle

    static let `default`: RecordingMode = .pushToTalk

    var title: String {
        switch self {
        case .pushToTalk: "Push to Talk"
        case .toggle: "Toggle"
        }
    }

    var subtitle: String {
        switch self {
        case .pushToTalk: "Удерживайте клавишу для записи, отпустите для остановки"
        case .toggle: "Нажмите для начала записи, нажмите ещё раз для остановки"
        }
    }

    /// Текст-подсказка для StatusBar и WorkerStatusCard
    func hint(key: String) -> String {
        switch self {
        case .pushToTalk: "Зажмите \(key) и говорите"
        case .toggle: "Нажмите \(key) для записи"
        }
    }
}
