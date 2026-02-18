import Foundation
import GRDB

enum InitialSchema {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("001_initialSchema") { db in
            // MARK: - Preferences
            try db.create(table: "preferences", ifNotExists: true) { t in
                t.primaryKey("key", .text).notNull()
                t.column("value", .text).notNull()
            }

            // MARK: - Sessions
            try db.create(table: "sessions", ifNotExists: true) { t in
                t.primaryKey("id", .text).notNull()
                t.column("created_at", .double).notNull()
                t.column("last_used", .double).notNull()
                t.column("title", .text).notNull()
            }

            // MARK: - Messages
            try db.create(table: "messages", ifNotExists: true) { t in
                t.primaryKey("id", .text).notNull()
                t.column("role", .text).notNull()
                t.column("content", .text).notNull()
                t.column("timestamp", .double).notNull()
                t.column("session_id", .text)
                t.column("metadata_json", .text)
                t.column("ui_json", .text)
                t.column("tool_calls_json", .text)
            }

            // MARK: - Cost Log
            try db.create(table: "cost_log", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("rowid")
                t.column("timestamp", .double).notNull()
                t.column("amount_usd", .double).notNull()
                t.column("session_id", .text)
            }
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS index_cost_log_on_timestamp ON cost_log(timestamp)")

            // MARK: - Notes
            try db.create(table: "notes", ifNotExists: true) { t in
                t.primaryKey("id", .text).notNull()
                t.column("title", .text).notNull()
                t.column("content", .text).notNull()
                t.column("created_at", .double).notNull()
                t.column("updated_at", .double).notNull()
            }
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS index_notes_on_updated_at ON notes(updated_at)")

            // MARK: - Daily Briefs
            try db.create(table: "daily_briefs", ifNotExists: true) { t in
                t.primaryKey("id", .text).notNull()
                t.column("date", .text).notNull()
                t.column("brief_type", .text).notNull()
                t.column("content", .text).notNull()
                t.column("generated_at", .double).notNull()
                t.column("read_at", .double)
                t.column("dismissed", .integer).notNull().defaults(to: 0)
            }
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS index_daily_briefs_on_date ON daily_briefs(date)")

            // MARK: - Daily Goals
            try db.create(table: "daily_goals", ifNotExists: true) { t in
                t.primaryKey("id", .text).notNull()
                t.column("date", .text).notNull()
                t.column("goal_text", .text).notNull()
                t.column("priority", .integer).notNull().defaults(to: 0)
                t.column("completed_at", .double)
                t.column("rolled_to", .text)
            }
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS index_daily_goals_on_date ON daily_goals(date)")

            // MARK: - Productivity Stats
            try db.create(table: "productivity_stats", ifNotExists: true) { t in
                t.primaryKey("id", .text).notNull()
                t.column("date", .text).notNull()
                t.column("goals_completed", .integer).notNull()
                t.column("goals_total", .integer).notNull()
                t.column("meetings_count", .integer).notNull()
                t.column("meetings_hours", .double).notNull()
                t.column("focus_hours", .double).notNull()
                t.column("overdue_count", .integer).notNull()
                t.column("generated_at", .double).notNull()
            }
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS index_productivity_stats_on_date ON productivity_stats(date)")

            // MARK: - Tasks
            try db.create(table: "tasks", ifNotExists: true) { t in
                t.primaryKey("id", .text).notNull()
                t.column("title", .text).notNull()
                t.column("notes", .text)
                t.column("due_date", .double)
                t.column("list_id", .text)
                t.column("priority", .integer).notNull().defaults(to: 0)
                t.column("completed", .integer).notNull().defaults(to: 0)
                t.column("completed_at", .double)
                t.column("created_at", .double).notNull()
                t.column("updated_at", .double).notNull()
                t.column("blocked_by_task_id", .text)
                t.column("blocked_offset_days", .integer)
            }
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS index_tasks_on_list_id ON tasks(list_id)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS index_tasks_on_due_date ON tasks(due_date)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS index_tasks_on_completed ON tasks(completed)")

            // MARK: - Task Lists
            try db.create(table: "task_lists", ifNotExists: true) { t in
                t.primaryKey("id", .text).notNull()
                t.column("name", .text).notNull()
                t.column("color", .text).notNull().defaults(to: "blue")
                t.column("icon", .text).notNull().defaults(to: "list.bullet")
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("created_at", .double).notNull()
            }

            // MARK: - Context Library
            try db.create(table: "context_library", ifNotExists: true) { t in
                t.primaryKey("id", .text).notNull()
                t.column("title", .text).notNull()
                t.column("content", .text).notNull()
                t.column("type", .text).notNull()
                t.column("created_at", .double).notNull()
                t.column("auto_include", .boolean).notNull()
            }
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS index_context_library_on_created_at ON context_library(created_at)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS index_context_library_on_auto_include ON context_library(auto_include)")

            // MARK: - Agent Tasks
            try db.create(table: "agent_tasks", ifNotExists: true) { t in
                t.primaryKey("id", .text).notNull()
                t.column("name", .text).notNull()
                t.column("prompt", .text).notNull()
                t.column("trigger_type", .text).notNull()
                t.column("trigger_config", .text).notNull().defaults(to: "{}")
                t.column("context_needs", .text).notNull().defaults(to: "[]")
                t.column("allowed_actions", .text).notNull().defaults(to: "[]")
                t.column("status", .text).notNull().defaults(to: "active")
                t.column("created_by", .text).notNull().defaults(to: "chat")
                t.column("created_at", .double).notNull()
                t.column("last_run", .double)
                t.column("next_run", .double)
                t.column("run_count", .integer).notNull().defaults(to: 0)
                t.column("max_runs", .integer)
                t.column("linked_todo_task_id", .text)
            }

