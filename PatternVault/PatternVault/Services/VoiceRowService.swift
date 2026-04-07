//
//  VoiceRowService.swift
//  PatternVault
//
//  Tap-to-talk speech recognition to capture row/round numbers hands-free.
//  Uses SFSpeechRecognizer + AVAudioEngine; parses "row 12", "round 5", etc.
//

import AVFoundation
import Foundation
import Speech
import SwiftUI

/// Authorization status for speech recognition (mirrors SFSpeechRecognizerAuthorizationStatus for SwiftUI).
enum VoiceRowAuthorizationStatus {
    case notDetermined
    case denied
    case restricted
    case authorized
}

@MainActor
final class VoiceRowService: ObservableObject {

    @Published private(set) var authorizationStatus: VoiceRowAuthorizationStatus = .notDetermined
    @Published private(set) var isListening = false
    @Published private(set) var errorMessage: String?

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let synthesizer = AVSpeechSynthesizer()

    private static let listenTimeout: TimeInterval = 6.0
    private static let locale = Locale(identifier: "en-US")

    init() {
        recognizer = SFSpeechRecognizer(locale: Self.locale)
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        let speechStatus = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        let status: VoiceRowAuthorizationStatus
        switch speechStatus {
        case .notDetermined: status = .notDetermined
        case .denied: status = .denied
        case .restricted: status = .restricted
        case .authorized: status = .authorized
        @unknown default: status = .denied
        }
        authorizationStatus = status
        if status != .authorized {
            errorMessage = messageForAuthorization(status)
            return
        }
        // Microphone permission
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .denied:
                authorizationStatus = .denied
                errorMessage = "Microphone access is denied. Enable it in Settings to use voice row counting."
                return
            case .granted:
                break
            case .undetermined:
                let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                    AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
                }
                if !granted {
                    authorizationStatus = .denied
                    errorMessage = "Microphone access is required for voice row counting."
                }
            @unknown default:
                authorizationStatus = .denied
                errorMessage = "Microphone access could not be determined."
            }
        } else {
            let session = AVAudioSession.sharedInstance()
            switch session.recordPermission {
            case .denied:
                authorizationStatus = .denied
                errorMessage = "Microphone access is denied. Enable it in Settings to use voice row counting."
                return
            case .granted:
                break
            case .undetermined:
                let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                    session.requestRecordPermission { cont.resume(returning: $0) }
                }
                if !granted {
                    authorizationStatus = .denied
                    errorMessage = "Microphone access is required for voice row counting."
                }
            @unknown default:
                authorizationStatus = .denied
                errorMessage = "Microphone access could not be determined."
            }
        }
    }

    private func messageForAuthorization(_ status: VoiceRowAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "Checking permissions…"
        case .denied: return "Speech recognition was denied. Enable it in Settings to log rows by voice."
        case .restricted: return "Speech recognition is not available on this device."
        case .authorized: return ""
        }
    }

    // MARK: - Listen for row number

    /// Starts listening; returns the parsed row/round number when the user finishes speaking (or nil on error/timeout).
    func listenForRowNumber() async -> Int? {
        if authorizationStatus != .authorized {
            await requestAuthorization()
            if authorizationStatus != .authorized {
                return nil
            }
        }
        guard let recognizer = recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition is not available."
            return nil
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Could not set up audio: \(error.localizedDescription)"
            return nil
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest = request
        request.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            errorMessage = "Could not start microphone: \(error.localizedDescription)"
            stopListening()
            return nil
        }
        isListening = true
        errorMessage = nil
        listeningFulfilled = false

        let result: Int? = await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Int?, Never>) in
                let complete: (Int?) -> Void = { [weak self] value in
                    Task { @MainActor in
                        self?.finishListeningAndResume(continuation: cont, value: value)
                    }
                }
                recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                    if let error = error {
                        let ns = error as NSError
                        // Speech framework cancellation (domain/code may not be in Swift scope on all SDKs)
                        let isCancelled = ns.domain == "NSSpeechRecognizerErrorDomain" && ns.code == 1
                        if isCancelled {
                            complete(nil)
                            return
                        }
                        Task { @MainActor in
                            self.errorMessage = error.localizedDescription
                        }
                        complete(nil)
                        return
                    }
                    guard let result = result, result.isFinal else { return }
                    let transcript = result.bestTranscription.formattedString
                    complete(Self.parseRowNumber(from: transcript))
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(Self.listenTimeout * 1_000_000_000))
                    self.errorMessage = "Couldn't hear a number."
                    self.finishListeningAndResumeIfNeeded(continuation: cont, value: nil)
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.stopListening()
            }
        }

        isListening = false
        return result
    }

    private var listeningFulfilled = false

    private func finishListeningAndResume(continuation: CheckedContinuation<Int?, Never>, value: Int?) {
        guard !listeningFulfilled else { return }
        listeningFulfilled = true
        stopListening()
        continuation.resume(returning: value)
    }

    private func finishListeningAndResumeIfNeeded(continuation: CheckedContinuation<Int?, Never>, value: Int?) {
        guard !listeningFulfilled else { return }
        listeningFulfilled = true
        stopListening()
        continuation.resume(returning: value)
    }

    func stopListening() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }

    /// Extracts a row or round number from transcribed text. Prefers "row N" / "round N"; otherwise last integer.
    static func parseRowNumber(from text: String) -> Int? {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.isEmpty { return nil }
        // Prefer "row 12" or "round 5"
        let rowRoundPattern = #"(?:row|round|rnd)\s*(\d+)"#
        if let regex = try? NSRegularExpression(pattern: rowRoundPattern),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let range = Range(match.range(at: 1), in: lower),
           let n = Int(lower[range]), n > 0 {
            return n
        }
        // Any integer (take the last one, often the user says "row 12" and we get "12")
        let digitPattern = #"\d+"#
        if let regex = try? NSRegularExpression(pattern: digitPattern) {
            let matches = regex.matches(in: lower, range: NSRange(lower.startIndex..., in: lower))
            if let last = matches.last, let range = Range(last.range, in: lower), let n = Int(lower[range]), n > 0 {
                return n
            }
        }
        return nil
    }

    // MARK: - Spoken confirmation

    func speakConfirmation(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Self.locale.identifier)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }
}
