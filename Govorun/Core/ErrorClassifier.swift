import Foundation

// MARK: - Классификация ошибок для аналитики

enum ErrorClassifier {
    static func classify(_ error: Error) -> AnalyticsErrorType {
        switch error {
        case let audio as AudioCaptureError:
            classifyAudioError(audio)

        case let stt as STTError:
            classifySTTError(stt)

        case is LLMError:
            .normalizationApi

        case let pipeline as PipelineError:
            classifyPipelineError(pipeline)

        case let workerError as WorkerError:
            classifyWorkerError(workerError)

        case is TextInsertionError:
            .insertionNoFocus

        default:
            .unknown
        }
    }

    // MARK: - Private

    private static func classifyAudioError(_ error: AudioCaptureError) -> AnalyticsErrorType {
        switch error {
        case .permissionDenied:
            .micPermission
        case .microphoneNotAvailable, .engineStartFailed, .alreadyRecording, .notRecording:
            .audioCapture
        }
    }

    private static func classifySTTError(_ error: STTError) -> AnalyticsErrorType {
        switch error {
        case .connectionFailed:
            .sttTimeout
        case .noAudioData, .recognitionFailed, .noResult:
            .sttApi
        }
    }

    private static func classifyWorkerError(_ error: WorkerError) -> AnalyticsErrorType {
        switch error {
        case .notRunning, .connectionRefused:
            .workerNotRunning
        case .timeout:
            .workerTimeout
        case .oom:
            .workerOom
        case .maxRetriesExceeded:
            .workerCrash
        case .pythonNotFound:
            .pythonNotFound
        case .setupFailed, .loadingModel, .invalidResponse, .fileNotFound, .internalError:
            .workerSetup
        }
    }

    private static func classifyPipelineError(_ error: PipelineError) -> AnalyticsErrorType {
        switch error {
        case .sttFailed:
            .sttApi
        case .audioCaptureFailed:
            .audioCapture
        case .cancelled:
            .unknown
        }
    }
}
