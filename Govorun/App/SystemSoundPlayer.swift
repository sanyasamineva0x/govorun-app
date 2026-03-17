import AppKit

/// Воспроизведение фирменных звуков из бандла приложения
final class SystemSoundPlayer: SoundPlaying, @unchecked Sendable {

    private let lock = NSLock()
    private var _enabled: Bool
    private let defaults: UserDefaults

    /// Предзагруженные звуки (инициализируются лениво при первом play)
    private var cachedSounds: [SoundEvent: NSSound] = [:]

    var isEnabled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _enabled }
        set { lock.lock(); defer { lock.unlock() }; _enabled = newValue }
    }

    init(enabled: Bool = true, defaults: UserDefaults = .standard) {
        self._enabled = enabled
        self.defaults = defaults
    }

    func play(_ event: SoundEvent) {
        // Читаем актуальное значение из UserDefaults — тогл в настройках применяется сразу
        let currentEnabled = defaults.bool(forKey: "soundEnabled")
        guard currentEnabled else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let sound = self.sound(for: event)
            sound?.stop() // прервать предыдущее воспроизведение
            sound?.play()
        }
    }

    // MARK: - Private

    private func sound(for event: SoundEvent) -> NSSound? {
        lock.lock()
        if let cached = cachedSounds[event] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let fileName: String
        switch event {
        case .recordingStarted:
            fileName = "recording_started"
        case .recordingFinished:
            fileName = "recording_finished"
        case .error:
            fileName = "error"
        }

        guard let url = Bundle.main.url(forResource: fileName, withExtension: "aiff") else {
            // Fallback на системные звуки если файл не найден
            let fallbackName: String
            switch event {
            case .recordingStarted: fallbackName = "Tink"
            case .recordingFinished: fallbackName = "Pop"
            case .error: fallbackName = "Basso"
            }
            return NSSound(named: NSSound.Name(fallbackName))
        }

        let sound = NSSound(contentsOf: url, byReference: true)
        lock.lock()
        cachedSounds[event] = sound
        lock.unlock()
        return sound
    }
}
