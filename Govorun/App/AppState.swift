import Cocoa
import Combine
import SwiftData

// MARK: - AppState: Composition Root

@MainActor
final class AppState: ObservableObject {

    private(set) var activationKeyMonitor: ActivationKeyMonitor
    let sessionManager: SessionManager
    let pipelineEngine: PipelineEngine
    let textInserter: TextInserterEngine
    let bottomBar: BottomBarController
    let audioCapture: AudioCapture
    let appContextEngine: AppContextEngine
    let soundPlayer: SoundPlaying
    let snippetEngine: SnippetEngine
    let analytics: AnalyticsEmitting
    let postInsertionMonitor: PostInsertionMonitoring
    let settings: SettingsStore
    let updaterService: UpdaterService?

    /// Python worker — управляет жизненным циклом процесса
    private let workerManager: ASRWorkerManaging?

    /// ModelContainer для reload сниппетов и usageCount
    private let modelContainer: ModelContainer?

    /// EventMonitoring (для recreateMonitor)
    private let eventMonitor: EventMonitoring?
    /// Текущая клавиша активации
    private var currentActivationKey: ActivationKey
    /// Отложенная клавиша (ждёт idle)
    private var pendingActivationKey: ActivationKey?
    /// Текущий режим записи
    private var currentRecordingMode: RecordingMode
    /// Отложенный режим записи (ждёт idle)
    private var pendingRecordingMode: RecordingMode?
    /// Подписка на изменения SettingsStore
    private var settingsCancellable: AnyCancellable?

    /// sessionId текущей диктовки (для привязки событий к сессии)
    private var currentSessionId: UUID?
    /// bundleId текущего приложения (для metadata событий)
    private var currentAppBundleId: String?
    private var currentAppContext: AppContext?

    /// Последний результат (для StatusBar)
    @Published private(set) var lastResult: PipelineResult?

    /// Состояние Python worker (для Cold start UI)
    @Published private(set) var workerState: WorkerState = .notStarted

    /// Флаг — приложение готово к работе
    @Published private(set) var isReady = false

    /// Мониторинг сети (нужен для первого скачивания модели)
    let networkMonitor = NetworkMonitor()

    private let audioCaptureDelegate: AudioCaptureBridge
    private let sessionManagerDelegate: SessionManagerBridge
    private var escMonitors: [Any] = []
    private var snippetsObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    /// Показывался ли хинт Accessibility в этой сессии (не спамим)
    private var accessibilityHintShown = false

    init(
        eventMonitor: EventMonitoring = NSEventMonitoring(),
        accessibility: AccessibilityProviding = SystemAccessibilityProvider(),
        clipboard: ClipboardProviding = SystemClipboardProvider(),
        workspace: WorkspaceProviding = NSWorkspaceProvider(),
        modeOverrides: AppModeOverriding = UserDefaultsAppModeOverrides(),
        soundPlayer: SoundPlaying = SystemSoundPlayer(),
        analytics: AnalyticsEmitting? = nil
    ) {
        let manager = ASRWorkerManager()
        self.workerManager = manager

        let stt: STTClient = LocalSTTClient(socketPath: manager.socketPath)
        let llm: LLMClient = PlaceholderLLMClient()
        let audio = AudioCapture()

        let snippetEngine = SnippetEngine()
        let container = AppModelContainer.shared
        self.modelContainer = container
        let context = ModelContext(container)
        let snippetStore = SnippetStore(modelContext: context)
        try? snippetStore.seedDefaultsIfNeeded()
        if let records = try? snippetStore.snippetRecords() {
            snippetEngine.updateSnippets(records)
        }
        self.snippetEngine = snippetEngine

        let settings = SettingsStore()
        self.settings = settings
        eventMonitor.activationKey = settings.activationKey
        eventMonitor.recordingMode = settings.recordingMode
        self.eventMonitor = eventMonitor
        self.currentActivationKey = settings.activationKey
        self.currentRecordingMode = settings.recordingMode

        self.audioCapture = audio
        self.pipelineEngine = PipelineEngine(
            audioCapture: audio,
            sttClient: stt,
            llmClient: llm,
            snippetEngine: snippetEngine
        )
        self.textInserter = TextInserterEngine(
            accessibility: accessibility,
            clipboard: clipboard
        )
        self.sessionManager = SessionManager()
        self.activationKeyMonitor = ActivationKeyMonitor(
            activationKey: settings.activationKey,
            recordingMode: settings.recordingMode,
            eventMonitor: eventMonitor
        )
        self.bottomBar = BottomBarController()
        self.audioCaptureDelegate = AudioCaptureBridge()
        self.sessionManagerDelegate = SessionManagerBridge()
        self.appContextEngine = AppContextEngine(
            workspace: workspace,
            modeOverrides: modeOverrides
        )
        self.soundPlayer = soundPlayer
        if let analytics {
            self.analytics = analytics
        } else {
            self.analytics = AnalyticsService(modelContainer: AppModelContainer.shared)
        }
        self.postInsertionMonitor = PostInsertionMonitor(
            focusedTextReader: SystemFocusedTextReader(),
            frontmostAppProvider: SystemFrontmostAppProvider()
        )
        self.updaterService = UpdaterService()

        wireActivationKeyMonitor()
        wireSessionManager()
        wireAudioCapture()
        wireSnippetNotifications()
        wireWorkerManager()
        wireSettingsChange()
        wireSleepNotification()
    }

