# Conductor

AI-powered personal productivity assistant for macOS, built on [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

Manage your projects, tasks, and calendar through natural language chat. Conductor runs Claude as a subprocess with MCP tools that give it direct access to your local data.

## Quick Start

### 1. Install Claude Code

Conductor uses [Claude Code](https://docs.anthropic.com/en/docs/claude-code) as its AI engine. Install it if you haven't:

```bash
npm install -g @anthropic-ai/claude-code
```

Then authenticate (one-time setup):

```bash
claude
```

This opens a browser for OAuth login. Once you see the Claude Code REPL, you're authenticated. You can close it — Conductor will use the same session. Your credentials are stored in `~/.claude/` and Conductor's subprocess inherits them automatically.

> **Already use Claude Code?** You're all set. Skip to step 2.

### 2. Build & Run

```bash
git clone https://github.com/philippe-eecs/conductor.git
cd conductor/Conductor
scripts/dev-run-app.sh
```

Grant Calendar/Reminders permissions when prompted. The app appears in your menubar.

> **Pre-built binary:** Download `Conductor.zip` from the [latest release](../../releases/latest), unzip, then:
> ```bash
> xattr -cr Conductor.app && open Conductor.app
> ```

## What It Does

**Chat** — Talk to Claude with full context of your day. It knows your calendar, projects, and TODOs before you ask.

```
> What's on my calendar today?
> Create a project called Video ViTok with 3 research tasks
> Help me plan my afternoon around my meetings
> Block 2 hours tomorrow morning for deep work
```

**Projects & TODOs** — Sidebar for managing projects. Click any task to see details, deliverables, and agent history.

**Blink Engine** — Background loop (every 15 min, configurable) that reviews your context and decides:
- **Silent** (default) — nothing to do
- **Notify** — macOS notification for urgent items (meeting in 10 min, overdue task)
- **Agent** — dispatches a background Claude session to work on a specific TODO

**Keyboard shortcuts:**

| Shortcut | Action |
|----------|--------|
| Cmd+N | New conversation |
| Cmd+E | Toggle chat panel |
| Cmd+T | Toggle Today panel |
| Cmd+, | Settings |
| Esc | Dismiss panels |

## Architecture

```
Conductor.app
├── Chat ── Claude CLI subprocess (--resume for session continuity)
│           Pre-fetched context + 9 MCP tools for CRUD
│
├── Blink Engine ── Timer loop → one-shot Claude → JSON decision
│                   Routes: silent | notify | dispatch agent
│
├── Agent Dispatcher ── Fresh Claude session per TODO
│                       Records results + cost, verifies deliverables
│
├── MCP Server ── In-process (Network.framework, 127.0.0.1)
│                 Bridges Claude CLI ↔ app database + EventKit
│
└── Data ── GRDB/SQLite
            Projects, TODOs, Deliverables, Messages, BlinkLogs, AgentRuns
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
│   └── build-release-app.sh    # Release universal binary (.zip)
└── Package.swift
```

```bash
# Run tests
cd Conductor && swift test

# Build release (universal arm64+x86_64, version-stamped)
scripts/build-release-app.sh
```

## Privacy

- All data stored locally in `~/Library/Application Support/Conductor/`
- Claude CLI runs as a local subprocess — no direct API calls from the app
- Calendar/Reminders accessed via native EventKit (data stays on device)
- No telemetry, no analytics, no tracking

## License

MIT
