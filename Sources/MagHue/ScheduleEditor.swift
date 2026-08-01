import MagHueCore
import SwiftUI

/// A compact editor for one automation rule inside the popover.
struct ScheduleEditor: View {
    @Binding var schedule: Schedule
    let onDelete: () -> Void

    // Sunday-first, matching Calendar's weekday numbering (1...7).
    private let weekdayLabels: [(day: Int, letter: String)] =
        [(1, "S"), (2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S")]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("", selection: $schedule.action) {
                    ForEach(ScheduleAction.allCases, id: \.self) { action in
                        Text(action.displayName).tag(action)
                    }
                }
                .labelsHidden()
                .fixedSize()

                Spacer()

                // The switch is what turns the rule on, so it needs to look
                // like the thing to press: grey while off, blue once on, and
                // big enough to notice.
                Toggle("", isOn: $schedule.enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help(schedule.enabled ? "Turn this schedule off" : "Turn this schedule on")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                Text("From").font(.caption).foregroundStyle(.secondary).fixedSize()
                anchorControl($schedule.start)
                Text("to").font(.caption).foregroundStyle(.secondary).fixedSize()
                anchorControl($schedule.end)
            }

            HStack(spacing: 4) {
                ForEach(weekdayLabels, id: \.day) { entry in
                    dayChip(entry.day, entry.letter)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
        // Dimmed while off, but not so far that the controls stop reading as
        // controls — this is the state the user has to click their way out of.
        .opacity(schedule.enabled ? 1 : 0.8)
    }

    // MARK: - Anchor (time / sunset / sunrise / battery %)

    @ViewBuilder
    private func anchorControl(_ anchor: Binding<TimeAnchor>) -> some View {
        HStack(spacing: 3) {
            Menu(anchorTitle(anchor.wrappedValue)) {
                Button("Sunset") { anchor.wrappedValue.kind = .sunset }
                Button("Sunrise") { anchor.wrappedValue.kind = .sunrise }
                Button("Set time…") { anchor.wrappedValue.kind = .clock }
                Divider()
                Button("Battery %") { anchor.wrappedValue.kind = .percent }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            switch anchor.wrappedValue.kind {
            case .clock:
                DatePicker("", selection: timeBinding(anchor), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .fixedSize()
            case .percent:
                // A menu rather than a stepper: two steppers plus their
                // labels overflow the 300pt popover and squeeze out the
                // "From" and "to". Steps of 5, like the threshold slider.
                Menu("\(anchor.wrappedValue.percent)%") {
                    ForEach(Array(stride(from: 0, through: 100, by: 5)), id: \.self) { value in
                        Button("\(value)%") { anchor.wrappedValue.percent = value }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            case .sunset, .sunrise:
                EmptyView()
            }
        }
    }

    private func anchorTitle(_ anchor: TimeAnchor) -> String {
        switch anchor.kind {
        case .sunset: return "Sunset"
        case .sunrise: return "Sunrise"
        case .clock: return "Time"
        case .percent: return "Batt."
        }
    }

    private func percentBinding(_ anchor: Binding<TimeAnchor>) -> Binding<Int> {
        Binding(
            get: { anchor.wrappedValue.percent },
            set: { anchor.wrappedValue.percent = min(max($0, 0), 100) }
        )
    }

    /// Bridges the anchor's hour/minute to the Date a DatePicker wants.
    private func timeBinding(_ anchor: Binding<TimeAnchor>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: anchor.wrappedValue.hour,
                                      minute: anchor.wrappedValue.minute,
                                      second: 0, of: Date()) ?? Date()
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                anchor.wrappedValue.hour = c.hour ?? 0
                anchor.wrappedValue.minute = c.minute ?? 0
            }
        )
    }

    // MARK: - Weekday chips

    private func dayChip(_ day: Int, _ letter: String) -> some View {
        let on = schedule.days.contains(day)
        return Button {
            if on { schedule.days.remove(day) } else { schedule.days.insert(day) }
        } label: {
            Text(letter)
                .font(.caption2)
                .fontWeight(.medium)
                .frame(width: 22, height: 22)
                .background(Circle().fill(on ? Color.accentColor : Color.primary.opacity(0.08)))
                .foregroundStyle(on ? Color.white : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}
