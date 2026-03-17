import Foundation

// MARK: - Событие звука

enum SoundEvent: String, Sendable {
    case recordingStarted
    case recordingFinished
    case error
}

// MARK: - Протокол (для DI и тестов)

protocol SoundPlaying: Sendable {
    func play(_ event: SoundEvent)
}

/// Нулевая реализация — не воспроизводит ничего
final class MuteSoundPlayer: SoundPlaying {
    func play(_ event: SoundEvent) {}
}
