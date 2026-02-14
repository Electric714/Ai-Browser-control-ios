import Testing

@testable import Model

struct AgentParserTests {
    private let clickMap = PageSnapshot(
        url: "https://example.com",
        title: "Example",
        clickables: [
            Clickable(
                id: "e1",
                role: "button",
                label: "Continue",
                rect: ClickRect(x: 0.1, y: 0.1, w: 0.2, h: 0.1),
                href: nil,
                tag: "BUTTON",
                disabled: false
            )
        ]
    )

    @Test
    func parseActionPlan_allowsBracesInsideJSONStringValues() throws {
        let response = """
        Plan:
        {"actions":[{"type":"done","summary":"Completed {draft} update"}],"notes":"ok"}
        Extra text
        """

        let plan = try AgentParser().parseActionPlan(from: response, clickMap: clickMap)

        #expect(plan.actions == [.done(summary: "Completed {draft} update")])
        #expect(plan.notes == "ok")
    }

    @Test
    func parseActionPlan_allowsEscapedQuotesAndBracesInJSONStringValues() throws {
        let response = """
        {"actions":[{"type":"ask_user","question":"Use this literal: \\\"{query}\\\"?"}],"notes":"prompt"} trailing
        """

        let plan = try AgentParser().parseActionPlan(from: response, clickMap: clickMap)

        #expect(plan.actions == [.askUser(question: "Use this literal: \"{query}\"?")])
        #expect(plan.notes == "prompt")
    }
}
