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
            return "Нет интернета"
        case .timedOut:
            return "Сервер не отвечает"
        case .cannotFindHost, .cannotConnectToHost:
            return "Сервер недоступен"
        case .secureConnectionFailed:
            return "Ошибка SSL-соединения"
        default:
            return "Ошибка сети"
        }
    }

    private static func pipelineMessage(_ error: PipelineError) -> String {
        switch error {
        case .cancelled:
            return "Отменено"
        case .sttFailed(let detail):
            return "Ошибка распознавания: \(detail)"
        case .audioCaptureFailed:
            return "Ошибка микрофона"
        }
    }

    private static func sttMessage(_ error: STTError) -> String {
        switch error {
        case .noAudioData:
            return "Нет аудио"
        case .noResult:
            return "Не удалось распознать"
        case .connectionFailed:
            return "Распознавание недоступно"
        case .recognitionFailed:
            return "Ошибка распознавания"
        }
    }

    private static func llmMessage(_ error: LLMError) -> String {
        switch error {
        case .networkError:
            return "Ошибка сети"
        case .invalidResponse:
            return "Ошибка ответа сервера"
        case .parsingFailed:
            return "Ошибка обработки ответа"
        case .rateLimited:
            return "Слишком много запросов"
        case .serverError:
            return "Ошибка сервера"
        case .timeout:
            return "Сервер не отвечает"
        }
    }

    private static func audioMessage(_ error: AudioCaptureError) -> String {
        switch error {
        case .microphoneNotAvailable:
            return "Микрофон не найден"
        case .permissionDenied:
            return "Нет доступа к микрофону"
        case .engineStartFailed:
            return "Ошибка микрофона"
        case .alreadyRecording:
            return "Уже записываю"
        case .notRecording:
            return "Запись не активна"
        }
    }

    private static func workerMessage(_ error: WorkerError) -> String {
        switch error {
        case .notRunning:
            return "Распознавание недоступно"
        case .loadingModel:
            return "Загружаю модель…"
        case .timeout:
            return "Попробуйте ещё раз"
        case .oom:
            return "Мало памяти — закройте приложения"
        case .fileNotFound:
            return "Ошибка распознавания"
        case .internalError:
            return "Ошибка распознавания"
        case .connectionRefused:
            return "Распознавание недоступно"
        case .invalidResponse:
            return "Ошибка распознавания"
        case .maxRetriesExceeded:
            return "Перезапустите Говорун"
        case .pythonNotFound:
            return "Внутренняя ошибка. Переустановите Говоруна"
        case .setupFailed:
            return "Не смог подготовиться…"
        }
    }

    private static func insertionMessage(_ error: TextInsertionError) -> String {
        switch error {
        case .allStrategiesFailed:
            return "Не удалось вставить текст"
        }
    }

    // MARK: - WorkerState.error(String) → UX

    /// Маппинг сырых строк из WorkerState.error → понятные сообщения.
    /// Используется в Settings/Onboarding, где state содержит String, а не typed Error.
    static func humanReadable(_ raw: String) -> String {
        let mapped: String?
        if raw.contains("упал") || raw.contains("Не удалось запустить") { mapped = "Не удалось запустить распознавание" }
        else if raw.contains("setup.sh") { mapped = "Ошибка подготовки" }
        else if raw.lowercased().contains("python") { mapped = "Внутренняя ошибка. Переустановите Говоруна" }
        else if raw.contains("Таймаут") { mapped = "Загрузка прервалась" }
        else if raw.contains("VERSION") { mapped = "Обновите приложение" }
        else if raw.contains("отменена") { mapped = nil }
        else { mapped = nil }

        if let mapped {
            print("[Govorun] Ошибка worker: \(raw) → UI: \(mapped)")
            return mapped
        }
        return raw
    }

}