    /// Тестовый init с инжектированными зависимостями
    init(
        activationKeyMonitor: ActivationKeyMonitor,
        sessionManager: SessionManager,
        pipelineEngine: PipelineEngine,
        textInserter: TextInserterEngine,
        bottomBar: BottomBarController,
        audioCapture: AudioCapture,
        appContextEngine: AppContextEngine? = nil,
        soundPlayer: SoundPlaying = MuteSoundPlayer(),
        modelContainer: ModelContainer? = nil,
        analytics: AnalyticsEmitting = NoOpAnalyticsService(),
        postInsertionMonitor: PostInsertionMonitoring? = nil,
        workerManager: ASRWorkerManaging? = nil,
        initialWorkerState: WorkerState = .ready,
        settings: SettingsStore = SettingsStore(),
        eventMonitor: EventMonitoring? = nil,
        updaterService: UpdaterService? = nil
    ) {
        self.workerManager = workerManager
        self.activationKeyMonitor = activationKeyMonitor
        self.sessionManager = sessionManager
        self.pipelineEngine = pipelineEngine
        self.textInserter = textInserter
        self.bottomBar = bottomBar
        self.audioCapture = audioCapture
        self.audioCaptureDelegate = AudioCaptureBridge()
        self.sessionManagerDelegate = SessionManagerBridge()
        self.appContextEngine = appContextEngine ?? AppContextEngine(
            workspace: NSWorkspaceProvider(),
            modeOverrides: UserDefaultsAppModeOverrides()
        )
        self.soundPlayer = soundPlayer
        self.snippetEngine = SnippetEngine()
        self.modelContainer = modelContainer
        self.analytics = analytics
        self.postInsertionMonitor = postInsertionMonitor ?? PostInsertionMonitor(
            focusedTextReader: SystemFocusedTextReader(),
            frontmostAppProvider: SystemFrontmostAppProvider()
        )
        self.settings = settings
        self.eventMonitor = eventMonitor
        self.currentActivationKey = settings.activationKey
        self.currentRecordingMode = settings.recordingMode
        self.updaterService = updaterService

        self.workerState = initialWorkerState

        wireActivationKeyMonitor()
        wireSessionManager()
        wireAudioCapture()
        wireSnippetNotifications()
        wireSettingsChange()
    }

    // MARK: - Worker State

    func updateWorkerState(_ state: WorkerState) {
        workerState = state
    }

    // MARK: - Start / Stop

    func start() {
        activationKeyMonitor.startMonitoring()
        isReady = true

        if let workerManager {
            // Если worker уже запущен (вручную или от предыдущего запуска) — проверить ping
            let socketPath = workerManager.socketPath
            if FileManager.default.fileExists(atPath: socketPath) && isWorkerAlive(socketPath: socketPath) {
                updateWorkerState(.ready)
                print("[Govorun] Worker alive (ping ok), пропускаю запуск")
            } else {
                // Проверить: если модель не скачана и нет сети — показать ошибку
                let modelManager = ModelManager()
                modelManager.checkModelStatus()
                if !modelManager.isModelDownloaded && !networkMonitor.isCurrentlyConnected {
                    updateWorkerState(.error("Нет интернета. Модель ещё не скачана."))
                    print("[Govorun] Нет сети, модель не скачана — worker не запускаю")
                    return
                }

                Task {
                    do {
                        try await workerManager.start()
                    } catch {
                        print("[Govorun] Worker не запустился: \(error)")
                        updateWorkerState(.error(error.localizedDescription))
                    }
                }
            }
        }
    }

