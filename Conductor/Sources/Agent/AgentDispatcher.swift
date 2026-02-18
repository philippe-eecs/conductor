import Foundation

actor AgentDispatcher {
    static let shared = AgentDispatcher()

    private init() {}

    /// Execute a one-shot agent run.
    /// Called from a detached Task — does not block the caller.
    func execute(runId: Int64, todoId: Int64, prompt: String) async {
        let blinkRepo = BlinkRepository(db: AppDatabase.shared)
        let projectRepo = ProjectRepository(db: AppDatabase.shared)

        // Build context from todo + project + deliverables
        var contextParts: [String] = []

        if let todo = try? projectRepo.todo(id: todoId) {
            contextParts.append("TODO: \(todo.title)")
            if let projectId = todo.projectId, let project = try? projectRepo.project(id: projectId) {
                contextParts.append("Project: \(project.name)")
                if let desc = project.description { contextParts.append("Description: \(desc)") }
            }

            let deliverables = (try? projectRepo.deliverablesForTodo(todoId)) ?? []
            if !deliverables.isEmpty {
                let deliverableList = deliverables.map { d in
                    "\(d.kind.rawValue): \(d.filePath ?? d.url ?? "unknown")"
                }.joined(separator: "\n")
                contextParts.append("Deliverables:\n\(deliverableList)")
            }
        }

        let fullPrompt = """
        \(contextParts.joined(separator: "\n"))

        Task:
        \(prompt)
        """

        Log.agent.info("Agent run \(runId) started for TODO \(todoId)")

        do {
            let response = try await ClaudeService.shared.executeAgentPrompt(fullPrompt)

            // Update run status
            try blinkRepo.completeAgentRun(
                id: runId,
                output: response.result,
                costUsd: response.totalCostUsd,
                status: .completed
            )

            // Verify deliverables exist on disk
            let deliverables = (try? projectRepo.deliverablesForTodo(todoId)) ?? []
            for deliverable in deliverables {
                if let filePath = deliverable.filePath {
                    let exists = FileManager.default.fileExists(atPath: filePath)
                    try? projectRepo.verifyDeliverable(id: deliverable.id!, verified: exists)
                }
            }

            Log.agent.info("Agent run \(runId) completed")
        } catch {
            Log.agent.error("Agent run \(runId) failed: \(error.localizedDescription, privacy: .public)")
            try? blinkRepo.completeAgentRun(
                id: runId,
                output: "Error: \(error.localizedDescription)",
                costUsd: nil,
                status: .failed
            )
        }
    }
}
