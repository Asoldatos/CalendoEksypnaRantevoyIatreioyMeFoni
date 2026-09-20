import SwiftUI

struct OnboardingView: View {
    let store: AppStore
    @State private var step = 0
    @State private var calendars: [GoogleCalendar] = []
    @State private var selectedCalendarID = ""
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        ZStack {
            CalendoBackground()
            VStack(alignment: .leading, spacing: 24) {
                Spacer()
                Image(systemName: step == 0 ? "waveform.and.mic" : "calendar.badge.checkmark")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(CalendoColor.teal)
                    .padding(18).background(.white.opacity(0.72), in: .circle)
                Text(step == 0 ? "Το πρόγραμμά σας, με μία φράση." : "Επιλέξτε το ημερολόγιό σας.")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text(step == 0 ? "Το Calendo ακούει ελληνικά, οργανώνει τα στοιχεία και ετοιμάζει το ραντεβού για το Google Calendar." : "Μόνο το επιλεγμένο ημερολόγιο θα λαμβάνει τα νέα ραντεβού.")
                    .font(.body).foregroundStyle(.secondary)
                if step == 0 { privacyCard } else { calendarPicker }
                Spacer()
                Button(action: primaryAction) {
                    Group { if isWorking { ProgressView().tint(.white) } else { Text(step == 0 ? "Σύνδεση με Google" : "Ολοκλήρωση") } }
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .primaryActionStyle().disabled(isWorking || (step == 1 && selectedCalendarID.isEmpty))
            }
            .padding(24)
        }
        .alert("Η σύνδεση δεν ολοκληρώθηκε", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("Εντάξει", role: .cancel) {} } message: { Text(error ?? "") }
    }

    private var privacyCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill").foregroundStyle(CalendoColor.teal)
            Text("Με τη συγκατάθεσή σας, η προσωρινή ηχογράφηση αναλύεται με Gemini για να βρεθούν όνομα, ημερομηνία, ώρα και διάρκεια. Δεν διατηρείται στον server μετά την ανάλυση.")
                .font(.footnote).foregroundStyle(.secondary)
        }.clinicalCard()
    }

    private var calendarPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if calendars.isEmpty { ProgressView("Φόρτωση ημερολογίων…") }
            ForEach(calendars) { calendar in
                Button { selectedCalendarID = calendar.id } label: {
                    HStack { Image(systemName: selectedCalendarID == calendar.id ? "checkmark.circle.fill" : "circle").foregroundStyle(CalendoColor.teal); Text(calendar.summary).foregroundStyle(.primary); Spacer(); if calendar.primary { Text("Κύριο").font(.caption).foregroundStyle(.secondary) } }
                }.buttonStyle(.plain).padding(.vertical, 8)
            }
        }.clinicalCard()
    }

    private func primaryAction() {
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                if step == 0 {
                    try await store.google.signIn()
                    calendars = try await store.google.calendars()
                    selectedCalendarID = calendars.first(where: \.primary)?.id ?? calendars.first?.id ?? ""
                    step = 1
                } else { store.completeOnboarding(calendarID: selectedCalendarID) }
            } catch { self.error = error.localizedDescription }
        }
    }
}
