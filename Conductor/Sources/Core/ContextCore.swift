import Foundation

/// Deterministic context fetch with lightweight rule-based escalation.
actor ContextCore {
    static let shared = ContextCore()

    private struct CacheEntry {
        let createdAt: Date
        let context: ContextData
    }

    private var cachedDefaultContext: CacheEntry?
    private let defaultTTL: TimeInterval = 45

    private init() {}

    func defaultContext() async -> ContextData {
        if let cached = cachedDefaultContext,
           Date().timeIntervalSince(cached.createdAt) < defaultTTL {
            return cached.context
        }

        let need = ContextNeed(
            types: [.calendar(filter: nil), .reminders(filter: nil), .goals],
            reasoning: "Default context"
        )
        let context = await ContextBuilder.shared.buildContext(for: need)

        cachedDefaultContext = CacheEntry(createdAt: Date(), context: context)
        return context
    }

    func context(forQuery query: String) async -> ContextData {
        let q = query.lowercased()

        var types: [ContextNeed.ContextType] = [.calendar(filter: nil), .reminders(filter: nil), .goals]

        if q.contains("email") || q.contains("mail") || q.contains("inbox") || q.contains("message") {
            types.append(.email(filter: nil))
        }

        if q.contains("note") || q.contains("notes") {
            types.append(.notes)
        }

        let need = ContextNeed(types: deduplicate(types), reasoning: "Rule-based query routing")
        return await ContextBuilder.shared.buildContext(for: need)
    }

    func invalidateCache() {
        cachedDefaultContext = nil
    }

    private func deduplicate(_ input: [ContextNeed.ContextType]) -> [ContextNeed.ContextType] {
        var set = Set<ContextNeed.ContextType>()
        var out: [ContextNeed.ContextType] = []
        for value in input where !set.contains(value) {
            set.insert(value)
            out.append(value)
        }
        return out
    }
}
