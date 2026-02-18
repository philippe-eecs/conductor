import AVFoundation
import Speech

@MainActor
final class SpeechManager: ObservableObject {
    static let shared = SpeechManager()

    @Published var isListening: Bool = false
    @Published var recognizedText: String = ""
    @Published var micPermissionDenied: Bool = false
    @Published var speechPermissionDenied: Bool = false

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    var onTextRecognized: ((String) -> Void)?

    private init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    }

    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    func startListening() {
        guard !isListening else { return }

        Task {
            await requestSpeechPermission()
            await requestMicrophonePermission()

            guard !speechPermissionDenied, !micPermissionDenied else { return }
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
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            Log.speech.error("Speech recognizer not available")
            return
        }

        recognizedText = ""

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }

        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
        } catch {
            Log.speech.error("Audio engine failed to start: \(error.localizedDescription, privacy: .public)")
            stopListening()
            return
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }

                if let result {
                    self.recognizedText = result.bestTranscription.formattedString
                    self.onTextRecognized?(self.recognizedText)
                }

                if error != nil {
                    self.stopListening()
                }
            }
        }
    }
}
