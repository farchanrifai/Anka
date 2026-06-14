import Foundation
import CoreML
import SwiftData

#if canImport(CreateML) && canImport(TabularData)
import CreateML
import TabularData
#endif

/// A thread-safe representation of a transaction used for ML training.
public struct TrainableTransaction: Sendable {
    public let note: String
    public let amount: Double
    public let categoryName: String

    public init(note: String, amount: Double, categoryName: String) {
        self.note = note
        self.amount = amount
        self.categoryName = categoryName
    }
}

/// On-device training for the user's personal category classifier.
/// Uses CreateML's MLTextClassifier (available on macOS and iOS 16+
/// when the CreateML framework is importable in the build target).
/// On builds where CreateML is unavailable, `trainIfNeeded` is a no-op —
/// inference still works via the bundled StarterCategoryClassifier.
public enum CategoryMLTrainer {
    private static let lastCountKey = MLStorage.lastTrainCountKey
    private static let appGroupID   = PlatformPaths.appGroupID

    // MARK: - Public

    public static func trainIfNeeded(transactions: [TrainableTransaction]) async throws {
        guard transactions.count >= 20 else { return }

        let defaults  = UserDefaults(suiteName: appGroupID)
        let lastCount = defaults?.integer(forKey: lastCountKey) ?? 0
        guard transactions.count >= lastCount + 10 || lastCount == 0 else { return }

#if canImport(CreateML) && canImport(TabularData)
        try await train(labeled: transactions, defaults: defaults, newCount: transactions.count)
#endif
    }

    // MARK: - Training (CreateML path)

#if canImport(CreateML) && canImport(TabularData)
    private static func train(labeled: [TrainableTransaction], defaults: UserDefaults?, newCount: Int) async throws {
        var texts:  [String] = []
        var labels: [String] = []

        // Same amounts used to compute the median for inference's
        // `amountBucket`, so train/inference buckets line up.
        let recentAmounts = labeled.map { $0.amount }

        for tx in labeled {
            texts.append(MLFeaturizer.input(note: tx.note, amount: tx.amount, recentAmounts: recentAmounts))
            labels.append(tx.categoryName)
        }

        // Include correction examples at 2x weight to prioritize user feedback.
        // Snapshot the count so we can prune exactly these absorbed entries after
        // a successful train (AUDIT.md P6) without dropping corrections the user
        // makes while training runs.
        let corrections = loadCorrections()
        for entry in corrections {
            guard let actual = entry.actual,
                  !entry.note.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let text = MLFeaturizer.input(note: entry.note, amount: entry.amount, recentAmounts: recentAmounts)
            texts.append(contentsOf: [text, text])
            labels.append(contentsOf: [actual, actual])
        }

        guard texts.count >= 20 else { return }

        var df = DataFrame()
        df.append(column: Column<String>(name: "text",  contents: texts))
        df.append(column: Column<String>(name: "label", contents: labels))

        // MLTextClassifier.init is a blocking CPU-intensive call.
        // Run it in a detached task so it never executes on the main actor.
        let tempURL = try await Task.detached(priority: .background) {
            let classifier = try MLTextClassifier(
                trainingData: df,
                textColumn: "text",
                labelColumn: "label"
            )
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("UserCategoryClassifier_\(UUID().uuidString).mlmodel")
            try classifier.write(to: url)
            return url
        }.value

        // Compile the written .mlmodel to .mlmodelc.
        let compiledURL = try await MLModel.compileModel(at: tempURL)

        // Move to shared container.
        let destURL = PlatformPaths.appGroupContainerURL
            .appendingPathComponent("UserCategoryClassifier.mlmodelc")

        let fm = FileManager.default
        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }
        try fm.copyItem(at: compiledURL, to: destURL)

        try? fm.removeItem(at: tempURL)
        try? fm.removeItem(at: compiledURL)

        defaults?.set(newCount, forKey: lastCountKey)
        // These corrections are now baked into the user model — age them out so
        // they don't double-count in every future training pass (P6).
        pruneCorrections(absorbed: corrections.count)
    }
#endif

    // MARK: - Corrections

    private static let correctionsKey = MLStorage.correctionsKey

    private static func loadCorrections() -> [CorrectionEntry] {
        let defaults = UserDefaults(suiteName: appGroupID)
        guard let data = defaults?.data(forKey: correctionsKey),
              let entries = try? JSONDecoder().decode([CorrectionEntry].self, from: data) else {
            return []
        }
        return entries
    }

    /// Drops the first `absorbed` correction entries (the ones folded into the
    /// just-trained model), preserving any added while training ran. Corrections
    /// are appended in order, so the oldest `absorbed` are the consumed ones.
    private static func pruneCorrections(absorbed: Int) {
        guard absorbed > 0 else { return }
        let defaults = UserDefaults(suiteName: appGroupID)
        guard let data = defaults?.data(forKey: correctionsKey),
              var entries = try? JSONDecoder().decode([CorrectionEntry].self, from: data) else { return }
        if entries.count <= absorbed {
            defaults?.removeObject(forKey: correctionsKey)
        } else {
            entries.removeFirst(absorbed)
            if let encoded = try? JSONEncoder().encode(entries) {
                defaults?.set(encoded, forKey: correctionsKey)
            }
        }
    }
}
