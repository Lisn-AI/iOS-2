import SwiftUI
import SwiftData

// MARK: - CalendarDay Model

struct CalendarDay: Identifiable {
    let id = UUID()
    let date: Date?
    let dayNumber: Int
    let isCurrentMonth: Bool
    let isToday: Bool
}

// MARK: - ViewModel

@MainActor
final class CalendarViewModel: ObservableObject {
    @Published var displayedMonth: Date = Date()
    @Published var selectedDate: Date? = nil
    @Published var briefing: BriefingResponse? = nil
    @Published var isBriefingLoading = false

    private let calendar = Calendar.current

    // MARK: - Month Navigation

    func goToPreviousMonth() {
        guard let prev = calendar.date(byAdding: .month, value: -1, to: displayedMonth) else { return }
        displayedMonth = prev
        selectedDate = nil
        briefing = nil
    }

    func goToNextMonth() {
        guard !isCurrentMonth else { return }
        guard let next = calendar.date(byAdding: .month, value: 1, to: displayedMonth) else { return }
        displayedMonth = next
        selectedDate = nil
        briefing = nil
    }

    func goToToday() {
        displayedMonth = Date()
        selectedDate = calendar.startOfDay(for: Date())
        fetchBriefing(for: selectedDate!)
    }

    var isCurrentMonth: Bool {
        calendar.isDate(displayedMonth, equalTo: Date(), toGranularity: .month)
    }

    var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayedMonth)
    }

    // MARK: - Grid Generation

    func generateMonthGrid() -> [CalendarDay] {
        var days: [CalendarDay] = []

        let comps = calendar.dateComponents([.year, .month], from: displayedMonth)
        guard let firstOfMonth = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else {
            return days
        }

        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        // Sunday = 1, so leading blanks = firstWeekday - 1
        let leadingBlanks = firstWeekday - 1

        let today = calendar.startOfDay(for: Date())

        // Leading blanks
        for _ in 0..<leadingBlanks {
            days.append(CalendarDay(date: nil, dayNumber: 0, isCurrentMonth: false, isToday: false))
        }

        // Actual days
        for day in range {
            var dc = comps
            dc.day = day
            let date = calendar.date(from: dc)!
            let startOfDate = calendar.startOfDay(for: date)
            days.append(CalendarDay(
                date: startOfDate,
                dayNumber: day,
                isCurrentMonth: true,
                isToday: startOfDate == today
            ))
        }

        // Trailing blanks to fill 6 rows (42 cells) or 5 rows (35)
        let totalNeeded = days.count <= 35 ? 35 : 42
        while days.count < totalNeeded {
            days.append(CalendarDay(date: nil, dayNumber: 0, isCurrentMonth: false, isToday: false))
        }

        return days
    }

    // MARK: - Day Selection

    func selectDate(_ date: Date) {
        if selectedDate == date {
            selectedDate = nil
            briefing = nil
        } else {
            selectedDate = date
            fetchBriefing(for: date)
        }
    }

    // MARK: - Briefing

    func fetchBriefing(for date: Date) {
        isBriefingLoading = true
        briefing = nil
        Task {
            do {
                let response = try await DataService.shared.getBriefing(date: date)
                self.briefing = response
            } catch {
                // Silently fail — no briefing for this day
            }
            self.isBriefingLoading = false
        }
    }
}

// MARK: - CalendarView

