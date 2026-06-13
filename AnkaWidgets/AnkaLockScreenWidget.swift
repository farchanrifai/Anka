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
        // W1: Schedule a refresh at midnight so stale data is zeroed even if
        // the main app hasn't been opened today.
        let now = Date()
        let cal = Calendar.current
        let next15 = cal.date(byAdding: .minute, value: 15, to: now) ?? now
        let nextMidnight = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: now) ?? now)
        let nextRefresh = min(next15, nextMidnight)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    /// Day formatter matching the main app's `WidgetDataWriter`.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func loadEntry() -> AnkaLockScreenEntry {
        let defaults = UserDefaults(suiteName: WidgetKeys.suiteName)

        // W1: Zero stale data when the snapshot date doesn't match today.
        let storedDay = defaults?.string(forKey: WidgetKeys.snapshotDate) ?? ""
        let today     = dayFormatter.string(from: Date())
        let isStale   = storedDay != today

        return AnkaLockScreenEntry(
            date: Date(),
            todayExpense: isStale ? 0 : (defaults?.double(forKey: WidgetKeys.todayExpense) ?? 0),
            todayIncome:  isStale ? 0 : (defaults?.double(forKey: WidgetKeys.todayIncome)  ?? 0)
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
                // W2: Use text "Rp" instead of the `indianrupeesign` SF Symbol
                // (which is ₹ — Indian rupee, wrong currency for an IDR app).
                Text("Rp")
                    .font(.caption2.weight(.bold))
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
                // W3: Tapping the lock-screen widget opens the app.
                .widgetURL(AnkaDeepLink.openApp)
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
