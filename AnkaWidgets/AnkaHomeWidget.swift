import WidgetKit
import SwiftUI

// MARK: - Timeline

struct AnkaHomeEntry: TimelineEntry {
    let date: Date
    let todayExpense: Double
    let todayIncome: Double
    let recentTransactions: [WidgetTransaction]
}

struct AnkaHomeTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> AnkaHomeEntry { Self.sampleEntry }

    func getSnapshot(in context: Context, completion: @escaping (AnkaHomeEntry) -> Void) {
        completion(Self.loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AnkaHomeEntry>) -> Void) {
        let entry = Self.loadEntry()

        // Schedule two refresh points:
        //   1. 15 minutes from now — regular polling cadence (also reloaded by
        //      app-side calls to WidgetCenter.shared.reloadAllTimelines()).
        //   2. Midnight — zeroes the totals so yesterday's spend doesn't carry
        //      over when the user hasn't opened the app (W1).
        let now = Date()
        let cal = Calendar.current
        let next15 = cal.date(byAdding: .minute, value: 15, to: now) ?? now
        let nextMidnight = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: now) ?? now)

        // The earlier of the two becomes the next timeline request.
        let nextRefresh = min(next15, nextMidnight)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    /// Day formatter matching the main app's `WidgetDataWriter`. Used to compare
    /// the stored snapshot date against the current calendar day.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func loadEntry() -> AnkaHomeEntry {
        let defaults = UserDefaults(suiteName: WidgetKeys.suiteName)

        // W1: If the stored snapshot is from a previous calendar day, the data
        // is stale — show zeroes instead of yesterday's numbers.
        let storedDay = defaults?.string(forKey: WidgetKeys.snapshotDate) ?? ""
        let today     = dayFormatter.string(from: Date())
        let isStale   = storedDay != today

        let expense: Double
        let income: Double
        var recent: [WidgetTransaction] = []

        if isStale {
            expense = 0
            income  = 0
        } else {
            expense = defaults?.double(forKey: WidgetKeys.todayExpense) ?? 0
            income  = defaults?.double(forKey: WidgetKeys.todayIncome) ?? 0

            if let data = defaults?.data(forKey: WidgetKeys.recentTxs),
               let decoded = try? JSONDecoder().decode([WidgetTransaction].self, from: data) {
                recent = decoded
            }
        }

        return AnkaHomeEntry(
            date: Date(),
            todayExpense: expense,
            todayIncome: income,
            recentTransactions: recent
        )
    }

    private static var sampleEntry: AnkaHomeEntry {
        AnkaHomeEntry(
            date: Date(),
            todayExpense: 125_000,
            todayIncome: 0,
            recentTransactions: [
                WidgetTransaction(id: "1", amount: 45_000, categoryName: "Eating Out",   categoryEmoji: "🍽️", note: "Lunch", isExpense: true),
                WidgetTransaction(id: "2", amount: 25_000, categoryName: "Coffee",       categoryEmoji: "☕",  note: nil,      isExpense: true),
                WidgetTransaction(id: "3", amount: 55_000, categoryName: "Taxi",         categoryEmoji: "🚕", note: "Home",   isExpense: true),
            ]
        )
    }
}

// MARK: - Views

struct AnkaHomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: AnkaHomeEntry

    var body: some View {
        switch family {
        case .systemSmall:  SmallContent(entry: entry)
        case .systemMedium: MediumContent(entry: entry)
        case .systemLarge:  LargeContent(entry: entry)
        default:            MediumContent(entry: entry)
        }
    }
}

// Local DS constants — kept self-contained so the widget target has no
// cross-target dependency on Anka's DesignSystem files.
private enum W {
    static let coral   = Color(red: 0xF2/255, green: 0x66/255, blue: 0x66/255)
    static let green   = Color(red: 0x34/255, green: 0xC7/255, blue: 0x59/255)
    static let textPri = Color.primary
    static let textSec = Color.secondary
    static let textMut = Color(uiColor: .tertiaryLabel)
    static let card    = Color(uiColor: .secondarySystemGroupedBackground)
}

// MARK: Small — just the headline

