# Development

## Running Conductor

### `swift run` (fast, limited)

You can run the executable directly:

```sh
swift run --disable-sandbox Conductor
```

However, macOS privacy prompts (TCC) for **Calendar** and **Reminders** require Conductor to run as a real `.app` bundle.
When launched via `swift run`, permission prompts may not appear (and some system frameworks may throw exceptions).

### Run as a `.app` (recommended for permissions)

Use the dev launcher:

```sh
scripts/dev-run-app.sh
```

This builds the debug binary, wraps it in a minimal `.app` bundle using `Sources/Info.plist`, ad-hoc signs it, and launches it.

#### Stable permission prompts (recommended)

macOS stores Calendar/Reminders permissions in its privacy database (TCC) and the decision can be tied to the app’s code identity.
For more consistent behavior across rebuilds, sign the dev app with a stable identity:

```sh
export CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)"
scripts/dev-run-app.sh
```

To find available identities:

```sh
security find-identity -p codesigning -v
```

## Calendar/Reminders access (how it works)

- Conductor uses EventKit (`EKEventStore`) to read and write:
  - Calendar events: `EKEventStore.authorizationStatus(for: .event)`
  - Reminders: `EKEventStore.authorizationStatus(for: .reminder)`
- On macOS 14+, EventKit distinguishes:
  - **Full Access**: Conductor can read your schedule/tasks (required for schedule/context features).
  - **Write Only**: Conductor can create items but cannot read existing ones (schedule/context remains limited).
- Permission prompts are requested via:
  - `requestFullAccessToEvents()` / `requestFullAccessToReminders()` (macOS 14+)
  - `requestAccess(to:)` on older macOS versions

Conductor only includes calendar/reminders data in assistant context when:
- access is granted, and
- the corresponding “read enabled” preference is on, and
- (if secure mode is enabled) you approve the context before sending.
