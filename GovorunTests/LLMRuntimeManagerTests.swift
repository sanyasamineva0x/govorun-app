@testable import Govorun
import XCTest

final class LLMRuntimeManagerTests: XCTestCase {
    func test_initialState_isNotStarted() {
        let manager = LLMRuntimeManager()
        XCTAssertEqual(manager.state, .notStarted)
        XCTAssertFalse(manager.isReady)
    }

    func test_start_withExternalEndpoint_setsDisabledWithoutLaunch() async throws {
        let executablePath = try makeExecutableFile()
        let modelPath = try makeModelFile()
        let recorder = LaunchRecorder()

        let manager = makeManager(
            configuration: LocalLLMRuntimeConfiguration(
                baseURLString: "https://example.com/v1",
                modelAlias: "gigachat-gguf",
                modelPath: modelPath,
                runtimeBinaryPath: executablePath
            ),
            recorder: recorder,
            probe: ProbeStub()
        )

        try await manager.start()

        XCTAssertEqual(manager.state, .disabled)
        XCTAssertEqual(recorder.requests(), [])
    }

    func test_start_withoutModelPath_setsDisabledWithoutLaunch() async throws {
        let recorder = LaunchRecorder()
        let manager = makeManager(
            configuration: LocalLLMRuntimeConfiguration(
                baseURLString: "http://127.0.0.1:8080/v1",
                modelAlias: "gigachat-gguf"
            ),
            recorder: recorder,
            probe: ProbeStub()
        )

        try await manager.start()

        XCTAssertEqual(manager.state, .disabled)
        XCTAssertEqual(recorder.requests(), [])
    }

    func test_start_launchesProcessAndBecomesReady() async throws {
        let executablePath = try makeExecutableFile()
        let modelPath = try makeModelFile()
        let recorder = LaunchRecorder()
        let probe = ProbeStub(failuresBeforeSuccess: 2)

        let manager = makeManager(
            configuration: LocalLLMRuntimeConfiguration(
                baseURLString: "http://127.0.0.1:8080/v1",
                modelAlias: "gigachat-gguf",
                modelPath: modelPath,
                runtimeBinaryPath: executablePath,
                contextSize: 8_192,
                gpuLayers: 42
            ),
            recorder: recorder,
            probe: probe
        )

        try await manager.start()

        XCTAssertEqual(manager.state, .ready)

        let requests = recorder.requests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].executablePath, executablePath)
        XCTAssertEqual(
            requests[0].arguments,
            [
                "--host", "127.0.0.1",
                "--port", "8080",
                "--model", modelPath,
                "--alias", "gigachat-gguf",
                "--ctx-size", "8192",
                "--n-gpu-layers", "42",
            ]
        )

        let probeCallCount = await probe.snapshotCallCount()
        XCTAssertEqual(probeCallCount, 3)
    }

    func test_updateConfiguration_restartsRunningProcess() async throws {
        let executablePath = try makeExecutableFile()
        let firstModelPath = try makeModelFile()
        let secondModelPath = try makeModelFile()
        let recorder = LaunchRecorder()
        let probe = ProbeStub()

        let manager = makeManager(
            configuration: LocalLLMRuntimeConfiguration(
                baseURLString: "http://127.0.0.1:8080/v1",
                modelAlias: "gigachat-gguf",
                modelPath: firstModelPath,
                runtimeBinaryPath: executablePath
            ),
            recorder: recorder,
            probe: probe
        )

        try await manager.start()
        let firstProcess = try XCTUnwrap(recorder.process(at: 0))

        try await manager.updateConfiguration(
            LocalLLMRuntimeConfiguration(
                baseURLString: "http://127.0.0.1:8080/v1",
                modelAlias: "gigachat-super",
                modelPath: secondModelPath,
                runtimeBinaryPath: executablePath
            )
        )

        XCTAssertEqual(firstProcess.terminateCallCount, 1)
        XCTAssertEqual(manager.state, .ready)

        let requests = recorder.requests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests[1].arguments.contains("gigachat-super"))
        XCTAssertTrue(requests[1].arguments.contains(secondModelPath))
    }

    func test_stop_terminatesRunningProcess() async throws {
        let executablePath = try makeExecutableFile()
        let modelPath = try makeModelFile()
        let recorder = LaunchRecorder()
        let probe = ProbeStub()

        let manager = makeManager(
            configuration: LocalLLMRuntimeConfiguration(
                baseURLString: "http://127.0.0.1:8080/v1",
                modelAlias: "gigachat-gguf",
                modelPath: modelPath,
                runtimeBinaryPath: executablePath
            ),
            recorder: recorder,
            probe: probe
        )

        try await manager.start()
        let process = try XCTUnwrap(recorder.process(at: 0))

        manager.stop()

        XCTAssertEqual(process.terminateCallCount, 1)
        XCTAssertEqual(manager.state, .notStarted)
    }

    func test_processExit_afterReady_setsErrorState() async throws {
        let executablePath = try makeExecutableFile()
        let modelPath = try makeModelFile()
        let recorder = LaunchRecorder()
        let probe = ProbeStub()

        let manager = makeManager(
            configuration: LocalLLMRuntimeConfiguration(
                baseURLString: "http://127.0.0.1:8080/v1",
                modelAlias: "gigachat-gguf",
                modelPath: modelPath,
                runtimeBinaryPath: executablePath
            ),
            recorder: recorder,
            probe: probe
        )

        try await manager.start()
        recorder.simulateExit(at: 0, status: 137)

        XCTAssertEqual(manager.state, .error("LLM runtime завершился с кодом 137"))
    }

    private func makeManager(
        configuration: LocalLLMRuntimeConfiguration,
        recorder: LaunchRecorder,
        probe: ProbeStub
    ) -> LLMRuntimeManager {
        LLMRuntimeManager(
            configuration: configuration,
            launchProcess: { request, onTerminate in
                recorder.record(request: request, onTerminate: onTerminate)
            },
            probeBackend: { configuration in
                try await probe.probe(configuration)
            },
            sleep: { _ in }
        )
    }

    private func makeExecutableFile() throws -> String {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("govorun-llama-server-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    private func makeModelFile() throws -> String {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("govorun-gigachat-\(UUID().uuidString).gguf")
        FileManager.default.createFile(atPath: path, contents: Data("gguf".utf8))
        return path
    }
}