private struct SmallContent: View {
    let entry: AnkaHomeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today")
                .font(.caption2)
                .foregroundStyle(W.textMut)
            Text(entry.todayExpense.groupedIDR)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(W.coral)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("IDR spent")
                .font(.caption2)
                .foregroundStyle(W.textSec)
            Spacer(minLength: 0)
            if entry.todayIncome > 0 {
                Text("+ \(entry.todayIncome.groupedIDR)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(W.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Medium — headline + 2 recent rows

private struct MediumContent: View {
    let entry: AnkaHomeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headlineRow
            Divider().opacity(0.25)
            if entry.recentTransactions.isEmpty {
                emptyRow
            } else {
                ForEach(entry.recentTransactions.prefix(2)) { tx in
                    TransactionRowView(tx: tx)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var headlineRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Spent today")
                    .font(.caption2)
                    .foregroundStyle(W.textMut)
                Text(entry.todayExpense.groupedIDR)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(W.coral)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            Spacer()
            if entry.todayIncome > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Earned")
                        .font(.caption2)
                        .foregroundStyle(W.textMut)
                    Text(entry.todayIncome.groupedIDR)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(W.green)
                        .lineLimit(1)
                }
            }
        }
    }

    private var emptyRow: some View {
        Text("No transactions today")
            .font(.caption)
            .foregroundStyle(W.textMut)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Large — headline + all 3 recent rows + quick-add link

private struct LargeContent: View {
    let entry: AnkaHomeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today")
                        .font(.caption2)
                        .foregroundStyle(W.textMut)
                    Text(entry.todayExpense.groupedIDR)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(W.coral)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("IDR spent")
                        .font(.caption2)
                        .foregroundStyle(W.textSec)
                }
                Spacer()
                if entry.todayIncome > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Earned")
                            .font(.caption2)
                            .foregroundStyle(W.textMut)
                        Text(entry.todayIncome.groupedIDR)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(W.green)
                            .lineLimit(1)
                    }
                }
            }
            Divider().opacity(0.25)
            if entry.recentTransactions.isEmpty {
                Text("No transactions today")
                    .font(.callout)
                    .foregroundStyle(W.textMut)
            } else {
                VStack(spacing: 10) {
                    ForEach(entry.recentTransactions.prefix(3)) { tx in
                        TransactionRowView(tx: tx)
                    }
                }
            }
            Spacer(minLength: 0)
            // W3: Quick-add deep link at the bottom of the large widget.
            Link(destination: AnkaDeepLink.addTransaction) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Add Transaction")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(W.coral)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

// MARK: Shared row

private struct TransactionRowView: View {
    let tx: WidgetTransaction

    var body: some View {
        HStack(spacing: 8) {
            Text(tx.categoryEmoji)
                .font(.system(size: 18))
            VStack(alignment: .leading, spacing: 1) {
                Text(tx.categoryName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(W.textPri)
                    .lineLimit(1)
                if let note = tx.note, !note.isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(W.textSec)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text("\(tx.isExpense ? "" : "+ ")\(tx.amount.groupedIDR)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tx.isExpense ? W.coral : W.green)
                .lineLimit(1)
        }
    }
}

// MARK: - Widget

struct AnkaHomeWidget: Widget {
    let kind: String = "AnkaHomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AnkaHomeTimelineProvider()) { entry in
            AnkaHomeWidgetView(entry: entry)
                .containerBackground(W.card, for: .widget)
                // W3: Tapping the small/medium widget opens the app to Today.
                .widgetURL(AnkaDeepLink.openApp)
        }
        .configurationDisplayName("Anka Summary")
        .description("Today's spending at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemMedium) {
    AnkaHomeWidget()
} timeline: {
    AnkaHomeEntry(
        date: Date(),
        todayExpense: 125_000,
        todayIncome: 0,
        recentTransactions: [
            WidgetTransaction(id: "1", amount: 45_000, categoryName: "Eating Out", categoryEmoji: "🍽️", note: "Lunch", isExpense: true)
        ]
    )
}

#Preview(as: .systemSmall) {
    AnkaHomeWidget()
} timeline: {
    AnkaHomeEntry(date: Date(), todayExpense: 87_500, todayIncome: 0, recentTransactions: [])
}

#Preview(as: .systemLarge) {
    AnkaHomeWidget()
} timeline: {
    AnkaHomeEntry(
        date: Date(),
        todayExpense: 240_000,
        todayIncome: 5_000_000,
        recentTransactions: [
            WidgetTransaction(id: "1", amount: 45_000, categoryName: "Eating Out", categoryEmoji: "🍽️", note: "Lunch",   isExpense: true),
            WidgetTransaction(id: "2", amount: 25_000, categoryName: "Coffee",     categoryEmoji: "☕",  note: nil,       isExpense: true),
            WidgetTransaction(id: "3", amount: 55_000, categoryName: "Taxi",       categoryEmoji: "🚕", note: "Home",    isExpense: true),
        ]
    )
}
