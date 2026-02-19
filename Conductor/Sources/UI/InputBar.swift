import SwiftUI

struct InputBar: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var speechManager = SpeechManager.shared
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    speechManager.toggleListening()
                } label: {
                    Image(systemName: speechManager.isListening ? "waveform.circle.fill" : "mic.circle")
                        .font(.title2)
                        .foregroundColor(speechManager.isListening ? .red : .secondary)
                }
                .buttonStyle(.plain)
                .help(speechManager.isListening ? "Stop listening" : "Voice input")

                HStack(spacing: 8) {
                    TextField("Message Conductor…", text: $appState.currentInput, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...6)
                        .focused($isFocused)
                        .onSubmit {
                            appState.sendMessage(appState.currentInput)
                        }

                    if appState.isLoading {
                        ProgressView()
                            .scaleEffect(0.75)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button {
                    appState.startNewConversation()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("New Conversation")

                Button {
                    appState.sendMessage(appState.currentInput)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(appState.currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appState.isLoading)
                .help("Send")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay { keyboardShortcutProxy }
        .onAppear {
            isFocused = true
            speechManager.onTextRecognized = { text in
                appState.currentInput = text
                isFocused = true
            }
        }
    }

    private var keyboardShortcutProxy: some View {
        Button("") {
            appState.sendMessage(appState.currentInput)
        }
        .keyboardShortcut(.return, modifiers: [.command])
        .frame(width: 0, height: 0)
        .opacity(0)
    }
}
