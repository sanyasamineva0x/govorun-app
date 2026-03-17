import Foundation

// MARK: - Классификация ошибок для аналитики

enum ErrorClassifier {

    static func classify(_ error: Error) -> AnalyticsErrorType {
        switch error {
        case let audio as AudioCaptureError:
            return classifyAudioError(audio)

        case let stt as STTError:
            return classifySTTError(stt)

        case is LLMError:
            return .normalizationApi

        case let pipeline as PipelineError:
            return classifyPipelineError(pipeline)

        case let workerError as WorkerError:
            return classifyWorkerError(workerError)

        case is TextInsertionError:
            return .insertionNoFocus

        default:
            return .unknown
        }
    }

    // MARK: - Private

    private static func classifyAudioError(_ error: AudioCaptureError) -> AnalyticsErrorType {
        switch error {
        case .permissionDenied:
            return .micPermission
        case .microphoneNotAvailable, .engineStartFailed, .alreadyRecording, .notRecording:
            return .audioCapture
        }
    }

    private static func classifySTTError(_ error: STTError) -> AnalyticsErrorType {
        switch error {
        case .connectionFailed:
            return .sttTimeout
        case .noAudioData, .recognitionFailed, .noResult:
            return .sttApi
        }
    }

    private static func classifyWorkerError(_ error: WorkerError) -> AnalyticsErrorType {
        switch error {
        case .notRunning, .connectionRefused:
            return .workerNotRunning
        case .timeout:
            return .workerTimeout
        case .oom:
            return .workerOom
        case .maxRetriesExceeded:
            return .workerCrash
        case .pythonNotFound:
            return .pythonNotFound
        case .setupFailed, .loadingModel, .invalidResponse, .fileNotFound, .internalError:
            return .workerSetup
        }
    }

    private static func classifyPipelineError(_ error: PipelineError) -> AnalyticsErrorType {
        switch error {
        case .sttFailed:
            return .sttApi
        case .audioCaptureFailed:
            return .audioCapture
        case .cancelled:
            return .unknown
        }
    }
}
