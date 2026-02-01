import Combine
import Foundation

@MainActor
final class TaskUndoManager: ObservableObject {
    static let shared = TaskUndoManager()

    enum UndoableAction {
        case deleteTask(TodoTask)
        case deleteList(list: TaskList, taskIds: [String])
    }

    @Published private(set) var canUndo: Bool = false

    private var undoStack: [UndoableAction] = []
    private let maxStackSize = 50

    private init() {}

    func recordDeleteTask(_ task: TodoTask) {
        push(.deleteTask(task))
    }

    func recordDeleteList(list: TaskList, taskIds: [String]) {
        push(.deleteList(list: list, taskIds: taskIds))
    }

    func undo() {
        guard let action = undoStack.popLast() else { return }
        canUndo = !undoStack.isEmpty

        switch action {
        case .deleteTask(let task):
            do {
                try Database.shared.createTask(task)
            } catch {
                // If the task already exists, treat undo as an update.
                try? Database.shared.updateTask(task)
            }

        case .deleteList(let list, let taskIds):
            do {
                try Database.shared.upsertTaskList(list)
                try Database.shared.restoreListMembership(taskIds: taskIds, listId: list.id)
            } catch {
                // Best effort; UI will refresh after undo.
            }
        }
    }

    private func push(_ action: UndoableAction) {
        undoStack.append(action)
        if undoStack.count > maxStackSize {
            undoStack.removeFirst(undoStack.count - maxStackSize)
        }
        canUndo = true
    }
}

