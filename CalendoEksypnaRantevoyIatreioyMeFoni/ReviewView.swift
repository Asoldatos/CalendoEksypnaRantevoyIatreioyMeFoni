import SwiftUI

struct ReviewView: View {
    let store: AppStore
    @State private var draft: AppointmentDraft
    @State private var player = AudioPreviewPlayer()
    @State private var error: String?
    @State private var isAnalyzing = false
    @State private var isCreating = false
    @State private var didAnalyze = false
    @FocusState private var focusedField: Field?

    enum Field { case name, telephone }

    init(store: AppStore, draft: AppointmentDraft) {
        self.store = store
        _draft = State(initialValue: draft)
    }

    var body: some View {
        ZStack {
            CalendoBackground()
            ScrollView {
                VStack(spacing: 18) {
                    header
                    if isAnalyzing { analysisProgress }
                    titlePreview
                    detailsCard
                    if let url = draft.audioURL { audioCard(url) }
                    createButton
                }.padding(20).padding(.bottom, 24)
            }.scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Έλεγχος ραντεβού").navigationBarTitleDisplayMode(.inline)
        .task { await analyzeIfNeeded() }
        .alert("Δεν ολοκληρώθηκε", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("Εντάξει", role: .cancel) {} } message: { Text(error ?? "") }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: isAnalyzing ? "sparkles" : "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(CalendoColor.teal)
            Text(isAnalyzing ? "Το Calendo ακούει…" : "Επιβεβαιώστε όσα κατάλαβε")
                .font(.title2.bold()).multilineTextAlignment(.center)
            Text("Διορθώστε κάθε πεδίο πριν δημιουργηθεί το ραντεβού.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private var analysisProgress: some View {
        HStack(spacing: 12) { ProgressView(); Text("Ανάλυση ελληνικής ηχογράφησης με Gemini…").font(.subheadline) }
            .frame(maxWidth: .infinity, alignment: .leading).clinicalCard()
    }

    private var titlePreview: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("ΤΙΤΛΟΣ GOOGLE CALENDAR", systemImage: "calendar.badge.clock").font(.caption.bold()).foregroundStyle(CalendoColor.teal)
            Text(draft.calendarTitle.isEmpty ? "ΟΝΟΜΑ ΑΣΘΕΝΟΥΣ 69XXXXXXXX" : draft.calendarTitle)
                .font(.title3.bold()).foregroundStyle(draft.calendarTitle.isEmpty ? .secondary : .primary)
            Text("Θα δημιουργηθεί στο επιλεγμένο Google Calendar.").font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).clinicalCard()
    }

    private var detailsCard: some View {
        VStack(spacing: 18) {
            LabeledContent("Ασθενής") { TextField("Ονοματεπώνυμο", text: $draft.patientName).multilineTextAlignment(.trailing).focused($focusedField, equals: .name).textContentType(.name) }
            Divider()
            DatePicker("Ημερομηνία", selection: $draft.startDate, displayedComponents: .date).environment(\.locale, Locale(identifier: "el_GR"))
            DatePicker("Ώρα έναρξης", selection: $draft.startDate, displayedComponents: .hourAndMinute).environment(\.locale, Locale(identifier: "el_GR"))
            durationSection
            Divider()
            telephoneField
        }.clinicalCard()
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Διάρκεια"); Spacer(); Text("\(draft.durationMinutes) λεπτά").foregroundStyle(.secondary) }
            HStack { ForEach([15, 30, 45, 60], id: \.self) { minutes in Button("\(minutes)′") { draft.durationMinutes = minutes }.buttonStyle(.bordered).tint(draft.durationMinutes == minutes ? CalendoColor.teal : .secondary) }; Spacer() }
            Stepper("Προσαρμογή ανά 5 λεπτά", value: $draft.durationMinutes, in: 5...240, step: 5).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var telephoneField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text("Τηλέφωνο"); Spacer(); TextField("69XXXXXXXX", text: $draft.telephone).keyboardType(.phonePad).textContentType(.telephoneNumber).multilineTextAlignment(.trailing).focused($focusedField, equals: .telephone) }
            if !draft.telephone.isEmpty && !draft.hasValidTelephone { Label("Χρειάζονται 10–15 ψηφία", systemImage: "exclamationmark.circle.fill").font(.caption).foregroundStyle(.red) }
            else if draft.telephone.isEmpty { Text("Υποχρεωτικό για τη δημιουργία ραντεβού").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func audioCard(_ url: URL) -> some View {
        Button { player.toggle(url: url) } label: {
            HStack { Image(systemName: player.isPlaying ? "stop.circle.fill" : "play.circle.fill").font(.title2).foregroundStyle(CalendoColor.teal); VStack(alignment: .leading) { Text(player.isPlaying ? "Διακοπή αναπαραγωγής" : "Ακούστε την εγγραφή").font(.headline).foregroundStyle(.primary); Text("Διαγράφεται από τον server μετά την ανάλυση.").font(.caption).foregroundStyle(.secondary) }; Spacer() }
        }.buttonStyle(.plain).clinicalCard()
    }

    private var createButton: some View {
        Button(action: createEvent) {
            Group { if isCreating { ProgressView().tint(.white) } else { Label("Δημιουργία στο Google Calendar", systemImage: "calendar.badge.plus") } }
                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 9)
        }.primaryActionStyle().disabled(!draft.canSave || isAnalyzing || isCreating).opacity(draft.canSave && !isAnalyzing ? 1 : 0.55)
    }

    private func analyzeIfNeeded() async {
        guard !didAnalyze, let audioURL = draft.audioURL else { return }
        didAnalyze = true; isAnalyzing = true
        defer { isAnalyzing = false }
        do {
            let token = try await store.google.validAccessToken()
            let result = try await GeminiAppointmentService().analyze(audioURL: audioURL, token: token)
            store.applyAI(result, to: &draft)
        }
        catch { self.error = "Δεν ολοκληρώθηκε η αυτόματη ανάλυση. Μπορείτε να συμπληρώσετε τα στοιχεία χειροκίνητα." }
    }

    private func createEvent() {
        guard draft.canSave else { focusedField = draft.patientName.isEmpty ? .name : .telephone; return }
        Task { isCreating = true; defer { isCreating = false }; do { try await store.createCalendarEvent(draft) } catch { self.error = "Δεν δημιουργήθηκε το event στο Google Calendar. Ελέγξτε τη σύνδεσή σας και δοκιμάστε ξανά." } }
    }
}
