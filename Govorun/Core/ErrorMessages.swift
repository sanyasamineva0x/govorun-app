import Foundation

/// Русские сообщения об ошибках для пользователя (bottom bar, menu bar)
enum ErrorMessages {
    static func userFacing(for error: Error) -> String {
        // Сетевые ошибки
        if let urlError = error as? URLError {
            return urlErrorMessage(urlError)
        }

        // Pipeline
        if let pipelineError = error as? PipelineError {
            return pipelineMessage(pipelineError)
        }

        // STT
        if let sttError = error as? STTError {
            return sttMessage(sttError)
        }

        // LLM
        if let llmError = error as? LLMError {
            return llmMessage(llmError)
        }

        // Audio
        if let audioError = error as? AudioCaptureError {
            return audioMessage(audioError)
        }

        // Worker
        if let workerError = error as? WorkerError {
            return workerMessage(workerError)
        }

        // Text insertion
        if let insertError = error as? TextInsertionError {
            return insertionMessage(insertError)
        }

        return "Ошибка: \(error.localizedDescription)"
    }

    // MARK: - Private

    private static func urlErrorMessage(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost:
            "Нет интернета"
        case .timedOut:
            "Сервер не отвечает"
        case .cannotFindHost, .cannotConnectToHost:
            "Сервер недоступен"
        case .secureConnectionFailed:
            "Ошибка SSL-соединения"
        default:
            "Ошибка сети"
        }
    }

    private static func pipelineMessage(_ error: PipelineError) -> String {
        switch error {
        case .cancelled:
            "Отменено"
        case .sttFailed(let detail):
            "Ошибка распознавания: \(detail)"
        case .audioCaptureFailed:
            "Ошибка микрофона"
        }
    }

    private static func sttMessage(_ error: STTError) -> String {
        switch error {
        case .noAudioData:
            "Нет аудио"
        case .noResult:
            "Не удалось распознать"
        case .connectionFailed:
            "Распознавание недоступно"
        case .recognitionFailed:
            "Ошибка распознавания"
        }
    }

    private static func llmMessage(_ error: LLMError) -> String {
        switch error {
        case .networkError:
            "Ошибка сети"
        case .invalidResponse:
            "Ошибка ответа сервера"
        case .parsingFailed:
            "Ошибка обработки ответа"
        case .rateLimited:
            "Слишком много запросов"
        case .serverError:
            "Ошибка сервера"
        case .timeout:
            "Сервер не отвечает"
        }
    }

    private static func audioMessage(_ error: AudioCaptureError) -> String {
        switch error {
        case .microphoneNotAvailable:
            "Микрофон не найден"
        case .permissionDenied:
            "Нет доступа к микрофону"
        case .engineStartFailed:
            "Ошибка микрофона"
        case .alreadyRecording:
            "Уже записываю"
        case .notRecording:
            "Запись не активна"
        }
    }

    private static func workerMessage(_ error: WorkerError) -> String {
        error.localizedDescription
    }

    private static func insertionMessage(_ error: TextInsertionError) -> String {
        switch error {
        case .allStrategiesFailed:
            "Не удалось вставить текст"
        }
    }

    // MARK: - WorkerState.error(String) → UX

    /// Маппинг сырых строк из WorkerState.error → понятные сообщения.
    /// Используется в Settings/Onboarding, где state содержит String, а не typed Error.
    static func humanReadable(_ raw: String) -> String {
        let mapped: String? = if raw.contains("упал") || raw.contains("Не удалось запустить") { "Не удалось запустить распознавание" }
        else if raw.contains("setup.sh") { "Ошибка подготовки" }
        else if raw.lowercased().contains("python") { "Внутренняя ошибка. Переустановите Говоруна" }
        else if raw.contains("Таймаут") { "Загрузка прервалась" }
        else if raw.contains("VERSION") { "Обновите приложение" }
        else if raw.contains("отменена") { nil }
        else { nil }

        if let mapped {
            print("[Govorun] Ошибка worker: \(raw) → UI: \(mapped)")
            return mapped
        }
        return raw
    }
}
