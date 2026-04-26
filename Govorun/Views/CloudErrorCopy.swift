import Foundation

// MARK: - Cloud Settings: отображение ошибок подключения

/// Маппит ошибку подключения Cloud в локализованную русскую строку из UI-SPEC §Copywriting Contract.
/// D-10: живёт в Views/ слое, не в Core/ErrorMessages.swift — pure-UI boundary фазы 15.
/// D-11.2 (Path B): использует `AuthError.networkError(urlError:description:)` для различения
/// offline / timeout / прочих транспортных ошибок через `URLError.Code`.
func cloudErrorMessage(for error: Error) -> String {
    let generic = "Сбой Cloud. Попробуйте позже."

    guard let authError = error as? AuthError else {
        return generic
    }

    switch authError {
    case .credentialsNotFound:
        return "Введите ключи API. Без них Cloud недоступен."

    case .invalidResponse(let statusCode):
        switch statusCode {
        case 401:
            return "Ключи отклонены Сбером. Проверьте Client ID и Secret."
        case 429:
            return "Слишком много запросов. Попробуйте через минуту."
        case 500...599:
            return "Ошибка на стороне Сбера. Попробуйте позже."
        default:
            return generic
        }

    case .tokenParsingFailed:
        return generic

    case .networkError(let urlErr, _):
        switch urlErr?.code {
        case .some(.notConnectedToInternet), .some(.networkConnectionLost):
            return "Нет интернета. Cloud временно недоступен."
        case .some(.timedOut):
            return "Сбер не ответил за 30 секунд. Проверьте сеть."
        default:
            return "Сервис Сбера недоступен. Попробуйте позже."
        }
    }
}
