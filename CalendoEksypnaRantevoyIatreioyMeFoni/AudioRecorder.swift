import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class AudioRecorder {
    enum RecorderError: LocalizedError {
        case permissionDenied
        case couldNotStart

        var errorDescription: String? {
            switch self {
            case .permissionDenied: "Δεν δόθηκε πρόσβαση στο μικρόφωνο. Μπορείτε να την ενεργοποιήσετε από τις Ρυθμίσεις."
            case .couldNotStart: "Η εγγραφή δεν μπόρεσε να ξεκινήσει. Δοκιμάστε ξανά."
            }
        }
    }

    var isRecording = false
    var isPaused = false
    var isInterrupted = false
    var elapsed: TimeInterval = 0
    var level: Float = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var outputURL: URL?

    func requestPermissionAndStart() async throws {
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else { throw RecorderError.permissionDenied }
        try start()
    }

    func togglePause() {
        guard let recorder else { return }
        if isPaused {
            recorder.record()
            isPaused = false
        } else {
            recorder.pause()
            isPaused = true
        }
    }

    func finish() -> URL? {
        recorder?.stop()
        stopTimer()
        isRecording = false
        isPaused = false
        deactivateSession()
        return outputURL
    }

    func cancel() {
        let url = finish()
        if let url { try? FileManager.default.removeItem(at: url) }
        outputURL = nil
    }

    func handleBackgrounding() -> URL? {
        guard isRecording else { return nil }
        isInterrupted = true
        return finish()
    }

    private func start() throws {
        let directory = LocalDraftRepository.recordingsDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString).m4a")
        let session = AVAudioSession.sharedInstance()
        // `.duckOthers` and `.spokenAudio` are not valid together with the record-only
        // category on physical iPhones (it produces OSStatus -50). A measurement session
        // is purpose-built for clear mono microphone capture and does not alter other audio.
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true, options: [])
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw RecorderError.couldNotStart }
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        self.recorder = recorder
        outputURL = url
        elapsed = 0
        isRecording = true
        isPaused = false
        isInterrupted = false
        startTimer()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let recorder = self.recorder else { return }
                if !self.isPaused { self.elapsed = recorder.currentTime }
                recorder.updateMeters()
                let power = recorder.averagePower(forChannel: 0)
                self.level = max(0.08, min(1, (power + 55) / 55))
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        level = 0
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

@MainActor
@Observable
final class AudioPreviewPlayer {
    var isPlaying = false
    private var player: AVAudioPlayer?

    func toggle(url: URL) {
        if isPlaying {
            player?.stop()
            isPlaying = false
            return
        }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
            isPlaying = true
        } catch {
            isPlaying = false
        }
    }
}