struct CalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recording.date, order: .reverse) private var allRecordings: [Recording]
    @StateObject private var viewModel = CalendarViewModel()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let weekdays = ["S", "M", "T", "W", "T", "F", "S"]

    /// Recordings grouped by start-of-day
    private var recordingsByDay: [Date: [Recording]] {
        let calendar = Calendar.current
        return Dictionary(grouping: allRecordings) { recording in
            calendar.startOfDay(for: recording.date)
        }
    }

    /// Set of days with recordings (for dot display)
    private var daysWithRecordings: Set<Date> {
        Set(recordingsByDay.keys)
    }

    /// Recordings for the selected date
    private var selectedDayRecordings: [Recording] {
        guard let date = viewModel.selectedDate else { return [] }
        return (recordingsByDay[date] ?? []).sorted { $0.date < $1.date }
    }

    private var hasNoRecordings: Bool {
        allRecordings.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LisnSpacing.lg) {
                    monthHeader
                    weekdayHeader
                    calendarGrid

                    if hasNoRecordings {
                        sampleDataSection
                    } else if let selected = viewModel.selectedDate {
                        dayDetailSection(for: selected)
                    }
                }
                .padding(.horizontal, LisnSpacing.md)
                .padding(.bottom, 68)
            }
            .safeAreaInset(edge: .top) {
                Text("Calendar")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(LisnColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, LisnSpacing.sm)
                    .padding(.bottom, LisnSpacing.xs)
                    .background(.regularMaterial)
            }
            .toolbar(.hidden, for: .navigationBar)
            .background(LisnColors.bgPrimary)
        }
    }

    // MARK: - Month Header

    private var monthHeader: some View {
        HStack {
            Button {
                LisnHaptics.selection()
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.goToPreviousMonth()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(LisnColors.accent)
                    .frame(width: 36, height: 36)
            }

            Spacer()

            Button {
                LisnHaptics.selection()
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.goToToday()
                }
            } label: {
                Text(viewModel.monthTitle)
                    .font(LisnFont.titleMedium())
                    .foregroundColor(LisnColors.textPrimary)
            }

            Spacer()

            Button {
                LisnHaptics.selection()
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.goToNextMonth()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(viewModel.isCurrentMonth ? LisnColors.textTertiary : LisnColors.accent)
                    .frame(width: 36, height: 36)
            }
            .disabled(viewModel.isCurrentMonth)
        }
        .padding(.top, LisnSpacing.xs)
    }

    // MARK: - Weekday Header

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(weekdays, id: \.self) { day in
                Text(day)
                    .font(LisnFont.captionBold())
                    .foregroundColor(LisnColors.textTertiary)
                    .frame(height: 24)
            }
        }
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        let days = viewModel.generateMonthGrid()
        return LazyVGrid(columns: columns, spacing: LisnSpacing.xxs) {
            ForEach(days) { day in
                CalendarDayCell(
                    day: day,
                    isSelected: day.date != nil && day.date == viewModel.selectedDate,
                    recordingCount: day.date != nil ? (recordingsByDay[day.date!]?.count ?? 0) : 0,
                    isSampleMode: hasNoRecordings
                )
                .onTapGesture {
                    guard day.isCurrentMonth, let date = day.date else { return }
                    LisnHaptics.selection()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectDate(date)
                    }
                }
            }
        }
    }

    // MARK: - Day Detail Section

    @ViewBuilder
    private func dayDetailSection(for date: Date) -> some View {
        VStack(alignment: .leading, spacing: LisnSpacing.md) {
            // Date header
            HStack {
                Text(formattedSelectedDate(date))
                    .font(LisnFont.titleSmall())
                    .foregroundColor(LisnColors.textPrimary)

                if !selectedDayRecordings.isEmpty {
                    Text("\(selectedDayRecordings.count)")
                        .font(LisnFont.captionBold())
                        .foregroundColor(.white)
                        .padding(.horizontal, LisnSpacing.xs)
                        .padding(.vertical, 2)
                        .background(LisnColors.accent)
                        .clipShape(Capsule())
                }

                Spacer()
            }

            // Briefing card
            if viewModel.isBriefingLoading {
                GlassCard {
                    HStack(spacing: LisnSpacing.sm) {
                        ProgressView()
                        Text("Loading briefing…")
                            .font(LisnFont.bodyMedium())
                            .foregroundColor(LisnColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let briefing = viewModel.briefing, !briefing.summary.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: LisnSpacing.xs) {
                        HStack(spacing: LisnSpacing.xs) {
                            Image(systemName: "sun.haze")
                                .foregroundColor(LisnColors.accent)
                            Text("Daily Briefing")
                                .font(LisnFont.labelMedium())
                                .foregroundColor(LisnColors.textSecondary)
                        }

                        Text(briefing.summary)
                            .font(LisnFont.bodyMedium())
                            .foregroundColor(LisnColors.textPrimary)
                            .lineLimit(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Recording cards
            if selectedDayRecordings.isEmpty {
                emptyDayState
            } else {
                ForEach(selectedDayRecordings, id: \.id) { recording in
                    NavigationLink {
                        RecordingDetailView(recording: recording)
                    } label: {
                        recordingCard(recording)
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Recording Card

    private func recordingCard(_ recording: Recording) -> some View {
        GlassCard {
            HStack(spacing: LisnSpacing.sm) {
                // Time pill
                Text(formatTime(recording.date))
                    .font(LisnFont.captionBold())
                    .foregroundColor(.white)
                    .padding(.horizontal, LisnSpacing.xs)
                    .padding(.vertical, LisnSpacing.xxxs)
                    .background(LisnColors.accent)
                    .clipShape(Capsule())

                VStack(alignment: .leading, spacing: LisnSpacing.xxxs) {
                    if let summary = recording.summary {
                        Text(summary.text)
                            .font(LisnFont.bodyMedium())
                            .foregroundColor(LisnColors.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text("Recording")
                            .font(LisnFont.bodyMedium())
                            .foregroundColor(LisnColors.textSecondary)
                    }

                    if recording.duration > 0 {
                        Text(recording.formattedDuration)
                            .font(LisnFont.caption())
                            .foregroundColor(LisnColors.textTertiary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(LisnColors.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Empty Day State

    private var emptyDayState: some View {
        VStack(spacing: LisnSpacing.sm) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 32))
                .foregroundColor(LisnColors.textTertiary)

            Text("No recordings this day")
                .font(LisnFont.bodyMedium())
                .foregroundColor(LisnColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LisnSpacing.xxl)
    }

    // MARK: - Sample Data Section (New Users)

    private var sampleDataSection: some View {
        VStack(spacing: LisnSpacing.md) {
            HStack(spacing: LisnSpacing.xs) {
                Image(systemName: "sparkles")
                    .foregroundColor(LisnColors.accent)
                Text("Here's how your calendar will look")
                    .font(LisnFont.labelMedium())
                    .foregroundColor(LisnColors.textSecondary)
            }
            .padding(.top, LisnSpacing.sm)

            // Sample recording cards
            ForEach(sampleRecordings, id: \.title) { sample in
                sampleCard(sample)
            }

            // CTA
            Button {
                LisnHaptics.light()
                NotificationCenter.default.post(name: .navigateToHome, object: nil)
            } label: {
                HStack(spacing: LisnSpacing.xs) {
                    Image(systemName: "mic.fill")
                    Text("Start Recording")
                        .font(LisnFont.labelLarge())
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, LisnSpacing.sm)
                .background(LisnColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: LisnRadius.lg, style: .continuous))
            }
            .padding(.top, LisnSpacing.xs)
        }
    }

    private func sampleCard(_ sample: SampleRecording) -> some View {
        GlassCard {
            HStack(spacing: LisnSpacing.sm) {
                Text(sample.time)
                    .font(LisnFont.captionBold())
                    .foregroundColor(.white)
                    .padding(.horizontal, LisnSpacing.xs)
                    .padding(.vertical, LisnSpacing.xxxs)
                    .background(LisnColors.accent.opacity(0.5))
                    .clipShape(Capsule())

                VStack(alignment: .leading, spacing: LisnSpacing.xxxs) {
                    Text(sample.title)
                        .font(LisnFont.bodyMedium())
                        .foregroundColor(LisnColors.textPrimary)
                        .lineLimit(2)

                    Text(sample.duration)
                        .font(LisnFont.caption())
                        .foregroundColor(LisnColors.textTertiary)
                }

                Spacer()

                Text("SAMPLE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(LisnColors.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(LisnColors.accent.opacity(0.12))
                    .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(0.7)
    }

    // MARK: - Helpers

    private func formattedSelectedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - CalendarDayCell

private struct CalendarDayCell: View {
    let day: CalendarDay
    let isSelected: Bool
    let recordingCount: Int
    let isSampleMode: Bool

    /// In sample mode, show ghost dots on some days
    private var showSampleDot: Bool {
        guard isSampleMode, day.isCurrentMonth, let date = day.date else { return false }
        let dayNum = Calendar.current.component(.day, from: date)
        // Show dots on a few past days for visual effect
        let today = Calendar.current.component(.day, from: Date())
        return dayNum < today && [today - 1, today - 3, today - 5, today - 7].contains(dayNum) && dayNum > 0
    }

    var body: some View {
        VStack(spacing: 4) {
            if day.isCurrentMonth {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(LisnColors.accent)
                            .frame(width: 34, height: 34)
                    } else if day.isToday {
                        Circle()
                            .stroke(LisnColors.accent, lineWidth: 1.5)
                            .frame(width: 34, height: 34)
                    }

                    Text("\(day.dayNumber)")
                        .font(LisnFont.bodyMedium())
                        .foregroundColor(isSelected ? .white : (day.isToday ? LisnColors.accent : LisnColors.textPrimary))
                }

                // Recording dots
                HStack(spacing: 3) {
                    let dotCount = min(recordingCount, 3)
                    if dotCount > 0 {
                        ForEach(0..<dotCount, id: \.self) { _ in
                            Circle()
                                .fill(isSelected ? LisnColors.accent : LisnColors.accent)
                                .frame(width: 4, height: 4)
                        }
                    } else if showSampleDot {
                        Circle()
                            .fill(LisnColors.accent.opacity(0.4))
                            .frame(width: 4, height: 4)
                    } else {
                        Circle()
                            .fill(Color.clear)
                            .frame(width: 4, height: 4)
                    }
                }
            } else {
                // Non-current-month placeholder
                Text("")
                    .frame(height: 34)
                Circle()
                    .fill(Color.clear)
                    .frame(width: 4, height: 4)
            }
        }
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

// MARK: - Sample Data

private struct SampleRecording {
    let time: String
    let title: String
    let duration: String
}

private let sampleRecordings: [SampleRecording] = [
    SampleRecording(time: "9:30 AM", title: "Morning standup — discussed sprint priorities and blockers", duration: "12:34"),
    SampleRecording(time: "1:15 PM", title: "Lunch catch-up with Alex about weekend plans", duration: "08:21"),
    SampleRecording(time: "4:00 PM", title: "Brainstorm session for new feature ideas", duration: "23:47"),
]
