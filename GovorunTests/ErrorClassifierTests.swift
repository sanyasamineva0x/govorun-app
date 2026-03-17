import XCTest
@testable import Govorun

final class ErrorClassifierTests: XCTestCase {

    // MARK: - AudioCaptureError

    func test_permission_denied_maps_to_mic_permission() {
        let result = ErrorClassifier.classify(AudioCaptureError.permissionDenied)
        XCTAssertEqual(result, .micPermission)
    }

    func test_microphone_not_available_maps_to_audio_capture() {
        let result = ErrorClassifier.classify(AudioCaptureError.microphoneNotAvailable)
        XCTAssertEqual(result, .audioCapture)
    }

    func test_engine_start_failed_maps_to_audio_capture() {
        let result = ErrorClassifier.classify(AudioCaptureError.engineStartFailed(underlying: "test"))
        XCTAssertEqual(result, .audioCapture)
    }

    func test_already_recording_maps_to_audio_capture() {
        let result = ErrorClassifier.classify(AudioCaptureError.alreadyRecording)
        XCTAssertEqual(result, .audioCapture)
    }

    func test_not_recording_maps_to_audio_capture() {
        let result = ErrorClassifier.classify(AudioCaptureError.notRecording)
        XCTAssertEqual(result, .audioCapture)
    }

    // MARK: - STTError

    func test_connection_failed_maps_to_stt_timeout() {
        let result = ErrorClassifier.classify(STTError.connectionFailed("timeout"))
        XCTAssertEqual(result, .sttTimeout)
    }

    func test_no_audio_data_maps_to_stt_api() {
        let result = ErrorClassifier.classify(STTError.noAudioData)
        XCTAssertEqual(result, .sttApi)
    }

    func test_recognition_failed_maps_to_stt_api() {
        let result = ErrorClassifier.classify(STTError.recognitionFailed("error"))
        XCTAssertEqual(result, .sttApi)
    }

    func test_no_result_maps_to_stt_api() {
        let result = ErrorClassifier.classify(STTError.noResult)
        XCTAssertEqual(result, .sttApi)
    }

    // MARK: - LLMError

    func test_llm_network_error_maps_to_normalization_api() {
        let result = ErrorClassifier.classify(LLMError.networkError("test"))
        XCTAssertEqual(result, .normalizationApi)
    }

    func test_llm_parsing_failed_maps_to_normalization_api() {
        let result = ErrorClassifier.classify(LLMError.parsingFailed)
        XCTAssertEqual(result, .normalizationApi)
    }

    func test_llm_rate_limited_maps_to_normalization_api() {
        let result = ErrorClassifier.classify(LLMError.rateLimited)
        XCTAssertEqual(result, .normalizationApi)
    }

    func test_llm_timeout_maps_to_normalization_api() {
        let result = ErrorClassifier.classify(LLMError.timeout)
        XCTAssertEqual(result, .normalizationApi)
    }

    func test_llm_server_error_maps_to_normalization_api() {
        let result = ErrorClassifier.classify(LLMError.serverError(statusCode: 500))
        XCTAssertEqual(result, .normalizationApi)
    }

    func test_llm_invalid_response_maps_to_normalization_api() {
        let result = ErrorClassifier.classify(LLMError.invalidResponse(statusCode: 400))
        XCTAssertEqual(result, .normalizationApi)
    }

    // MARK: - PipelineError

    func test_pipeline_stt_failed_maps_to_stt_api() {
        let result = ErrorClassifier.classify(PipelineError.sttFailed("test"))
        XCTAssertEqual(result, .sttApi)
    }

    func test_pipeline_audio_capture_failed_maps_to_audio_capture() {
        let result = ErrorClassifier.classify(PipelineError.audioCaptureFailed("test"))
        XCTAssertEqual(result, .audioCapture)
    }

    func test_pipeline_cancelled_maps_to_unknown() {
        let result = ErrorClassifier.classify(PipelineError.cancelled)
        XCTAssertEqual(result, .unknown)
    }

    // MARK: - TextInsertionError

    func test_text_insertion_error_maps_to_insertion_no_focus() {
        let result = ErrorClassifier.classify(TextInsertionError.allStrategiesFailed)
        XCTAssertEqual(result, .insertionNoFocus)
    }

    // MARK: - WorkerError

    func test_worker_not_running_maps_to_worker_not_running() {
        let result = ErrorClassifier.classify(WorkerError.notRunning)
        XCTAssertEqual(result, .workerNotRunning)
    }

    func test_worker_connection_refused_maps_to_worker_not_running() {
        let result = ErrorClassifier.classify(WorkerError.connectionRefused)
        XCTAssertEqual(result, .workerNotRunning)
    }

    func test_worker_timeout_maps_to_worker_timeout() {
        let result = ErrorClassifier.classify(WorkerError.timeout)
        XCTAssertEqual(result, .workerTimeout)
    }

    func test_worker_oom_maps_to_worker_oom() {
        let result = ErrorClassifier.classify(WorkerError.oom)
        XCTAssertEqual(result, .workerOom)
    }

    func test_worker_max_retries_maps_to_worker_crash() {
        let result = ErrorClassifier.classify(WorkerError.maxRetriesExceeded)
        XCTAssertEqual(result, .workerCrash)
    }

    func test_worker_python_not_found_maps_to_python_not_found() {
        let result = ErrorClassifier.classify(WorkerError.pythonNotFound)
        XCTAssertEqual(result, .pythonNotFound)
    }

    func test_worker_setup_failed_maps_to_worker_setup() {
        let result = ErrorClassifier.classify(WorkerError.setupFailed("pip error"))
        XCTAssertEqual(result, .workerSetup)
    }

    func test_worker_internal_error_maps_to_worker_setup() {
        let result = ErrorClassifier.classify(WorkerError.internalError("crash"))
        XCTAssertEqual(result, .workerSetup)
    }

    // MARK: - Unknown

    func test_unknown_error_maps_to_unknown() {
        struct SomeRandomError: Error {}
        let result = ErrorClassifier.classify(SomeRandomError())
        XCTAssertEqual(result, .unknown)
    }
}
