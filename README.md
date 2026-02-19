# Conductor

AI-powered personal productivity assistant for macOS. Uses [Claude Code](https://docs.anthropic.com/en/docs/claude-code) as its AI backbone.

Conductor is a menubar app that manages your projects, tasks, and calendar through natural language chat. It runs Claude as a subprocess with MCP tools that give it read/write access to your local data.

## Features

- **Chat workspace** — Talk to Claude with full context of your calendar, projects, and TODOs
- **Projects & TODOs** — Create and manage projects with tasks, priorities, and due dates
- **Calendar integration** — Reads Apple Calendar; can create time blocks
- **Blink Engine** — Background loop (every 15 min) that reviews your context and sends smart notifications or dispatches AI agents
- **Agent dispatch** — Kick off background AI tasks on specific TODOs
- **Reminders sync** — Reads Apple Reminders for additional context
- **Voice input** — Speech-to-text for hands-free interaction

## Requirements

- macOS 14.0 (Sonoma) or later
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated
- Calendar and Reminders permissions (prompted on first launch)

## Install

### Download (pre-built)

1. Download `Conductor.zip` from the [latest release](../../releases/latest)
2. Unzip and move `Conductor.app` to `/Applications`
3. On first launch, bypass Gatekeeper (app is ad-hoc signed):
   ```bash
   xattr -cr /Applications/Conductor.app
   open /Applications/Conductor.app
   ```
4. Grant Calendar, Reminders, and Notification permissions when prompted

### Build from source

```bash
git clone https://github.com/philippe-eecs/conductor.git
cd conductor/Conductor

# Development (debug build, launches immediately)
scripts/dev-run-app.sh

# Release (universal binary, zipped .app)
scripts/build-release-app.sh
# Output: .build/release-app/Conductor.zip
```

## Usage

Conductor lives in your menubar. Click the icon or use the keyboard to open the main window.

**Chat** — Ask anything. Claude has MCP tools to read/write your data:
- "What's on my calendar today?"
- "Create a project called Video ViTok"
- "Add 3 research TODOs to that project with high priority"
- "Help me plan my afternoon around my meetings"

**Keyboard shortcuts:**
| Shortcut | Action |
|----------|--------|
| Cmd+N | New conversation |
| Cmd+E | Toggle chat panel |
| Cmd+T | Toggle Today panel |
| Cmd+, | Settings |
| Esc | Dismiss panels |

**Blink Engine** — Runs automatically in the background. Reviews your calendar, open TODOs, and context every 15 minutes (configurable). Decisions:
- **Silent** (default) — nothing happening
- **Notify** — sends a macOS notification for urgent items (meeting in 10 min, overdue task)
- **Agent** — dispatches a background Claude session to work on a specific TODO

## Architecture

```
Conductor.app
├── Chat (Claude CLI subprocess with --resume for session continuity)
│   ├── Pre-fetched context: calendar, projects, TODOs
│   └── 9 MCP tools: get/create/update projects, TODOs, calendar, agents
│
├── Blink Engine (background timer, every 15 min)
│   ├── Gathers: calendar, TODOs, running agents, emails, recent blinks
│   ├── One-shot Claude call → JSON decision
│   └── Routes: silent | notify | dispatch agent
│
├── Agent Dispatcher (fresh Claude session per task)
│   ├── Context from specific TODO's project + deliverables
│   └── Records results + cost in database
│
├── MCP Server (in-process, Network.framework on 127.0.0.1)
│   └── Bridges Claude CLI ↔ app database + EventKit
│
└── Data (GRDB/SQLite)
    └── Projects, TODOs, Deliverables, Messages, BlinkLogs, AgentRuns
```

## Development

```
Conductor/
├── Sources/
│   ├── AI/            # ClaudeService, BlinkEngine, BlinkPromptBuilder
│   ├── Agent/         # AgentDispatcher
│   ├── App/           # AppDelegate, entry point
│   ├── Context/       # EventKitManager
│   ├── Data/          # AppDatabase, Models, Repositories
│   ├── MCP/           # MCPServer, MCPTools
│   └── UI/            # SwiftUI views
├── Tests/
├── scripts/
│   ├── dev-run-app.sh          # Debug build + launch
│   └── build-release-app.sh    # Release universal binary
└── Package.swift
```

### Running tests

```bash
cd Conductor
swift test
```

## Privacy

- All data stored locally in `~/Library/Application Support/Conductor/`
- Claude CLI runs as a local subprocess — no direct API calls from the app
- Calendar/Reminders accessed via native EventKit (data stays on device)
- No telemetry, no analytics, no network calls except Claude CLI

## License

MIT
