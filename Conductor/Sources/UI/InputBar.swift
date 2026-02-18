import SwiftUI

struct InputBar: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var speechManager = SpeechManager.shared
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Mic button
            Button {
                speechManager.toggleListening()
            } label: {
                Image(systemName: speechManager.isListening ? "mic.fill" : "mic")
                    .foregroundColor(speechManager.isListening ? .red : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help(speechManager.isListening ? "Stop listening" : "Voice input")

            TextField("Message...", text: $appState.currentInput, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isFocused)
                .onSubmit {
                    if !NSEvent.modifierFlags.contains(.shift) {
                        appState.sendMessage(appState.currentInput)
                    }
                }

            Button {
                appState.sendMessage(appState.currentInput)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(appState.currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appState.isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            isFocused = true
            speechManager.onTextRecognized = { text in
                appState.currentInput = text
            }
        }
    }
}
