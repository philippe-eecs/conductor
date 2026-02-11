import Foundation

/// Extracts `<conductor_actions>[...]</conductor_actions>` JSON from Claude response text.
enum ActionParser {

    struct ParseResult {
        let cleanText: String
        let actions: [AssistantActionRequest]
    }

    /// Parse Claude response text for embedded action JSON.
    static func extractActions(from text: String) -> ParseResult {
        let pattern = "<conductor_actions>([\\s\\S]*?)</conductor_actions>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
              let jsonRange = Range(match.range(at: 1), in: text) else {
            return ParseResult(cleanText: text, actions: [])
        }

        let jsonString = String(text[jsonRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanText = text.replacingOccurrences(
            of: "<conductor_actions>[\\s\\S]*?</conductor_actions>",
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        // Try parsing as an array of AssistantActionRequest
        guard let data = jsonString.data(using: .utf8) else {
            return ParseResult(cleanText: cleanText, actions: [])
        }

        // Try array first, then envelope
        if let actions = try? JSONDecoder().decode([AssistantActionRequest].self, from: data) {
            return ParseResult(cleanText: cleanText, actions: actions)
        }

        if let envelope = try? JSONDecoder().decode(AssistantActionEnvelope.self, from: data) {
            return ParseResult(cleanText: cleanText, actions: envelope.actions)
        }

        return ParseResult(cleanText: cleanText, actions: [])
    }
}
