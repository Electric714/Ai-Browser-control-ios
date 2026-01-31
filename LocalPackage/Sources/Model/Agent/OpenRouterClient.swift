import Foundation

struct OpenRouterClient {
    enum OpenRouterClientError: Error {
        case invalidJSON
        case emptyResponse
    }
    struct RequestPayload: Encodable {
        let model: String
        let messages: [Message]
        let temperature: Double
    }

    struct Message: Encodable {
        let role: String
        let content: String
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
        let plan: ActionPlan
    }

    let urlSession: URLSession
    let model: String

    init(urlSession: URLSession = .shared, model: String = "openai/gpt-4o-mini") {
        self.urlSession = urlSession
        self.model = model
    }

    func generateActionPlan(apiKey: String, instruction: String, snapshot: PageSnapshot) async throws -> Result {
        guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else {
            throw URLError(.badURL)
        }

        let encoder = JSONEncoder()
        let snapshotData = try encoder.encode(snapshot)
        let snapshotText = String(data: snapshotData, encoding: .utf8) ?? "{}"

        let systemPrompt = """
        You are an automation planner. Return JSON only. No markdown. No extra text.
        Choose exactly one best click action from the provided clickables unless none match.
        If none match return {"actions":[],"notes":"no match"}.
        Output schema: {"actions":[{"type":"click","id":"e17"}],"notes":"optional"}
        """

        let userPrompt = """
        Instruction: \(instruction)
        Page: \(snapshot.url) (title: \(snapshot.title))
        Clickables JSON: \(snapshotText)
        """

        let payload = RequestPayload(
            model: model,
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: userPrompt)
            ],
            temperature: 0
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "OpenRouterClient", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: message])
        }

        let decoded = try JSONDecoder().decode(ResponsePayload.self, from: data)
        let text = decoded.choices.first?.message.content ?? ""
        guard let textData = text.data(using: .utf8), !text.isEmpty else {
            throw OpenRouterClientError.emptyResponse
        }
        let plan: ActionPlan
        do {
            plan = try JSONDecoder().decode(ActionPlan.self, from: textData)
        } catch {
            throw OpenRouterClientError.invalidJSON
        }
        return Result(rawText: text, plan: plan)
    }
}
