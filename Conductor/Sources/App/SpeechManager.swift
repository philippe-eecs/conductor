import AVFoundation
import Speech

@MainActor
final class SpeechManager: ObservableObject {
    static let shared = SpeechManager()

    // Text-to-Speech (TTS)
    @Published var isEnabled: Bool = false
    @Published var isSpeaking: Bool = false
    @Published var selectedVoice: String = ""

    // Speech-to-Text (STT)
    @Published var isListening: Bool = false
    @Published var recognizedText: String = ""
    @Published var micPermissionDenied: Bool = false
    @Published var speechPermissionDenied: Bool = false

    private let synthesizer = AVSpeechSynthesizer()
    private var delegate: SpeechDelegate?
    private var currentUtterance: AVSpeechUtterance?

    // Speech recognition
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    var onTextRecognized: ((String) -> Void)?

    private init() {
        delegate = SpeechDelegate(
            onStart: { [weak self] utterance in
                Task { @MainActor in
                    guard let self else { return }
                    guard let current = self.currentUtterance, current === utterance else { return }
                    self.isSpeaking = true
                }
            },
            onFinish: { [weak self] utterance in
                Task { @MainActor in
                    guard let self else { return }
                    guard let current = self.currentUtterance, current === utterance else { return }
                    self.isSpeaking = false
                    self.currentUtterance = nil
                }
            },
            onCancel: { [weak self] utterance in
                Task { @MainActor in
                    guard let self else { return }
                    guard let current = self.currentUtterance, current === utterance else { return }
                    self.isSpeaking = false
                    self.currentUtterance = nil
                }
            }
        )
        synthesizer.delegate = delegate

        // Load preference
        isEnabled = (try? Database.shared.getPreference(key: "voice_enabled")) == "true"
        selectedVoice = (try? Database.shared.getPreference(key: "voice_id")) ?? ""

        // Initialize speech recognizer
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    }

    var availableVoices: [(id: String, name: String)] {
        AVSpeechSynthesisVoice.speechVoices()
            .sorted { lhs, rhs in
                if lhs.name == rhs.name { return lhs.language < rhs.language }
                return lhs.name < rhs.name
            }
            .map { voice in
                (voice.identifier, "\(voice.name) (\(voice.language))")
            }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        try? Database.shared.setPreference(key: "voice_enabled", value: enabled ? "true" : "false")
        if !enabled {
            stop()
        }
    }

    func setVoice(_ voiceId: String) {
        selectedVoice = voiceId
        try? Database.shared.setPreference(key: "voice_id", value: voiceId)
        if isSpeaking {
            stop()
        }
    }

    func speak(_ text: String) {
        guard isEnabled else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        stop()

        let utterance = AVSpeechUtterance(string: trimmed)
        if let voice = resolvedVoice() {
            utterance.voice = voice
        }

        currentUtterance = utterance
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        currentUtterance = nil
        isSpeaking = false
    }

    private func resolvedVoice() -> AVSpeechSynthesisVoice? {
        guard !selectedVoice.isEmpty else { return nil }
        return AVSpeechSynthesisVoice(identifier: selectedVoice)
    }

    // MARK: - Speech-to-Text (Microphone Input)

    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    func startListening() {
        // Check if already listening
        guard !isListening else { return }

        // Stop any TTS first
        stop()

        // Request permissions and start
        Task {
            await requestSpeechPermission()
            await requestMicrophonePermission()

            guard !speechPermissionDenied, !micPermissionDenied else {
                return
            }

            await startRecognition()
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
    }

    private func requestSpeechPermission() async {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            speechPermissionDenied = false
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
            speechPermissionDenied = !granted
        default:
            speechPermissionDenied = true
        }
    }

    private func requestMicrophonePermission() async {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            micPermissionDenied = false
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            micPermissionDenied = !granted
        default:
            micPermissionDenied = true
        }
    }

    private func startRecognition() async {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            print("Speech recognizer not available")
            return
        }

        recognizedText = ""

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }

        recognitionRequest.shouldReportPartialResults = true

        // Configure audio session
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Install tap on audio input
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        // Start audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
        } catch {
            print("Audio engine failed to start: \(error)")
            stopListening()
            return
        }

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }

                if let result = result {
                    self.recognizedText = result.bestTranscription.formattedString
                    self.onTextRecognized?(self.recognizedText)
                }

                if error != nil || (result?.isFinal ?? false) {
                    // Don't auto-stop - let user tap to stop
                    // Only stop if there's an actual error
                    if error != nil {
                        self.stopListening()
                    }
                }
            }
        }
    }
}

private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    let onStart: (AVSpeechUtterance) -> Void
    let onFinish: (AVSpeechUtterance) -> Void
    let onCancel: (AVSpeechUtterance) -> Void

    init(
        onStart: @escaping (AVSpeechUtterance) -> Void,
        onFinish: @escaping (AVSpeechUtterance) -> Void,
        onCancel: @escaping (AVSpeechUtterance) -> Void
    ) {
        self.onStart = onStart
        self.onFinish = onFinish
        self.onCancel = onCancel
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        onStart(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onCancel(utterance)
    }
}