private final class LaunchRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requestsStorage: [LLMRuntimeLaunchRequest] = []
    private var processes: [MockLLMRuntimeProcess] = []
    private var terminationHandlers: [@Sendable (Int32) -> Void] = []

    func record(
        request: LLMRuntimeLaunchRequest,
        onTerminate: @escaping @Sendable (Int32) -> Void
    ) -> MockLLMRuntimeProcess {
        let process = MockLLMRuntimeProcess()
        lock.lock()
        requestsStorage.append(request)
        processes.append(process)
        terminationHandlers.append(onTerminate)
        lock.unlock()
        return process
    }

    func requests() -> [LLMRuntimeLaunchRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requestsStorage
    }

    func process(at index: Int) -> MockLLMRuntimeProcess? {
        lock.lock()
        defer { lock.unlock() }
        guard processes.indices.contains(index) else { return nil }
        return processes[index]
    }

    func simulateExit(at index: Int, status: Int32) {
        let process: MockLLMRuntimeProcess?
        let handler: (@Sendable (Int32) -> Void)?

        lock.lock()
        if processes.indices.contains(index), terminationHandlers.indices.contains(index) {
            process = processes[index]
            handler = terminationHandlers[index]
        } else {
            process = nil
            handler = nil
        }
        lock.unlock()

        process?.markStopped()
        handler?(status)
    }
}

private actor ProbeStub {
    private var failuresBeforeSuccess: Int
    private var callCount = 0

    init(failuresBeforeSuccess: Int = 0) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
    }

    func probe(_: LocalLLMRuntimeConfiguration) throws {
        callCount += 1
        if failuresBeforeSuccess > 0 {
            failuresBeforeSuccess -= 1
            throw LLMRuntimeError.healthcheckFailed("runtime ещё не готов")
        }
    }

    func snapshotCallCount() -> Int {
        callCount
    }
}

private final class MockLLMRuntimeProcess: LLMRuntimeProcessControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var running = true
    private(set) var terminateCallCount = 0

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    func terminate() {
        lock.lock()
        terminateCallCount += 1
        running = false
        lock.unlock()
    }

    func markStopped() {
        lock.lock()
        running = false
        lock.unlock()
    }
}
