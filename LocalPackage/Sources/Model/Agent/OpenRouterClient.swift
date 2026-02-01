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

    struct ResponseMetadata: Sendable {
        let requestId: String
        let statusCode: Int
        let responseBytes: Int
        let latencyMs: Int
    }

    struct Result: Sendable {
        let rawText: String
        let plan: ActionPlan
        let metadata: ResponseMetadata
    }

    let urlSession: URLSession
    let model: String

    init(urlSession: URLSession = .shared, model: String = "openai/gpt-4o-mini") {
        self.urlSession = urlSession
        self.model = model
    }

    func generateActionPlan(
        apiKey: String,
        instruction: String,
        clickMap: PageSnapshot,
        allowSensitiveClicks: Bool,
        requestId: String
    ) async throws -> Result {
        guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else {
            throw URLError(.badURL)
        }

        let encoder = JSONEncoder()
        let clickMapText = try encodeClickMap(clickMap)

        let systemPrompt = """
        You control an in-app browser and must return strict JSON only (no markdown, no prose).
        Use only the provided clickMap ids; prefer id-based actions.
        Output one of:
        {"actions":[...]} or {"error":"..."}.
        Allowed actions: click, type, scroll, wait, navigate, ask_user, done.
        Ask for clarification with {"actions":[{"type":"ask_user","question":"..."}]} when uncertain.
        Never click pay/checkout/confirm purchase unless allowSensitiveClicks is true.
        """

        let userPrompt = """
        Instruction: \(instruction)
        Page: \(clickMap.url) (title: \(clickMap.title))
        allowSensitiveClicks: \(allowSensitiveClicks)
        Click map JSON: \(clickMapText)
        """

        let payload = RequestPayload(
            model: model,
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: userPrompt)
            ],
            temperature: 0,
            responseFormat: ResponseFormat(type: "json_object")
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(requestId, forHTTPHeaderField: "X-Request-Id")
        request.httpBody = try encoder.encode(payload)

        let start = ContinuousClock.now
        let (data, response) = try await urlSession.data(for: request)
        let duration = start.duration(to: ContinuousClock.now).components
        let latencyMs = Int(duration.seconds) * 1000 + Int(duration.attoseconds / 1_000_000_000_000_000)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "OpenRouterClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }

        let decoded = try JSONDecoder().decode(ResponsePayload.self, from: data)
        let text = decoded.choices.first?.message.content ?? ""
        let plan = try AgentParser().parseActionPlan(from: text, clickMap: clickMap)
        let metadata = ResponseMetadata(requestId: requestId, statusCode: httpResponse.statusCode, responseBytes: data.count, latencyMs: latencyMs)
        return Result(rawText: text, plan: plan, metadata: metadata)
    }

    func redactedPayloadString(instruction: String, clickMap: PageSnapshot, allowSensitiveClicks: Bool) -> String {
        let redactedClickMap = truncateClickMap(clickMap, maxItems: 25)
        let clickMapText = (try? encodeClickMap(redactedClickMap)) ?? "{}"
        let systemPrompt = """
        You control an in-app browser and must return strict JSON only (no markdown, no prose).
        Use only the provided clickMap ids; prefer id-based actions.
        Output one of:
        {"actions":[...]} or {"error":"..."}.
        Allowed actions: click, type, scroll, wait, navigate, ask_user, done.
        Ask for clarification with {"actions":[{"type":"ask_user","question":"..."}]} when uncertain.
        Never click pay/checkout/confirm purchase unless allowSensitiveClicks is true.
        """
        let userPrompt = """
        Instruction: \(truncate(instruction))
        Page: \(truncate(clickMap.url)) (title: \(truncate(clickMap.title)))
        allowSensitiveClicks: \(allowSensitiveClicks)
        Click map JSON: \(clickMapText)
        """
        let payload = RequestPayload(
            model: model,
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: userPrompt)
            ],
            temperature: 0,
            responseFormat: ResponseFormat(type: "json_object")
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = (try? encoder.encode(payload)) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func encodeClickMap(_ clickMap: PageSnapshot) throws -> String {
        let data = try JSONEncoder().encode(clickMap)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func truncateClickMap(_ clickMap: PageSnapshot, maxItems: Int) -> PageSnapshot {
        let trimmed = clickMap.clickables.prefix(maxItems).map { clickable in
            Clickable(
                id: clickable.id,
                role: clickable.role,
                label: truncate(clickable.label),
                rect: clickable.rect,
                href: clickable.href.map { truncate($0) },
                tag: clickable.tag,
                disabled: clickable.disabled
            )
        }
        return PageSnapshot(url: truncate(clickMap.url), title: truncate(clickMap.title), clickables: Array(trimmed))
    }

    private func truncate(_ value: String, maxLength: Int = 200) -> String {
        if value.count <= maxLength { return value }
        return String(value.prefix(maxLength)) + "…"
    }
}
