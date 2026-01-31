import Foundation

struct OpenRouterClient {
    struct RequestPayload: Encodable {
        let model: String
        let messages: [Message]
        let temperature: Double
        let responseFormat: ResponseFormat

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case temperature
            case responseFormat = "response_format"
        }
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct ResponseFormat: Encodable {
        let type: String
    }

    struct ResponsePayload: Decodable {
        struct Choice: Decodable {
            struct ChoiceMessage: Decodable {
                let content: String?
            }
            let message: ChoiceMessage
        }
        let choices: [Choice]
    }

    struct Result: Sendable {
        let rawText: String
        let requestId: String
        let statusCode: Int
        let latencyMs: Int
        let responseBytes: Int
    }

    enum OpenRouterClientError: LocalizedError {
        case httpError(statusCode: Int, body: String, requestId: String, latencyMs: Int, responseBytes: Int)
        case invalidResponse(String)

        var errorDescription: String? {
            switch self {
            case let .httpError(statusCode, body, requestId, latencyMs, responseBytes):
                return "OpenRouter HTTP \(statusCode) (id \(requestId), \(latencyMs)ms, \(responseBytes) bytes): \(body)"
            case let .invalidResponse(message):
                return "OpenRouter response invalid: \(message)"
            }
        }
    }

    let urlSession: URLSession
    let model: String

    init(urlSession: URLSession = .shared, model: String = "openai/gpt-4o-mini") {
        self.urlSession = urlSession
        self.model = model
    }

    func payloadPreview(instruction: String, clickMap: PageSnapshot, allowSensitiveClicks: Bool) -> String {
        let payload = buildPayload(instruction: instruction, clickMap: clickMap, allowSensitiveClicks: allowSensitiveClicks)
        return sanitizedPayloadPreview(payload: payload, clickMap: clickMap)
    }

    func generateActionPlan(apiKey: String, requestId: String, instruction: String, clickMap: PageSnapshot, allowSensitiveClicks: Bool) async throws -> Result {
        guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else {
            throw URLError(.badURL)
        }

        let encoder = JSONEncoder()
        let payload = buildPayload(instruction: instruction, clickMap: clickMap, allowSensitiveClicks: allowSensitiveClicks)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(requestId, forHTTPHeaderField: "X-Request-Id")
        request.httpBody = try encoder.encode(payload)

        let start = ContinuousClock.now
        let (data, response) = try await urlSession.data(for: request)
        let duration = start.duration(to: ContinuousClock.now)
        let latencyMs = Int(duration.components.seconds * 1000) +
            Int(duration.components.attoseconds / 1_000_000_000_000_000)
        let responseBytes = data.count

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterClientError.invalidResponse("Missing HTTPURLResponse")
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? ""
            let truncated = String(message.prefix(800))
            throw OpenRouterClientError.httpError(
                statusCode: httpResponse.statusCode,
                body: truncated,
                requestId: requestId,
                latencyMs: latencyMs,
                responseBytes: responseBytes
            )
        }

        let decoded = try JSONDecoder().decode(ResponsePayload.self, from: data)
        let text = decoded.choices.first?.message.content ?? ""
        return Result(
            rawText: text,
            requestId: requestId,
            statusCode: httpResponse.statusCode,
            latencyMs: latencyMs,
            responseBytes: responseBytes
        )
    }

    private func buildPayload(instruction: String, clickMap: PageSnapshot, allowSensitiveClicks: Bool) -> RequestPayload {
        let clickMapData = (try? JSONEncoder().encode(clickMap)) ?? Data()
        let clickMapText = String(data: clickMapData, encoding: .utf8) ?? "{}"

        let systemPrompt = """
        You are controlling an in-app browser with an action executor. You will receive:
        - A user instruction
        - The current URL/title
        - A click map of elements with stable ids (data-ai-id)
        Return ONLY JSON. No prose. No markdown.

        Output must be one of:
        {"actions":[...]} OR {"error":"..."}

        Allowed actions with required fields:
        - {"type":"click","id":"e17"}
        - {"type":"type","id":"e17","text":"hello"} (or selector instead of id)
        - {"type":"scroll","direction":"down","amount":400}
        - {"type":"wait","ms":500}
        - {"type":"navigate","url":"https://example.com"}
        - {"type":"ask_user","question":"..."}
        - {"type":"done","summary":"..."}

        Rules:
        - Prefer click by id from click map.
        - Never click pay/checkout/confirm purchase unless allowSensitiveClicks is true.
        - If unsure, return ask_user with a question.
        allowSensitiveClicks=\(allowSensitiveClicks ? "true" : "false")
        """

        let userPrompt = """
        Instruction: \(instruction)
        Page: \(clickMap.url) (title: \(clickMap.title))
        Click map JSON: \(clickMapText)
        """

        return RequestPayload(
            model: model,
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: userPrompt)
            ],
            temperature: 0,
            responseFormat: ResponseFormat(type: "json_object")
        )
    }

    private func sanitizedPayloadPreview(payload: RequestPayload, clickMap: PageSnapshot) -> String {
        let truncatedClickables = clickMap.clickables.prefix(25)
        let truncatedSnapshot = PageSnapshot(url: clickMap.url, title: clickMap.title, clickables: Array(truncatedClickables))
        let preview = RequestPayload(
            model: payload.model,
            messages: [
                payload.messages[0],
                Message(
                    role: payload.messages[1].role,
                    content: "Instruction: <redacted>\nPage: \(clickMap.url) (title: \(clickMap.title))\nClick map JSON: \(String(data: (try? JSONEncoder().encode(truncatedSnapshot)) ?? Data(), encoding: .utf8) ?? "{}")"
                )
            ],
            temperature: payload.temperature,
            responseFormat: payload.responseFormat
        )
        let data = try? JSONEncoder().encode(preview)
        let previewString = String(data: data ?? Data(), encoding: .utf8) ?? ""
        return String(previewString.prefix(1200))
    }
}
