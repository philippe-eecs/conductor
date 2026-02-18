import Foundation

struct ConversationTurnResult {
    let assistantMessage: ChatMessage
    let parsedActions: [AssistantActionRequest]
    let sessionId: String?
    let title: String
    let totalCost: Double?
    let model: String?
}

actor ConversationCore {
    static let shared = ConversationCore()

    private let claudeService = ClaudeService.shared

    func runTurn(
        content: String,
        history: [ChatMessage],
        toolsEnabled: Bool,
        chatModel: String,
        permissionMode: String
    ) async throws -> ConversationTurnResult {
        let temporalContext = TemporalContext.current()
        let response = try await claudeService.sendMessage(
            content,
            history: history,
            toolsEnabled: toolsEnabled,
            modelOverride: chatModel,
            permissionModeOverride: permissionMode,
            runtimePreamble: temporalContext.runtimePreamble()
        )

        let parseResult = ActionParser.extractActions(from: response.result)
        let displayText = parseResult.cleanText.isEmpty ? response.result : parseResult.cleanText

        let assistantMessage = ChatMessage(
            role: .assistant,
            content: displayText,
            cost: response.totalCostUsd,
            model: response.model,
            toolCalls: response.toolCalls
        )

        return ConversationTurnResult(
            assistantMessage: assistantMessage,
            parsedActions: parseResult.actions,
            sessionId: response.sessionId,
            title: extractTitle(from: content),
            totalCost: response.totalCostUsd,
            model: response.model
        )
    }

    func startNewConversation() async {
        await claudeService.startNewConversation()
    }

    func resumeSession(_ sessionId: String) async {
        await claudeService.resumeSession(sessionId)
    }

    private func extractTitle(from message: String) -> String {
        let truncated = String(message.prefix(50))
        if let periodIndex = truncated.firstIndex(of: ".") {
            return String(truncated[..<periodIndex])
        }
        if let newlineIndex = truncated.firstIndex(of: "\n") {
            return String(truncated[..<newlineIndex])
        }
        return truncated
    }
}
