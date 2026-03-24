import Foundation
import SwiftData

// MARK: - Имена событий аналитики (§3 metrics-spec)

enum AnalyticsEventName: String, CaseIterable {
    case dictationStarted = "dictation_started"
    case dictationCancelled = "dictation_cancelled"
    case dictationStopped = "dictation_stopped"
    case sttCompleted = "stt_completed"
    case sttFailed = "stt_failed"
    case normalizationCompleted = "normalization_completed"
    case normalizationFailed = "normalization_failed"
    case insertionStarted = "insertion_started"
    case insertionSucceeded = "insertion_succeeded"
    case insertionFailed = "insertion_failed"
    case manualEditDetected = "manual_edit_detected"
    case undoDetected = "undo_detected"
    case lastResultReinserted = "last_result_reinserted"
    case clipboardFallbackUsed = "clipboard_fallback_used"
    case snippetFallbackUsed = "snippet_fallback_used"
}

// MARK: - Стратегия вставки (§5.2 metrics-spec)

enum InsertionStrategy: String {
    case axSelectedText = "ax_selected_text"
    case axValueComposition = "ax_value_composition"
    case clipboard
    case none
}

// MARK: - Тип ошибки (§5.3 metrics-spec)

enum AnalyticsErrorType: String {
    case micPermission = "mic_permission"
    case audioCapture = "audio_capture"
    case sttTimeout = "stt_timeout"
    case sttApi = "stt_api"
    case normalizationApi = "normalization_api"
    case insertionNoFocus = "insertion_no_focus"
    case insertionUnsupportedField = "insertion_unsupported_field"
    case clipboardRestoreFailed = "clipboard_restore_failed"
    case workerNotRunning = "worker_not_running"
    case workerTimeout = "worker_timeout"
    case workerOom = "worker_oom"
    case workerCrash = "worker_crash"
    case workerSetup = "worker_setup"
    case pythonNotFound = "python_not_found"
    case unknown
}

// MARK: - Ключи metadata

enum AnalyticsMetadataKey {
    static let appBundleId = "app_bundle_id"
    static let textMode = "text_mode"
    static let language = "language"
    static let normalizationPath = "normalization_path"
    static let insertionStrategy = "insertion_strategy"
    static let audioDurationMs = "audio_duration_ms"
    static let rawTextLengthChars = "raw_text_length_chars"
    static let cleanTextLengthChars = "clean_text_length_chars"
    static let sttLatencyMs = "stt_latency_ms"
    static let normalizationLatencyMs = "normalization_latency_ms"
    static let insertionLatencyMs = "insertion_latency_ms"
    static let e2eLatencyMs = "e2e_latency_ms"
    static let errorType = "error_type"
    static let fallbackUsed = "fallback_used"
}

// MARK: - SwiftData модель

@Model
final class AnalyticsEvent {
    var type: String
    var timestamp: Date
    var sessionId: UUID?
    var metadata: [String: String]

    init(
        type: String,
        timestamp: Date = Date(),
        sessionId: UUID? = nil,
        metadata: [String: String] = [:]
    ) {
        self.type = type
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.metadata = metadata
    }
}
