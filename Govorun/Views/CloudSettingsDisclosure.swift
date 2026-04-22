import SwiftUI

// MARK: - Cloud Settings Disclosure

//
// Disclosure-блок внутри ProductModeCard — ввод ключей GigaChat, проверка
// подключения, consent-баннер. D-01/D-02: SwiftUI-композиция без AppKit NSAlert.

struct CloudSettingsDisclosure: View {
    @EnvironmentObject private var appState: AppState

    // MARK: - Локальное состояние

    enum ConnectionState: Equatable {
        case notConfigured
        case checking
        case connected
        case error(String)
    }

    @State private var clientIdDraft: String = ""
    @State private var clientSecretDraft: String = ""
    @State private var connectionState: ConnectionState = .notConfigured
    @State private var showClearKeysAlert: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CloudCredentialsBlock(
                clientIdDraft: $clientIdDraft,
                clientSecretDraft: $clientSecretDraft,
                connectionState: $connectionState,
                showClearKeysAlert: $showClearKeysAlert
            )

            CloudStatusBlock(connectionState: connectionState)

            if connectionState == .connected {
                CloudConsentBanner(connectionState: $connectionState)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .onAppear {
            // cloudAvailable говорит нам есть ли ключи; их содержимое не извлекаем в UI
            // (credential-leaking getter on AppState отклонён — см. T-15-04-02 / T-15-06-02)
            if appState.cloudAvailable {
                connectionState = .connected
            }
        }
        .animation(.easeOut(duration: 0.22), value: connectionState)
    }
}

// MARK: - Блок учётных данных

private struct CloudCredentialsBlock: View {
    @EnvironmentObject private var appState: AppState

    @Binding var clientIdDraft: String
    @Binding var clientSecretDraft: String
    @Binding var connectionState: CloudSettingsDisclosure.ConnectionState
    @Binding var showClearKeysAlert: Bool

    private enum Field: Hashable {
        case clientId
        case clientSecret
    }

    @FocusState private var focus: Field?

    private var canSave: Bool {
        !clientIdDraft.trimmingCharacters(in: .whitespaces).isEmpty
            && !clientSecretDraft.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canClear: Bool {
        appState.cloudAvailable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("УЧЁТНЫЕ ДАННЫЕ")
                .font(.caption.weight(.medium))
                .tracking(1.5)
                .foregroundStyle(Color.ink.opacity(0.28))

            SecureField("Введите Client ID", text: $clientIdDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.mist, lineWidth: 1)
                )
                .focused($focus, equals: .clientId)
                .accessibilityLabel("Идентификатор клиента Client ID для GigaChat")
                .accessibilityHint("Введите Client ID из личного кабинета Сбер")

            SecureField("Введите Client Secret", text: $clientSecretDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.mist, lineWidth: 1)
                )
                .focused($focus, equals: .clientSecret)
                .accessibilityLabel("Секретный ключ Client Secret для GigaChat")
                .accessibilityHint("Введите Client Secret из личного кабинета Сбер")

            HStack(spacing: 8) {
                Button(action: saveAndProbe) {
                    Text("Сохранить")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(canSave ? Color.white : Color.ink.opacity(0.25))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 7)
                        .background(canSave ? Color.ink : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(canSave ? Color.clear : Color.mist, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
                .accessibilityHint("Сохраняет ключи и проверяет подключение к Сберу")

                Button(action: probeOnly) {
                    Text("Проверить")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.ink.opacity(0.5))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.mist, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!appState.cloudAvailable)
                .accessibilityHint("Повторно проверяет подключение к Сберу")

                Spacer()

                Button(action: { showClearKeysAlert = true }) {
                    Text("Очистить")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.ink.opacity(0.5))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.mist, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canClear)
                .accessibilityHint("Удаляет ключи API")
                .alert(
                    "Удалить ключи API?",
                    isPresented: $showClearKeysAlert
                ) {
                    Button("Отмена", role: .cancel) {}
                    Button("Удалить", role: .destructive) {
                        clearKeys()
                    }
                } message: {
                    Text("Cloud-режим станет недоступен. Ключи можно будет ввести снова.")
                }
            }
        }
        .onAppear {
            // даём SwiftUI настроиться и NSTextField смонтироваться (Landmine #5)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if clientIdDraft.isEmpty {
                    focus = .clientId
                }
            }
        }
    }

    // MARK: - Actions

    private func saveAndProbe() {
        let id = clientIdDraft.trimmingCharacters(in: .whitespaces)
        let secret = clientSecretDraft.trimmingCharacters(in: .whitespaces)
        connectionState = .checking
        do {
            try appState.saveCloudCredentials(clientId: id, clientSecret: secret)
        } catch {
            connectionState = .error(cloudErrorMessage(for: error))
            return
        }
        // T-15-06-01: очищаем secret-draft сразу после успешного save
        clientSecretDraft = ""
        Task {
            let result = await appState.probeCloudConnection()
            await MainActor.run {
                switch result {
                case .success:
                    connectionState = .connected
                case .failure(let authError):
                    connectionState = .error(cloudErrorMessage(for: authError))
                }
            }
        }
    }

    private func probeOnly() {
        connectionState = .checking
        Task {
            let result = await appState.probeCloudConnection()
            await MainActor.run {
                switch result {
                case .success:
                    connectionState = .connected
                case .failure(let authError):
                    connectionState = .error(cloudErrorMessage(for: authError))
                }
            }
        }
    }

    private func clearKeys() {
        clientIdDraft = ""
        clientSecretDraft = ""
        do {
            try appState.deleteCloudCredentials()
            connectionState = .notConfigured
        } catch {
            connectionState = .error(cloudErrorMessage(for: error))
        }
    }
}

