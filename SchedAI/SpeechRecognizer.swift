//
//  SpeechRecognizer.swift
//  SchedAI
//

import Foundation
import AVFoundation
import Speech
import Combine

@MainActor
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
        if microphonePermissionGranted() {
            micOK = true
        } else {
            micOK = await requestMicPermission()
        }

        let ok = speechOK && micOK
        self.isAuthorized = ok
        self.errorMessage = ok ? nil : "Speech Recognition and Microphone access are required for voice planning."
        return ok
    }

    func refreshAuthorizationStatus() {
        isAuthorized = SFSpeechRecognizer.authorizationStatus() == .authorized
            && microphonePermissionGranted()
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
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            }
        }
    }

    private func microphonePermissionGranted() -> Bool {
        if #available(iOS 17.0, *) {
            return AVAudioApplication.shared.recordPermission == .granted
        } else {
            return AVAudioSession.sharedInstance().recordPermission == .granted
        }
    }

    // MARK: - Recording

    func start(update: @escaping (String) -> Void) {
        guard !isRecording else { return }
        guard isAuthorized else {
            errorMessage = "Voice planning needs Speech Recognition and Microphone access."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech Recognition is not available right now."
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
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            audioRequest.append(buffer)
        }

        recognitionTask?.cancel()
        recognitionTask = recognizer.recognitionTask(with: audioRequest) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let hadError = error != nil

            Task { @MainActor in
                guard let self else { return }
                self.handleRecognitionUpdate(text: text, isFinal: isFinal, hadError: hadError)
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            stopAudio(cancelTask: true, finishTask: false, clearTranscript: false)
            errorMessage = "Could not start recording."
            return
        }

        isRecording = true
    }

    private func handleRecognitionUpdate(text: String?, isFinal: Bool, hadError: Bool) {
        if let text {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                transcript = trimmed
                updateHandler?(trimmed)
            }
        }

        if hadError || isFinal {
            stopAudio(cancelTask: false, finishTask: false, clearTranscript: false)
            if hadError {
                errorMessage = "Speech Recognition stopped unexpectedly."
            }
        }
    }

    /// Stops recording. DOES NOT clear `transcript` or send an empty update.
    func stop() {
        guard isRecording else { return }
        stopAudio(cancelTask: false, finishTask: true, clearTranscript: false)
    }

    /// Stops any active recognition and clears local speech state so a new planning pass starts cleanly.
    func resetForFreshInput() {
        stopAudio(cancelTask: true, finishTask: false, clearTranscript: true)
        errorMessage = nil
    }

    private func stopAudio(cancelTask: Bool, finishTask: Bool, clearTranscript: Bool) {
        request?.endAudio()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        if cancelTask {
            recognitionTask?.cancel()
        } else if finishTask {
            recognitionTask?.finish()
        }

        recognitionTask = nil
        request = nil
        updateHandler = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false

        if clearTranscript {
            transcript = ""
        }
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