    func stop() {
        activationKeyMonitor.stopMonitoring()
        stopEscMonitor()
        postInsertionMonitor.stopMonitoring()
        workerManager?.stop()
        if let snippetsObserver {
            NotificationCenter.default.removeObserver(snippetsObserver)
        }
        snippetsObserver = nil
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
        }
        sleepObserver = nil
        isReady = false
    }

    // MARK: - Cancel Worker Loading

    func cancelWorkerLoading() {
        workerManager?.stop()
        updateWorkerState(.error("Загрузка отменена"))
    }

    func retryWorkerLoading() {
        guard let workerManager else { return }
        updateWorkerState(.notStarted)
        Task {
            do {
                try await workerManager.start()
            } catch {
                print("[Govorun] Worker не запустился: \(error)")
                updateWorkerState(.error(error.localizedDescription))
            }
        }
    }

    // MARK: - Cancel (для Esc во время processing)

    func cancelProcessing() {
        let state = sessionManager.state
        guard state == .processing || state == .recording else { return }
        handleCancelled()
    }

    // MARK: - Snippet Sync

    func reloadSnippets() {
        guard let modelContainer else { return }
        let context = ModelContext(modelContainer)
        let store = SnippetStore(modelContext: context)
        if let records = try? store.snippetRecords() {
            snippetEngine.updateSnippets(records)
        }
    }

    private func incrementSnippetUsage(trigger: String) {
        guard let modelContainer else { return }
        let context = ModelContext(modelContainer)
        let store = SnippetStore(modelContext: context)
        do {
            try store.incrementUsage(trigger: trigger)
        } catch {
            print("[Govorun] Не удалось обновить usageCount для '\(trigger)': \(error)")
        }
    }

    // MARK: - Dictionary Sync

    private func loadDictionaryHints() -> (sttHints: [String], llmReplacements: [String: String]) {
        guard let modelContainer else {
            print("[Govorun] Dictionary: modelContainer не инициализирован, словарь пропущен")
            return ([], [:])
        }
        let context = ModelContext(modelContainer)
        let store = DictionaryStore(modelContext: context)
        do {
            let stt = try store.sttHints()
            let llm = try store.llmReplacements()
            if !stt.isEmpty {
                print("[Govorun] Dictionary: загружено \(stt.count) STT-хинтов, \(llm.count) LLM-замен")
            }
            return (stt, llm)
        } catch {
            print("[Govorun] Dictionary: ошибка загрузки — \(error.localizedDescription)")
            return ([], [:])
        }
    }

    // MARK: - Wiring

    private func wireActivationKeyMonitor() {
        activationKeyMonitor.onActivated = { [weak self] in
            Task { @MainActor [weak self] in self?.handleActivated() }
        }
        activationKeyMonitor.onDeactivated = { [weak self] in
            Task { @MainActor [weak self] in self?.handleDeactivated() }
        }
        activationKeyMonitor.onCancelled = { [weak self] in
            Task { @MainActor [weak self] in self?.handleCancelled() }
        }
        // CGEventTap reset во время toggle записи → деактивация
        if let nsMonitor = eventMonitor as? NSEventMonitoring {
            nsMonitor.onTapReset = { [weak self] in
                Task { @MainActor [weak self] in self?.handleCancelled() }
            }
        }
    }

    private func wireSettingsChange() {
        settingsCancellable = settings.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleSettingsChanged() }
        }
    }

    private func handleSettingsChanged() {
        let newKey = settings.activationKey
        let newMode = settings.recordingMode
        let keyChanged = newKey != currentActivationKey
        let modeChanged = newMode != currentRecordingMode

        guard keyChanged || modeChanged else { return }

        if sessionManager.state == .idle {
            recreateMonitor(key: newKey, mode: newMode)
        } else {
            if keyChanged { pendingActivationKey = newKey }
            if modeChanged { pendingRecordingMode = newMode }
        }
    }

    private func recreateMonitor(key: ActivationKey, mode: RecordingMode) {
        guard let eventMonitor else { return }
        activationKeyMonitor.stopMonitoring()
        eventMonitor.activationKey = key
        eventMonitor.recordingMode = mode
        activationKeyMonitor = ActivationKeyMonitor(
            activationKey: key,
            recordingMode: mode,
            eventMonitor: eventMonitor
        )
        wireActivationKeyMonitor()
        activationKeyMonitor.startMonitoring()
        currentActivationKey = key
        currentRecordingMode = mode
        pendingActivationKey = nil
        pendingRecordingMode = nil
    }

    fileprivate func applyPendingSettings() {
        let key = pendingActivationKey ?? currentActivationKey
        let mode = pendingRecordingMode ?? currentRecordingMode
        guard pendingActivationKey != nil || pendingRecordingMode != nil else { return }
        recreateMonitor(key: key, mode: mode)
    }

    /// Проверить что worker жив через ping по unix socket
    private func isWorkerAlive(socketPath: String) -> Bool {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }

        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 104) { dest in
                for (i, byte) in socketPath.utf8CString.enumerated() where i < 104 {
                    dest[i] = byte
                }
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else { return false }

        let pingData = Data("{\"cmd\":\"ping\"}".utf8)
        let sent = pingData.withUnsafeBytes { buf in
            Darwin.send(fd, buf.baseAddress!, buf.count, 0)
        }
        guard sent > 0 else { return false }
        Darwin.shutdown(fd, SHUT_WR)

        var buf = [UInt8](repeating: 0, count: 256)
        let received = Darwin.recv(fd, &buf, buf.count, 0)
        guard received > 0 else { return false }

        let response = String(bytes: buf[..<received], encoding: .utf8) ?? ""
        return response.contains("\"ok\"")
    }

    private func wireWorkerManager() {
        guard let manager = workerManager as? ASRWorkerManager else { return }
        manager.onStateChanged = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.updateWorkerState(state)
            }
        }
    }

    private func wireSessionManager() {
        sessionManagerDelegate.appState = self
        sessionManager.delegate = sessionManagerDelegate
    }

    private func wireAudioCapture() {
        audioCaptureDelegate.appState = self
        audioCapture.delegate = audioCaptureDelegate
    }

    private func wireSnippetNotifications() {
        snippetsObserver = NotificationCenter.default.addObserver(
            forName: .snippetsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadSnippets()
            }
        }
    }

    private func wireSleepNotification() {
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Деактивировать запись при уходе в сон (оба режима)
                if self.sessionManager.state == .recording {
                    self.handleCancelled()
                }
            }
        }
    }

    // MARK: - Handlers

    private func handleActivated() {
        // Новая диктовка → предыдущий post-insertion монитор отменяется
        postInsertionMonitor.stopMonitoring()

        // Блокировка записи пока worker не готов
        guard workerState == .ready else {
            switch workerState {
            case .error(let msg):
                bottomBar.showError(msg)
                soundPlayer.play(.error)
            case .downloadingModel(let progress):
                bottomBar.showModelDownloading(progress: progress)
            default:
                bottomBar.showModelLoading()
            }
            return
        }

        sessionManager.handleActivated()
        bottomBar.show()
        soundPlayer.play(.recordingStarted)

        let sessionId = UUID()
        currentSessionId = sessionId

        let context = appContextEngine.detectCurrentApp()
        currentAppBundleId = context.bundleId
        currentAppContext = context
        let dictionary = loadDictionaryHints()

        pipelineEngine.textMode = context.textMode
        pipelineEngine.hints = NormalizationHints(
            personalDictionary: dictionary.llmReplacements,
            appName: context.appName,
            textMode: context.textMode
        )

        Task {
            await analytics.emit(.dictationStarted, sessionId: sessionId, metadata: [
                AnalyticsMetadataKey.appBundleId: context.bundleId,
                AnalyticsMetadataKey.textMode: context.textMode.rawValue,
            ])
        }

        do {
            try pipelineEngine.startRecording(sessionId: sessionId)
        } catch {
            let message = ErrorMessages.userFacing(for: error)
            sessionManager.handleError(message)
            bottomBar.showError(message)
            soundPlayer.play(.error)
            Task {
                await analytics.emit(.sttFailed, sessionId: sessionId, metadata: [
                    AnalyticsMetadataKey.errorType: ErrorClassifier.classify(error).rawValue,
                ])
            }
        }
    }

    private func handleDeactivated() {
        // Guard: если активация была отклонена (worker не готов), session не в recording
        guard sessionManager.state == .recording else { return }
        sessionManager.handleDeactivated()
        bottomBar.showProcessing()
        soundPlayer.play(.recordingFinished)

        let sessionId = currentSessionId
        let appBundleId = currentAppBundleId

        Task {
            await analytics.emit(.dictationStopped, sessionId: sessionId, metadata: [
                AnalyticsMetadataKey.appBundleId: appBundleId ?? "",
            ])
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let processingStart = ContinuousClock.now
                let result = try await pipelineEngine.stopRecording()

                // Emit STT + normalization events постфактум (timestamps из PipelineResult)
                await emitPipelineEvents(for: result, appBundleId: appBundleId)

                // Минимум 600ms на processing анимацию (2 цикла ProcessingView)
                let elapsed = ContinuousClock.now - processingStart
                let minimumProcessingDisplay: Duration = .milliseconds(600)
                if elapsed < minimumProcessingDisplay {
                    try? await Task.sleep(for: minimumProcessingDisplay - elapsed)
                }

                guard !result.normalizedText.isEmpty else {
                    sessionManager.handleProcessingComplete()
                    sessionManager.handleInsertionComplete()
                    bottomBar.dismiss()
                    return
                }

                sessionManager.handleProcessingComplete()

                if let trigger = result.matchedSnippetTrigger {
                    incrementSnippetUsage(trigger: trigger)
                }

                await analytics.emit(.insertionStarted, sessionId: sessionId, metadata: [
                    AnalyticsMetadataKey.appBundleId: appBundleId ?? "",
                ])

                let insertionStart = CFAbsoluteTimeGetCurrent()
                try await textInserter.insert(result.normalizedText)
                let insertionMs = Int((CFAbsoluteTimeGetCurrent() - insertionStart) * 1000)
                sessionManager.handleInsertionComplete()

                var resultWithInsertion = result
                resultWithInsertion.insertionLatencyMs = insertionMs
                resultWithInsertion.insertionStrategy = textInserter.lastInsertionMethod?.asInsertionStrategy

                let strategy = resultWithInsertion.insertionStrategy?.rawValue ?? InsertionStrategy.none.rawValue
                await analytics.emit(.insertionSucceeded, sessionId: sessionId, metadata: [
                    AnalyticsMetadataKey.appBundleId: appBundleId ?? "",
                    AnalyticsMetadataKey.insertionStrategy: strategy,
                    AnalyticsMetadataKey.insertionLatencyMs: "\(insertionMs)",
                    AnalyticsMetadataKey.e2eLatencyMs: "\(resultWithInsertion.totalLatencyMs + insertionMs)",
                    AnalyticsMetadataKey.cleanTextLengthChars: "\(result.normalizedText.count)",
                    AnalyticsMetadataKey.rawTextLengthChars: "\(result.rawTranscript.count)",
                    AnalyticsMetadataKey.audioDurationMs: "\(result.audioDurationMs)",
                ])

                if resultWithInsertion.insertionStrategy == .clipboard {
                    await analytics.emit(.clipboardFallbackUsed, sessionId: sessionId, metadata: [
                        AnalyticsMetadataKey.insertionStrategy: InsertionStrategy.clipboard.rawValue,
                    ])
                }

                lastResult = resultWithInsertion
                bottomBar.dismiss()

                // Accessibility хинт: один раз за сессию после clipboard fallback
                if resultWithInsertion.insertionStrategy == .clipboard,
                   !accessibilityHintShown,
                   !AXIsProcessTrusted() {
                    accessibilityHintShown = true
                    // Показать после короткой паузы чтобы pill dismiss анимация завершилась
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.bottomBar.showAccessibilityHint()
                    }
                }

                if let modelContainer, let appContext = currentAppContext {
                    let historyContext = ModelContext(modelContainer)
                    let historyStore = HistoryStore(modelContext: historyContext)
                    try? historyStore.save(resultWithInsertion, appContext: appContext)
                }

                // Post-insertion мониторинг: 60s окно для edit/undo detection
                postInsertionMonitor.startMonitoring(
                    sessionId: result.sessionId,
                    insertedText: result.normalizedText,
                    targetBundleId: appBundleId,
                    analytics: analytics
                )
            } catch PipelineError.cancelled {
                // dictationCancelled уже emit'ится в handleCancelled()
                bottomBar.dismiss()
            } catch {
                let errorType = ErrorClassifier.classify(error)
                await analytics.emit(.insertionFailed, sessionId: sessionId, metadata: [
                    AnalyticsMetadataKey.errorType: errorType.rawValue,
                    AnalyticsMetadataKey.appBundleId: appBundleId ?? "",
                ])
                let message = ErrorMessages.userFacing(for: error)
                sessionManager.handleError(message)
                bottomBar.showError(message)
                soundPlayer.play(.error)
            }
        }
    }

    /// Emit STT и normalization событий из PipelineResult
    private func emitPipelineEvents(for result: PipelineResult, appBundleId: String?) async {
        let sessionId = result.sessionId

        await analytics.emit(.sttCompleted, sessionId: sessionId, metadata: [
            AnalyticsMetadataKey.sttLatencyMs: "\(result.sttLatencyMs)",
            AnalyticsMetadataKey.rawTextLengthChars: "\(result.rawTranscript.count)",
            AnalyticsMetadataKey.audioDurationMs: "\(result.audioDurationMs)",
        ])

        let normPath = result.normalizationPath.rawValue
        if result.llmLatencyMs > 0 || result.normalizationPath == .llm || result.normalizationPath == .snippetPlusLLM {
            await analytics.emit(.normalizationCompleted, sessionId: sessionId, metadata: [
                AnalyticsMetadataKey.normalizationPath: normPath,
                AnalyticsMetadataKey.normalizationLatencyMs: "\(result.llmLatencyMs)",
                AnalyticsMetadataKey.cleanTextLengthChars: "\(result.normalizedText.count)",
            ])
        }

        if result.snippetFallbackUsed {
            await analytics.emit(.snippetFallbackUsed, sessionId: sessionId, metadata: [
                AnalyticsMetadataKey.normalizationPath: normPath,
            ])
        }
    }

    private func handleCancelled() {
        let sessionId = currentSessionId
        sessionManager.handleCancelled()
        pipelineEngine.cancel()
        stopEscMonitor()
        bottomBar.dismiss()
        Task {
            await analytics.emit(.dictationCancelled, sessionId: sessionId, metadata: [:])
        }
    }

    // MARK: - Esc monitor (processing cancellation)

    fileprivate func startEscMonitor() {
        stopEscMonitor()

        // Local: Говорун в фокусе
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if event.keyCode == 53 { // Esc
                Task { @MainActor [weak self] in
                    self?.cancelProcessing()
                }
                return nil
            }
            return event
        }) {
            escMonitors.append(m)
        }

        // Global: Говорун не в фокусе (требует Accessibility permission)
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor [weak self] in
                    self?.cancelProcessing()
                }
            }
        }) {
            escMonitors.append(m)
        } else {
            print("[Govorun] Global Esc monitor не создан — нет Accessibility permission")
        }
    }

    fileprivate func stopEscMonitor() {
        for m in escMonitors {
            NSEvent.removeMonitor(m)
        }
        escMonitors.removeAll()
    }

    /// Обновление уровня аудио
    fileprivate func handleAudioLevelUpdate(_ level: Float) {
        bottomBar.showRecording(audioLevel: level)
    }
}

