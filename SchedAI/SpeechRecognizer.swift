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
        if isAuthorized { return true }

        let speechOK = await requestSpeechAuthorization()
        let micOK    = await requestMicPermission()

        let ok = speechOK && micOK
        self.isAuthorized = ok
        return ok
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
        guard isAuthorized else { return }

        updateHandler = update
        transcript = ""

        do {
            try configureAudioSession()
        } catch {
            return
        }

        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        recognitionTask?.cancel()
        recognitionTask = recognizer?.recognitionTask(with: request!) { [weak self] result, error in
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
                DispatchQueue.main.async { self.isRecording = false }
            }
        }

        audioEngine.prepare()
        do { try audioEngine.start() } catch { return }

        isRecording = true
    }

    /// Stops recording. DOES NOT clear `transcript` or send an empty update.
    func stop() {
        guard isRecording else { return }
        request?.endAudio()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask?.finish()
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
