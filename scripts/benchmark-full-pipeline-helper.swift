import Foundation

private struct Request: Decodable {
    let op: String
    let textMode: String?
    let currentDate: String?
    let transcript: String?
    let deterministicText: String?
    let llmOutput: String?
    let terminalPeriodEnabled: Bool?
}

private struct Response: Encodable {
    let ok: Bool
    let systemPrompt: String?
    let deterministicText: String?
    let shouldInvokeLLM: Bool?
    let finalText: String?
    let normalizationPath: String?
    let gateFailureReason: String?
    let error: String?

    static func error(_ message: String) -> Self {
        .init(
            ok: false,
            systemPrompt: nil,
            deterministicText: nil,
            shouldInvokeLLM: nil,
            finalText: nil,
            normalizationPath: nil,
            gateFailureReason: nil,
            error: message
        )
    }
}

@main
struct BenchmarkFullPipelineHelper {
    static func main() {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = []

        while let line = readLine() {
            let response: Response
            do {
                let data = Data(line.utf8)
                let request = try decoder.decode(Request.self, from: data)
                response = try handle(request)
            } catch {
                response = .error(String(describing: error))
            }

            do {
                let data = try encoder.encode(response)
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data([0x0a]))
            } catch {
                let fallback = #"{"ok":false,"error":"encoding_failed"}"#
                FileHandle.standardOutput.write(Data(fallback.utf8))
                FileHandle.standardOutput.write(Data([0x0a]))
            }
        }
    }

    private static func handle(_ request: Request) throws -> Response {
        switch request.op {
        case "prompt":
            let textMode = try parseTextMode(request.textMode)
            let currentDate = try parseDate(request.currentDate)
            return .init(
                ok: true,
                systemPrompt: textMode.systemPrompt(currentDate: currentDate),
                deterministicText: nil,
                shouldInvokeLLM: nil,
                finalText: nil,
                normalizationPath: nil,
                gateFailureReason: nil,
                error: nil
            )

        case "preflight":
            guard let transcript = request.transcript else {
                return .error("missing transcript")
            }
            let preflight = NormalizationPipeline.preflight(
                transcript: transcript,
                terminalPeriodEnabled: request.terminalPeriodEnabled ?? true
            )
            return .init(
                ok: true,
                systemPrompt: nil,
                deterministicText: preflight.deterministicText,
                shouldInvokeLLM: preflight.shouldInvokeLLM,
                finalText: nil,
                normalizationPath: nil,
                gateFailureReason: nil,
                error: nil
            )

        case "postflight":
            guard let deterministicText = request.deterministicText else {
                return .error("missing deterministicText")
            }
            guard let llmOutput = request.llmOutput else {
                return .error("missing llmOutput")
            }
            let textMode = try parseTextMode(request.textMode)
            let postflight = NormalizationPipeline.postflight(
                deterministicText: deterministicText,
                llmOutput: llmOutput,
                textMode: textMode,
                terminalPeriodEnabled: request.terminalPeriodEnabled ?? true
            )
            return .init(
                ok: true,
                systemPrompt: nil,
                deterministicText: nil,
                shouldInvokeLLM: nil,
                finalText: postflight.finalText,
                normalizationPath: postflight.path.rawValue,
                gateFailureReason: postflight.gateFailureReason?.analyticsValue,
                error: nil
            )

        case "failed-postflight":
            guard let deterministicText = request.deterministicText else {
                return .error("missing deterministicText")
            }
            let postflight = NormalizationPipeline.failedPostflight(
                deterministicText: deterministicText
            )
            return .init(
                ok: true,
                systemPrompt: nil,
                deterministicText: nil,
                shouldInvokeLLM: nil,
                finalText: postflight.finalText,
                normalizationPath: postflight.path.rawValue,
                gateFailureReason: nil,
                error: nil
            )

        default:
            return .error("unsupported op: \(request.op)")
        }
    }

    private static func parseTextMode(_ rawValue: String?) throws -> TextMode {
        guard let rawValue, let mode = TextMode(rawValue: rawValue) else {
            throw HelperError.invalidTextMode(rawValue ?? "nil")
        }
        return mode
    }

    private static func parseDate(_ rawValue: String?) throws -> Date {
        guard let rawValue else { return Date() }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: rawValue) else {
            throw HelperError.invalidDate(rawValue)
        }
        return date
    }

    private enum HelperError: Error, CustomStringConvertible {
        case invalidTextMode(String)
        case invalidDate(String)

        var description: String {
            switch self {
            case .invalidTextMode(let value):
                "invalid text mode: \(value)"
            case .invalidDate(let value):
                "invalid currentDate: \(value)"
            }
        }
    }
}
