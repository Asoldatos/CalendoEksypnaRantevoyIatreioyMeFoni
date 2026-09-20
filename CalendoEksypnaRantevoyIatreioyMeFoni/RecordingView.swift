import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct RecordingView: View {
    let store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var recorder = AudioRecorder()
    @State private var errorMessage: String?

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
            if phase == .background, let url = recorder.handleBackgrounding() {
                store.reviewRecording(at: url)
            }
        }
        .alert("Μικρόφωνο", isPresented: errorBinding) {
            Button("Ρυθμίσεις") { openSettings() }
            Button("Χειροκίνητη συμπλήρωση") { store.reviewRecording(at: nil) }
        } message: {
            Text(errorMessage ?? "Δεν είναι διαθέσιμη η εγγραφή.")
        }
    }

    private var recordingHeader: some View {
        HStack {
            Button("Ακύρωση") {
                recorder.cancel()
                store.finishFlow()
            }
            .foregroundStyle(.secondary)
            Spacer()
            Label(recorder.isPaused ? "Σε παύση" : "Ηχογράφηση", systemImage: "circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(recorder.isPaused ? .orange : .red)
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
            Text("Μιλήστε φυσικά στα ελληνικά")
                .font(.title2.bold())
            Text("«Αύριο στις δέκα, Μαρία Κωνσταντίνου, για σαράντα πέντε λεπτά»")
                .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
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
            .accessibilityLabel(recorder.isPaused ? "Συνέχεια εγγραφής" : "Παύση εγγραφής")

            Button {
                let url = recorder.finish()
                store.reviewRecording(at: url)
            } label: {
                Label("Τέλος", systemImage: "checkmark")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 9)
            }
            .primaryActionStyle()
        }
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
