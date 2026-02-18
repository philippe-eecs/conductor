import os

enum Log {
    static let mcp       = Logger(subsystem: "com.conductor.app", category: "MCP")
    static let claude    = Logger(subsystem: "com.conductor.app", category: "Claude")
    static let database  = Logger(subsystem: "com.conductor.app", category: "Database")
    static let action    = Logger(subsystem: "com.conductor.app", category: "Action")
    static let scheduler = Logger(subsystem: "com.conductor.app", category: "Scheduler")
    static let agent     = Logger(subsystem: "com.conductor.app", category: "Agent")
    static let proactive = Logger(subsystem: "com.conductor.app", category: "Proactive")
    static let eventKit  = Logger(subsystem: "com.conductor.app", category: "EventKit")
    static let mail      = Logger(subsystem: "com.conductor.app", category: "Mail")
    static let cost      = Logger(subsystem: "com.conductor.app", category: "Cost")
    static let notify    = Logger(subsystem: "com.conductor.app", category: "Notification")
    static let speech    = Logger(subsystem: "com.conductor.app", category: "Speech")
    static let app       = Logger(subsystem: "com.conductor.app", category: "App")
    static let planning  = Logger(subsystem: "com.conductor.app", category: "Planning")
}