            // MARK: - Agent Task Results
            try db.create(table: "agent_task_results", ifNotExists: true) { t in
                t.primaryKey("id", .text).notNull()
                t.column("task_id", .text).notNull()
                t.column("timestamp", .double).notNull()
                t.column("output", .text).notNull()
                t.column("actions_proposed", .text).notNull().defaults(to: "[]")
                t.column("actions_executed", .text).notNull().defaults(to: "[]")
                t.column("cost_usd", .double)
                t.column("status", .text).notNull().defaults(to: "success")
                t.column("duration_ms", .integer)
            }

            // MARK: - Processed Emails
            try db.create(table: "processed_emails", ifNotExists: true) { t in
                t.primaryKey("id", .text).notNull()
                t.column("message_id", .text).notNull().unique()
                t.column("sender", .text).notNull()
                t.column("subject", .text).notNull()
                t.column("body_preview", .text).notNull().defaults(to: "")
                t.column("received_at", .double).notNull()
                t.column("is_read", .boolean).notNull().defaults(to: true)
                t.column("severity", .text).notNull().defaults(to: "normal")
                t.column("ai_summary", .text)
                t.column("action_item", .text)
                t.column("processed_at", .double).notNull()
                t.column("dismissed", .boolean).notNull().defaults(to: false)
            }

            // MARK: - Themes
            try db.create(table: "themes", ifNotExists: true) { t in
                t.primaryKey("id", .text).notNull()
                t.column("name", .text).notNull()
                t.column("color", .text).notNull().defaults(to: "blue")
                t.column("description", .text)
                t.column("is_archived", .boolean).notNull().defaults(to: false)
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("created_at", .double).notNull()
                t.column("objective", .text)
                t.column("default_start_time", .text)
                t.column("default_duration_minutes", .integer).notNull().defaults(to: 60)
                t.column("context_filter", .text)
                t.column("auto_remind_leftover", .boolean).notNull().defaults(to: false)
                t.column("leftover_remind_time", .text)
                t.column("is_loose_bucket", .boolean).notNull().defaults(to: false)
            }

            // MARK: - Theme Items
            try db.create(table: "theme_items", ifNotExists: true) { t in
                t.primaryKey("id", .text).notNull()
                t.column("theme_id", .text).notNull()
                t.column("item_type", .text).notNull()
                t.column("item_id", .text).notNull()
                t.column("created_at", .double).notNull()
                t.uniqueKey(["theme_id", "item_type", "item_id"])
            }

            // MARK: - Event Theme Keywords
            try db.create(table: "event_theme_keywords", ifNotExists: true) { t in
                t.primaryKey("id", .text).notNull()
                t.column("theme_id", .text).notNull()
                t.column("keyword", .text).notNull()
            }

            // MARK: - Theme Blocks
            try db.create(table: "theme_blocks", ifNotExists: true) { t in
                t.primaryKey("id", .text).notNull()
                t.column("theme_id", .text).notNull()
                t.column("start_time", .text).notNull()
                t.column("end_time", .text).notNull()
                t.column("is_recurring", .boolean).notNull().defaults(to: false)
                t.column("recurrence_rule", .text)
                t.column("status", .text).notNull().defaults(to: "draft")
                t.column("calendar_event_id", .text)
                t.column("created_at", .double).notNull()
                t.column("updated_at", .double).notNull()
            }
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS index_theme_blocks_on_theme_id ON theme_blocks(theme_id)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS index_theme_blocks_on_status ON theme_blocks(status)")

            // MARK: - Theme Focus Migrations (legacy compat)
            try db.create(table: "theme_focus_migrations", ifNotExists: true) { t in
                t.primaryKey("focus_group_id", .text).notNull()
                t.column("theme_id", .text).notNull()
                t.column("migrated_at", .double).notNull()
            }

            // MARK: - Behavior Events
            try db.create(table: "behavior_events", ifNotExists: true) { t in
                t.primaryKey("id", .text).notNull()
                t.column("event_type", .text).notNull()
                t.column("entity_id", .text)
                t.column("metadata_json", .text).notNull().defaults(to: "{}")
                t.column("hour_of_day", .integer).notNull()
                t.column("day_of_week", .integer).notNull()
                t.column("created_at", .double).notNull()
            }
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS index_behavior_events_on_hour_of_day ON behavior_events(hour_of_day)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS index_behavior_events_on_day_of_week ON behavior_events(day_of_week)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS index_behavior_events_on_created_at ON behavior_events(created_at)")

            // MARK: - Operation Events
            try db.create(table: "operation_events", ifNotExists: true) { t in
                t.primaryKey("id", .text).notNull()
                t.column("correlation_id", .text).notNull()
                t.column("operation", .text).notNull()
                t.column("entity_type", .text).notNull()
                t.column("entity_id", .text)
                t.column("source", .text).notNull()
                t.column("status", .text).notNull()
                t.column("message", .text).notNull()
                t.column("payload_json", .text).notNull().defaults(to: "{}")
                t.column("created_at", .double).notNull()
            }
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS index_operation_events_on_correlation_id ON operation_events(correlation_id)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS index_operation_events_on_entity_type ON operation_events(entity_type)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS index_operation_events_on_status ON operation_events(status)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS index_operation_events_on_created_at ON operation_events(created_at)")
        }
    }
}
