import WidgetKit
import SwiftUI

// MARK: - Timeline

struct AnkaLockScreenEntry: TimelineEntry {
    let date: Date
    let todayExpense: Double
    let todayIncome: Double
}

struct AnkaLockScreenTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> AnkaLockScreenEntry {
        AnkaLockScreenEntry(date: Date(), todayExpense: 125_000, todayIncome: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (AnkaLockScreenEntry) -> Void) {
        completion(Self.loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AnkaLockScreenEntry>) -> Void) {
        let entry = Self.loadEntry()
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private static func loadEntry() -> AnkaLockScreenEntry {
        let defaults = UserDefaults(suiteName: WidgetKeys.suiteName)
        return AnkaLockScreenEntry(
            date: Date(),
            todayExpense: defaults?.double(forKey: WidgetKeys.todayExpense) ?? 0,
            todayIncome:  defaults?.double(forKey: WidgetKeys.todayIncome)  ?? 0
        )
    }
}

// MARK: - View
// Lock-screen complications are rendered through a vibrancy effect that
// flattens custom colors, so we lean on system foregroundStyle + .widgetAccentable.

struct AnkaLockScreenWidgetView: View {
    var entry: AnkaLockScreenEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "indianrupeesign")
                    .font(.caption2.weight(.semibold))
                Text("Today")
                    .font(.caption2.weight(.semibold))
            }
            .widgetAccentable()

            Text(entry.todayExpense.groupedIDR)
                .font(.title3.weight(.bold))
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            if entry.todayIncome > 0 {
                Text("+ \(entry.todayIncome.groupedIDR)")
                    .font(.caption2)
                    .widgetAccentable()
            }
        }
        .containerBackground(.clear, for: .widget)
    }
}

// MARK: - Widget

struct AnkaLockScreenWidget: Widget {
    let kind: String = "AnkaLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AnkaLockScreenTimelineProvider()) { entry in
            AnkaLockScreenWidgetView(entry: entry)
        }
        .configurationDisplayName("Anka Daily")
        .description("Quick view of today's spending.")
        .supportedFamilies([.accessoryRectangular])
    }
}

#Preview(as: .accessoryRectangular) {
    AnkaLockScreenWidget()
} timeline: {
    AnkaLockScreenEntry(date: Date(), todayExpense: 125_000, todayIncome: 0)
    AnkaLockScreenEntry(date: Date(), todayExpense: 240_000, todayIncome: 5_000_000)
}
