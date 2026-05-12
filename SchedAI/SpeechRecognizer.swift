//
//  SpeechRecognizer.swift
//  SchedAI
//

import Foundation
import AVFoundation
import Speech
import Combine

final class SpeechRecognizer: NSObject, ObservableObject {
    @Published var isAuthorized = false
    @Published var isRecording  = false
    @Published var transcript   = ""
    @Published var errorMessage: String? = nil

    private let recognizer = SFSpeechRecognizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    /// UI update callback for live transcript updates.
    private var updateHandler: ((String) -> Void)?

    // MARK: - Authorization

    /// Fire-and-forget authorization request (kept for compatibility with older call sites).
    func requestAuthorization() {
        Task { _ = await ensureAuthorized() }
    }

    /// Ensures both Speech Recognition + Microphone permission are granted.
    /// Returns `true` if authorized, `false` otherwise.
    @MainActor
    func ensureAuthorized() async -> Bool {
        refreshAuthorizationStatus()
        if isAuthorized { return true }

        let speechOK: Bool
        if SFSpeechRecognizer.authorizationStatus() == .authorized {
            speechOK = true
        } else {
            speechOK = await requestSpeechAuthorization()
        }

        let micOK: Bool
        if AVAudioSession.sharedInstance().recordPermission == .granted {
            micOK = true
        } else {
            micOK = await requestMicPermission()
        }

        let ok = speechOK && micOK
        self.isAuthorized = ok
        self.errorMessage = ok ? nil : "Speech Recognition and Microphone access are required for voice planning."
        return ok
    }

    @MainActor
    func refreshAuthorizationStatus() {
        isAuthorized = SFSpeechRecognizer.authorizationStatus() == .authorized
            && AVAudioSession.sharedInstance().recordPermission == .granted
        if isAuthorized {
            errorMessage = nil
        }
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }

    // MARK: - Recording

    func start(update: @escaping (String) -> Void) {
        guard !isRecording else { return }
        guard isAuthorized else {
            DispatchQueue.main.async {
                self.errorMessage = "Voice planning needs Speech Recognition and Microphone access."
            }
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            DispatchQueue.main.async {
                self.errorMessage = "Speech Recognition is not available right now."
            }
            return
        }

        updateHandler = update
        transcript = ""
        errorMessage = nil

        do {
            try configureAudioSession()
        } catch {
            errorMessage = "Could not start the microphone."
            return
        }

        let audioRequest = SFSpeechAudioBufferRecognitionRequest()
        audioRequest.shouldReportPartialResults = true
        request = audioRequest

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        recognitionTask?.cancel()
        recognitionTask = recognizer.recognitionTask(with: audioRequest) { [weak self] result, error in
            guard let self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    DispatchQueue.main.async {
                        self.transcript = trimmed
                        self.updateHandler?(trimmed)   // only non-empty updates
                    }
                }
            }

            if error != nil || (result?.isFinal ?? false) {
                // Stop audio without clearing transcript.
                self.audioEngine.stop()
                self.audioEngine.inputNode.removeTap(onBus: 0)
                self.request?.endAudio()
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                DispatchQueue.main.async {
                    self.isRecording = false
                    if error != nil {
                        self.errorMessage = "Speech Recognition stopped unexpectedly."
                    }
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            audioEngine.inputNode.removeTap(onBus: 0)
            recognitionTask?.cancel()
            recognitionTask = nil
            request = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            errorMessage = "Could not start recording."
            return
        }

        isRecording = true
    }

    /// Stops recording. DOES NOT clear `transcript` or send an empty update.
    func stop() {
        guard isRecording else { return }
        request?.endAudio()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask?.finish()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false
        // Do NOT wipe transcript here.
    }

    // MARK: - Audio Session

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try? session.setPreferredInputNumberOfChannels(1)
        try? session.setPreferredSampleRate(44_100)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }
}
