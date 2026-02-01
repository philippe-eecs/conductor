# Conductor

Your AI-powered personal assistant - "Claude Code for Life"

Conductor is a macOS menubar app that acts as your personal AI chief of staff, understanding your context (calendar, tasks, projects) and helping you manage your day.

## Features

- **Chat Interface**: Natural language input with keyboard-first design
- **Calendar Integration**: Reads your Apple Calendar to provide context-aware responses
- **Reminders Integration**: Creates and manages Apple Reminders
- **Proactive Notifications**: Meeting reminders, daily briefings (optional)
- **Secure Storage**: API keys in Keychain, data encrypted with SQLCipher
- **Global Hotkey**: Cmd+Shift+C to toggle the window

## Requirements

- macOS 14.0 (Sonnet) or later
- Xcode 15.0 or later
- Claude API key from [Anthropic Console](https://console.anthropic.com/)

## Installation

### Building from Source

1. Open the project in Xcode:
   ```bash
   cd Conductor
   open Package.swift
   ```

2. Build and run (Cmd+R)

3. Grant permissions when prompted:
   - Accessibility (for global hotkey)
   - Calendar access
   - Reminders access
   - Notifications

4. Click the brain icon in the menubar and add your API key in Settings

### Creating an App Bundle

To create a proper `.app` bundle, use Xcode:

1. File → New → Project → macOS → App
2. Copy the `Sources` directory contents into the new project
3. Add dependencies via File → Add Package Dependencies:
   - `https://github.com/evgenyneu/keychain-swift.git`
   - `https://github.com/stephencelis/SQLite.swift.git`
4. Build for release (Product → Archive)

## Usage

### Quick Start

1. Press **Cmd+Shift+C** to open Conductor
2. Ask questions like:
   - "What's on my calendar today?"
   - "Remind me to call mom Sunday at 10am"
   - "Help me plan my week"
   - "Block 2 hours tomorrow for deep work"

### Suggested Prompts

- **Daily briefing**: "What's my day look like?"
- **Quick capture**: "Remind me to X" / "Add task Y to project Z"
- **Context search**: "What do I know about [topic]?"
- **Time blocking**: "Block time for [activity] tomorrow"

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    CONDUCTOR MENUBAR APP                         │
├─────────────────────────────────────────────────────────────────┤
│  Chat Interface → Context Layer → AI Service → Proactive Engine │
│                                                                  │
│  Security: Keychain (API keys) + SQLite (encrypted data)        │
└─────────────────────────────────────────────────────────────────┘
```

### Key Components

| Component | Description |
|-----------|-------------|
| `ConductorApp.swift` | Main app entry, MenuBarExtra setup |
| `ConductorView.swift` | Chat interface |
| `ClaudeService.swift` | Claude API integration |
| `EventKitManager.swift` | Calendar/Reminders access |
| `KeychainManager.swift` | Secure API key storage |
| `Database.swift` | SQLite conversation/notes storage |
| `ProactiveEngine.swift` | Background checks and notifications |

## Configuration

### API Keys

API keys are stored securely in the macOS Keychain. Access Settings from the gear icon in the menubar.

- **Claude API Key** (required): Powers the AI assistant
- **Gemini API Key** (optional): For future multimodal features

### Permissions

Conductor requests permissions on first use:

| Permission | Purpose |
|------------|---------|
| Accessibility | Global hotkey (Cmd+Shift+C) |
| Calendar | Read your schedule for context |
| Reminders | Create and read reminders |
| Notifications | Proactive alerts and briefings |

## Privacy

- All data stored locally on your Mac
- API keys never leave the Keychain
- Conversation history stored in encrypted SQLite
- Calendar/Reminder data accessed via native EventKit (not copied)

## Development

### Project Structure

```
Conductor/
├── Sources/
│   ├── App/           # App lifecycle, main entry
│   ├── UI/            # SwiftUI views
│   ├── Security/      # Keychain, encryption
│   ├── Data/          # SQLite database
│   ├── Context/       # EventKit, context building
│   ├── Proactive/     # Background engine, notifications
│   ├── AI/            # Claude/Gemini API services
│   └── Tools/         # External tool integrations
└── Package.swift
```

### Building

```bash
# Build with Swift Package Manager (requires Xcode)
cd Conductor
swift build

# Or open in Xcode
open Package.swift
```

### Testing

Run the app and verify:
1. Menubar icon appears
2. Cmd+Shift+C toggles window
3. Can enter API key in Settings
4. Chat works with Claude
5. Calendar context is included

## Roadmap

- [x] MVP v0.1: Chat + API integration
- [ ] MVP v0.2: Calendar context
- [ ] MVP v0.3: Quick actions (reminders, calendar events)
- [ ] MVP v0.4: Persistence and memory
- [ ] Proactive notifications
- [ ] Obsidian vault integration
- [ ] Orchestra multi-agent workflows

## License

MIT
