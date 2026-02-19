# Changelog

All notable changes to Conductor will be documented in this file.

## [2.0.0] - 2026-02-18

Complete rewrite from v1. New architecture built on Claude Code CLI as a subprocess.

### Added
- **Blink Engine**: Background polling loop (configurable interval) that reviews context and makes decisions (silent/notify/agent)
- **MCP Server**: In-process server providing 9 tools for Claude to read/write app data
- **Agent Dispatcher**: Background AI task execution on specific TODOs with deliverable verification
- **Project & TODO management**: Full CRUD via chat or direct UI interaction
- **Pre-fetched context**: Chat sessions start with calendar, projects, and TODOs already loaded
- **Operation receipts**: Inline confirmation cards for every create/update action with Undo support
- **Task detail inspector**: Click any TODO to see details, deliverables, and agent history
- **Chat toggle**: Hide/show chat panel (Cmd+E) to focus on calendar or project views
- **Settings sheet**: Compact overlay instead of full-screen replacement
- **Voice input**: Speech-to-text for hands-free interaction
- **Release build script**: Universal binary (arm64 + x86_64) with ad-hoc or Developer ID signing

### Changed
- Replaced direct Anthropic API calls with Claude Code CLI subprocess
- Session continuity via `--resume` instead of manual message history
- Database migrated from SQLite.swift to GRDB
- All data models use auto-incrementing Int64 IDs

### Removed
- Direct API key management (Claude Code handles authentication)
- KeychainSwift dependency
- SQLCipher encryption (using plain SQLite via GRDB)
- v1 ProactiveEngine (replaced by Blink Engine)

## [1.0.0] - 2026-01-06

Initial release. Preserved on `v1-archive` branch.