// MARK: - Блок статуса подключения

private struct CloudStatusBlock: View {
    let connectionState: CloudSettingsDisclosure.ConnectionState

    private var statusTitle: String {
        switch connectionState {
        case .notConfigured: "Не настроено"
        case .checking: "Проверяю подключение…"
        case .connected: "Подключено"
        case .error(let message): message
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            switch connectionState {
            case .notConfigured:
                StatusDot(title: "Не настроено", state: .idle)
            case .checking:
                StatusDot(title: "Проверяю подключение…", state: .idle)
            case .connected:
                StatusDot(title: "Подключено", state: .connected)
            case .error(let message):
                StatusDot(title: message, state: .error)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Статус подключения: \(statusTitle)")
    }
}

// MARK: - Баннер согласия

private struct CloudConsentBanner: View {
    @EnvironmentObject private var appState: AppState
    @Binding var connectionState: CloudSettingsDisclosure.ConnectionState

    private var acceptedAt: Date? {
        appState.settings.cloudConsentAcceptedAt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("КОНФИДЕНЦИАЛЬНОСТЬ")
                .font(.caption.weight(.medium))
                .tracking(1.5)
                .foregroundStyle(Color.ink.opacity(0.28))

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.sage.opacity(0.7))
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 6) {
                    if let accepted = acceptedAt {
                        postAckContent(acceptedAt: accepted)
                    } else {
                        preAckContent
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.sage.opacity(0.07))
            )
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Pre-ack

    @ViewBuilder
    private var preAckContent: some View {
        Text("Аудио и текст отправляются в Сбер GigaChat")
            .font(.body)
            .foregroundStyle(Color.ink)

        Text("Перед первым использованием облачного режима подтвердите отправку данных. Ключи остаются в Keychain на вашем Mac.")
            .font(.caption)
            .foregroundStyle(Color.ink.opacity(0.5))

        Button(action: acceptConsent) {
            Text("Принять и включить Cloud")
                .font(.callout.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 7)
                .background(Color.ink)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .accessibilityHint("Включает облачный режим и разрешает отправку данных в Сбер")
    }

    // MARK: - Post-ack

    @ViewBuilder
    private func postAckContent(acceptedAt: Date) -> some View {
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.dateStyle = .short
            f.timeStyle = .none
            return f
        }()

        Text("Cloud активен с \(formatter.string(from: acceptedAt))")
            .font(.caption)
            .foregroundStyle(Color.ink.opacity(0.5))

        Button(action: revokeConsent) {
            Text("Отозвать согласие")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.ink.opacity(0.5))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.mist, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .accessibilityHint("Отключает облачный режим со следующей сессии. Ключи останутся сохранены.")
    }

    // MARK: - Actions

    private func acceptConsent() {
        appState.settings.cloudConsentAcceptedAt = Date()
        // productMode = .cloud триггерит applyProductMode через wireSettingsChange observer
        appState.settings.productMode = .cloud
    }

    private func revokeConsent() {
        appState.settings.clearCloudConsent()
        // productMode = .standard триггерит applyProductMode через wireSettingsChange observer
        // (D-07.1: actual switch deferred to idle via pendingProductMode)
        appState.settings.productMode = .standard
    }
}
