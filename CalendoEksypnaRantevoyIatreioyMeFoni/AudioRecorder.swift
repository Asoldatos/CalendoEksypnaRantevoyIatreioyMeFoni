import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    enum RecorderError: LocalizedError {
        case microphonePermissionDenied
        case couldNotStart
        case recordingFailed
        case recordingTooShort

        var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                "Δεν δόθηκε πρόσβαση στο μικρόφωνο. Ενεργοποιήστε την από τις Ρυθμίσεις."
            case .couldNotStart:
                "Δεν ήταν δυνατή η εκκίνηση του μικροφώνου. Κλείστε τυχόν κλήση ή άλλη εφαρμογή που το χρησιμοποιεί και δοκιμάστε ξανά."
            case .recordingFailed:
                "Η εγγραφή δεν αποθηκεύτηκε σωστά. Δοκιμάστε ξανά."
            case .recordingTooShort:
                "Δεν καταγράφηκε αρκετός ήχος. Μιλήστε για τουλάχιστον ένα τέταρτο του δευτερολέπτου και δοκιμάστε ξανά."
            }
        }
    }

    var isRecording = false
    var isPaused = false
    var elapsed: TimeInterval = 0
    var level: Float = 0
    var runtimeError: String?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var outputURL: URL?

    func requestPermissionAndStart() async throws {
        guard await AVAudioApplication.requestRecordPermission() else {
            throw RecorderError.microphonePermissionDenied
        }
        cancel()
        try prepareRecordingDirectory()
        try configureAudioSession()

        let fileURL = LocalDraftRepository.recordingsDirectory
            .appendingPathComponent("appointment-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord(), recorder.record() else {
                throw RecorderError.couldNotStart
            }
            self.recorder = recorder
            outputURL = fileURL
            isRecording = true
            isPaused = false
            elapsed = 0
            runtimeError = nil
            startMetering()
        } catch let error as RecorderError {
            cleanupFailedRecording(at: fileURL)
            throw error
        } catch {
            NSLog("Calendo microphone recording setup failed: %@", error.localizedDescription)
            cleanupFailedRecording(at: fileURL)
            throw RecorderError.couldNotStart
        }
    }

    func togglePause() {
        guard let recorder, isRecording else { return }
        if isPaused {
            guard recorder.record() else {
                runtimeError = RecorderError.recordingFailed.errorDescription
                cancel()
                return
            }
            isPaused = false
        } else {
            recorder.pause()
            isPaused = true
        }
    }

    func finish() throws -> URL {
        guard let recorder, let outputURL else { throw RecorderError.recordingFailed }
        let duration = recorder.currentTime
        recorder.stop()
        stopMetering()
        isRecording = false
        isPaused = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        self.recorder = nil
        self.outputURL = nil
        let fileSize = (try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard duration >= 0.25,
              FileManager.default.fileExists(atPath: outputURL.path),
              fileSize > 256 else {
            cleanupFailedRecording(at: outputURL)
            throw RecorderError.recordingTooShort
        }
        return outputURL
    }

    func cancel() {
        recorder?.stop()
        recorder = nil
        stopMetering()
        isRecording = false
        isPaused = false
        if let outputURL { cleanupFailedRecording(at: outputURL) }
        outputURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func handleBackgrounding() {
        guard isRecording else { return }
        runtimeError = "Η εγγραφή σταμάτησε επειδή το Calendo πέρασε στο παρασκήνιο."
        cancel()
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor [weak self] in
            if let error { NSLog("Calendo audio encoding failed: %@", error.localizedDescription) }
            self?.runtimeError = RecorderError.recordingFailed.errorDescription
            self?.cancel()
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default, options: [])
        try session.setActive(true)
    }

    private func prepareRecordingDirectory() throws {
        try FileManager.default.createDirectory(
            at: LocalDraftRepository.recordingsDirectory,
            withIntermediateDirectories: true
        )
    }

    private func startMetering() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let recorder = self.recorder, recorder.isRecording else { return }
                recorder.updateMeters()
                self.elapsed = recorder.currentTime
                let decibels = recorder.averagePower(forChannel: 0)
                self.level = max(0.08, min(1, pow(10, decibels / 28)))
            }
        }
    }

    private func stopMetering() {
        timer?.invalidate()
        timer = nil
        level = 0
    }

    private func cleanupFailedRecording(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
