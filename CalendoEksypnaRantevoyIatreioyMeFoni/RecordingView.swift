import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct RecordingView: View {
    let store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var recorder = AudioRecorder()
    @State private var errorMessage: String?
    @State private var pendingAudioURL: URL?
    @State private var isTranscribing = false

    var body: some View {
        ZStack {
            CalendoBackground()
            VStack(spacing: 28) {
                recordingHeader
                Spacer()
                WaveformView(level: recorder.level, isPaused: recorder.isPaused)
                timer
                prompt
                Spacer()
                controls
            }
            .padding(24)
        }
        .navigationBarBackButtonHidden()
        .task { await beginRecording() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { recorder.handleBackgrounding() }
        }
        .onChange(of: recorder.runtimeError) { _, message in
            if let message { errorMessage = message }
        }
        .alert("Δεν ολοκληρώθηκε", isPresented: errorBinding) {
            if pendingAudioURL != nil {
                Button("Νέα προσπάθεια μετατροπής") { Task { await transcribePendingRecording() } }
            }
            Button("Χειροκίνητη συμπλήρωση") { continueManually() }
            Button("Ρυθμίσεις") { openSettings() }
            Button("Ακύρωση", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Δεν είναι διαθέσιμη η εγγραφή.")
        }
    }

    private var recordingHeader: some View {
        HStack {
            Button("Ακύρωση") {
                discardPendingRecording()
                recorder.cancel()
                store.finishFlow()
            }
            .foregroundStyle(.secondary)
            .disabled(isTranscribing)
            Spacer()
            Label(recordingStatus, systemImage: statusIcon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isTranscribing ? CalendoColor.teal : (recorder.isRecording ? .red : .secondary))
        }
    }

    private var timer: some View {
        Text(formattedElapsed)
            .font(.system(size: 52, weight: .semibold, design: .rounded).monospacedDigit())
            .contentTransition(.numericText())
            .accessibilityLabel("Χρόνος εγγραφής \(formattedElapsed)")
    }

    private var prompt: some View {
        VStack(spacing: 8) {
            Text(isTranscribing ? "Μετατροπή σε κείμενο…" : "Μιλήστε φυσικά στα ελληνικά")
                .font(.title2.bold())
            Text(isTranscribing
                 ? "Το AssemblyAI μετατρέπει με ασφάλεια την εγγραφή σας."
                 : "«Αύριο στις δέκα, Μαρία Κωνσταντίνου, για σαράντα πέντε λεπτά»")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if isTranscribing { ProgressView().padding(.top, 8) }
        }
    }

    private var controls: some View {
        HStack(spacing: 18) {
            Button {
                recorder.togglePause()
            } label: {
                Image(systemName: recorder.isPaused ? "play.fill" : "pause.fill")
                    .font(.title2).frame(width: 58, height: 58)
            }
            .buttonStyle(.bordered)
            .disabled(!recorder.isRecording || isTranscribing)
            .accessibilityLabel(recorder.isPaused ? "Συνέχεια εγγραφής" : "Παύση εγγραφής")

            Button {
                Task { await finishAndTranscribe() }
            } label: {
                Label("Τέλος", systemImage: "checkmark")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 9)
            }
            .primaryActionStyle()
            .disabled(!recorder.isRecording || isTranscribing)
        }
    }

    private var recordingStatus: String {
        if isTranscribing { return "Μετατροπή με AssemblyAI" }
        if !recorder.isRecording { return "Προετοιμασία μικροφώνου" }
        return recorder.isPaused ? "Σε παύση" : "Ηχογράφηση"
    }

    private var statusIcon: String {
        isTranscribing ? "waveform.badge.magnifyingglass" : (recorder.isRecording ? "circle.fill" : "hourglass")
    }

    private var formattedElapsed: String {
        let seconds = Int(recorder.elapsed)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func beginRecording() async {
        do { try await recorder.requestPermissionAndStart() }
        catch { errorMessage = error.localizedDescription }
    }

    private func finishAndTranscribe() async {
        do {
            pendingAudioURL = try recorder.finish()
            await transcribePendingRecording()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func transcribePendingRecording() async {
        guard let audioURL = pendingAudioURL, !isTranscribing else { return }
        isTranscribing = true
        defer { isTranscribing = false }
        do {
            let token = try await store.google.validAccessToken()
            let transcript = try await AssemblyAITranscriptionService().transcribe(audioURL: audioURL, token: token)
            store.reviewRecording(audioURL: audioURL, transcript: transcript)
            pendingAudioURL = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func continueManually() {
        discardPendingRecording()
        recorder.cancel()
        store.reviewManually()
    }

    private func discardPendingRecording() {
        guard let pendingAudioURL else { return }
        try? FileManager.default.removeItem(at: pendingAudioURL)
        self.pendingAudioURL = nil
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct WaveformView: View {
    let level: Float
    let isPaused: Bool
    private let factors: [CGFloat] = [0.35, 0.7, 0.48, 1, 0.62, 0.82, 0.42, 0.9, 0.55]

    var body: some View {
        HStack(spacing: 7) {
            ForEach(factors.indices, id: \.self) { index in
                Capsule()
                    .fill(CalendoColor.teal.gradient)
                    .frame(width: 7, height: barHeight(index))
            }
        }
        .frame(height: 116)
        .animation(.spring(response: 0.18), value: level)
        .accessibilityHidden(true)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let active = isPaused ? 0.12 : CGFloat(level)
        return max(16, 96 * factors[index] * active + 14)
    }
}