// MARK: - AudioCaptureBridge

private final class AudioCaptureBridge: AudioCaptureDelegate {
    weak var appState: AppState?

    func audioCapture(_ capture: any AudioRecording, didUpdateLevel level: Float) {
        let appState = appState
        Task { @MainActor in
            appState?.handleAudioLevelUpdate(level)
        }
    }

    func audioCapture(_ capture: any AudioRecording, didCaptureChunk chunk: Data) {
        appState?.pipelineEngine.handleAudioChunk(chunk)
    }

    func audioCaptureDidStop(_ capture: any AudioRecording) {}

    func audioCapture(_ capture: any AudioRecording, didFailWithError error: Error) {
        let appState = appState
        let message = ErrorMessages.userFacing(for: error)
        Task { @MainActor in
            appState?.sessionManager.handleError(message)
            appState?.bottomBar.showError(message)
            appState?.soundPlayer.play(.error)
        }
    }
}

// MARK: - SessionManagerBridge

@MainActor
private final class SessionManagerBridge: SessionManagerDelegate {
    weak var appState: AppState?

    func sessionManager(_ manager: SessionManager, didChangeState state: SessionState) {
        switch state {
        case .processing:
            appState?.startEscMonitor()
        case .recording:
            // Toggle mode: Esc должен отменять запись
            if appState?.settings.recordingMode == .toggle {
                appState?.startEscMonitor()
            }
        case .idle:
            appState?.stopEscMonitor()
            appState?.applyPendingSettings()
        default:
            appState?.stopEscMonitor()
        }
    }
}
