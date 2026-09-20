import SwiftUI

struct HomeView: View {
    let store: AppStore

    var body: some View {
        ZStack {
            CalendoBackground()
            ScrollView {
                LazyVStack(spacing: 20) {
                    HomeHeader()
                    RecordingHero(onRecord: store.startRecording)
                    WeekPulseCard(drafts: store.drafts)
                    if let draft = store.latestDraft { RecentDraftCard(draft: draft, onEdit: { store.edit(draft) }) }
                    ShortcutGuideCard()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct HomeHeader: View {
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("CALENDO").font(.caption.weight(.bold)).tracking(2.2).foregroundStyle(CalendoColor.teal)
                Text("Καλημέρα").font(.largeTitle.bold())
                Text("Το επόμενο ραντεβού ξεκινά από τη φωνή σας.").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "stethoscope").font(.title2.weight(.semibold)).foregroundStyle(CalendoColor.teal)
                .frame(width: 52, height: 52).background(.thinMaterial, in: Circle()).accessibilityHidden(true)
        }
        .padding(.top, 18)
    }
}

private struct RecordingHero: View {
    let onRecord: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Άμεση καταχώριση", systemImage: "sparkles").font(.subheadline.weight(.semibold))
                Spacer()
                Text("AI + GOOGLE").font(.caption2.bold()).foregroundStyle(CalendoColor.teal)
            }
            Text("Πείτε όνομα, ημερομηνία, ώρα και διάρκεια — με όποια σειρά θέλετε.").font(.title3.weight(.semibold))
            Button(action: onRecord) {
                Label("Νέα εγγραφή", systemImage: "waveform.badge.mic").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
            }.primaryActionStyle().accessibilityHint("Ανοίγει την οθόνη ηχογράφησης")
        }.clinicalCard()
    }
}

private struct WeekPulseCard: View {
    let drafts: [AppointmentDraft]
    @State private var selectedDay: Date?

    private var days: [Date] {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    private var values: [Int] {
        days.map { day in
            drafts.filter { Calendar.current.isDate($0.startDate, inSameDayAs: day) && $0.status == .ready }.count
        }
    }
    private var selectedCount: Int? {
        guard let selectedDay, let index = days.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: selectedDay) }) else { return nil }
        return values[index]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ρυθμός εβδομάδας").font(.headline)
                    Text(summaryText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Προβολή όλων") { selectedDay = nil }.font(.caption.weight(.semibold)).foregroundStyle(CalendoColor.teal)
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(days.indices, id: \.self) { index in
                    Button { selectedDay = days[index] } label: {
                        VStack(spacing: 7) {
                            Capsule().fill(isSelected(index) ? CalendoColor.teal : CalendoColor.mint)
                                .frame(height: barHeight(for: values[index]))
                            Text(days[index].formatted(.dateTime.locale(Locale(identifier: "el_GR")).weekday(.narrow)))
                                .font(.caption2).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(.plain).accessibilityLabel("\(days[index].formatted(date: .abbreviated, time: .omitted)): \(values[index]) ραντεβού")
                }
            }.frame(height: 98, alignment: .bottom)
            if let selectedDay, let selectedCount {
                Text("\(selectedDay.formatted(.dateTime.locale(Locale(identifier: "el_GR")).weekday(.wide).day().month(.wide))): \(selectedCount) \(selectedCount == 1 ? "ραντεβού" : "ραντεβού")")
                    .font(.caption.weight(.medium)).foregroundStyle(CalendoColor.teal)
            }
        }.clinicalCard()
    }

    private var summaryText: String { "\(values.reduce(0, +)) επιβεβαιωμένα ραντεβού αυτή την εβδομάδα" }
    private func barHeight(for value: Int) -> CGFloat { CGFloat(max(16, min(82, 16 + value * 15))) }
    private func isSelected(_ index: Int) -> Bool { selectedDay.map { Calendar.current.isDate($0, inSameDayAs: days[index]) } ?? false }
}

private struct RecentDraftCard: View {
    let draft: AppointmentDraft
    let onEdit: () -> Void
    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 14) {
                DateTile(date: draft.startDate)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Πρόσφατο ραντεβού").font(.caption).foregroundStyle(.secondary)
                    Text(draft.patientName).font(.headline).foregroundStyle(.primary)
                    Text("\(draft.startDate.greekTime) · \(draft.durationMinutes) λεπτά").font(.subheadline).foregroundStyle(.secondary)
                    Label(draft.status.title, systemImage: "checkmark.seal.fill").font(.caption.weight(.semibold)).foregroundStyle(CalendoColor.teal)
                }
                Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).clinicalCard()
    }
}

private struct DateTile: View {
    let date: Date
    var body: some View {
        VStack(spacing: 2) {
            Text(date.formatted(.dateTime.locale(Locale(identifier: "el_GR")).month(.abbreviated))).font(.caption2.bold()).textCase(.uppercase)
            Text(date.formatted(.dateTime.day())).font(.title2.bold())
        }.foregroundStyle(CalendoColor.teal).frame(width: 52, height: 58).background(CalendoColor.ice, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct ShortcutGuideCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "square.grid.2x2.fill").font(.title2).foregroundStyle(CalendoColor.teal)
            VStack(alignment: .leading, spacing: 5) {
                Text("Δεύτερο εικονίδιο στην Αρχική").font(.headline)
                Text("Στις Συντομεύσεις, βρείτε «Νέα εγγραφή» του Calendo και επιλέξτε Προσθήκη στην οθόνη Αφετηρίας.").font(.subheadline).foregroundStyle(.secondary)
            }
        }.clinicalCard()
    }
}
