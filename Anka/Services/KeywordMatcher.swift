import Foundation

/// Layer 1 of category prediction — static keyword dictionary, no ML required.
/// Returns confidence of 0.90 for all keyword hits.
public enum KeywordMatcher {

    // MARK: - Compound keywords (checked first)

    // Multi-word phrases that must win over any single-word prefix they contain.
    // e.g. "grab food" must beat "grab" → Taxi.
    private static let compoundKeywords: [(keyword: String, category: String)] = [
        // ── Food Delivery compounds ──────────────────────────────────────
        ("shopee food",    "Food Delivery"),
        ("shopeefood",     "Food Delivery"),
        ("grab food",      "Food Delivery"),
        ("grabfood",       "Food Delivery"),
        ("gofood",         "Food Delivery"),
        ("go food",        "Food Delivery"),
        ("gojek food",     "Food Delivery"),
        ("traveloka food", "Food Delivery"),

        // ── Taxi compounds ───────────────────────────────────────────────
        ("grab car",       "Taxi"),
        ("grab bike",      "Taxi"),
        ("go car",         "Taxi"),
        ("go ride",        "Taxi"),
    ]

    // MARK: - Single keywords (checked after compounds)

    private static let singleKeywords: [(keyword: String, category: String)] = [
        // ── Transport (Taxi) ─────────────────────────────────────────────
        ("grab",          "Taxi"),
        ("gojek",         "Taxi"),
        ("gocar",         "Taxi"),
        ("goxtra",        "Taxi"),
        ("blue bird",     "Taxi"),
        ("bluebird",      "Taxi"),
        ("maxim",         "Taxi"),
        ("indriver",      "Taxi"),
        ("ojek",          "Taxi"),

        // ── Food Delivery ────────────────────────────────────────────────
        ("anterin",       "Food Delivery"),
        ("delivery",      "Food Delivery"),
        ("pesan makan",   "Food Delivery"),

        // ── Groceries ────────────────────────────────────────────────────
        ("indomaret",     "Groceries"),
        ("alfamart",      "Groceries"),
        ("superindo",     "Groceries"),
        ("hypermart",     "Groceries"),
        ("giant",         "Groceries"),
        ("carrefour",     "Groceries"),
        ("hero",          "Groceries"),
        ("lotte mart",    "Groceries"),
        ("lottemart",     "Groceries"),
        ("indogrosir",    "Groceries"),
        ("transmart",     "Groceries"),
        ("ranch market",  "Groceries"),
        ("farmers market","Groceries"),
        ("pasar",         "Groceries"),
        ("sayur",         "Groceries"),
        ("beras",         "Groceries"),
        ("sembako",       "Groceries"),

        // ── Eating Out ───────────────────────────────────────────────────
        ("kfc",           "Eating Out"),
        ("mcdonald",      "Eating Out"),
        ("mcdonalds",     "Eating Out"),
        ("burger king",   "Eating Out"),
        ("pizza hut",     "Eating Out"),
        ("domino",        "Eating Out"),
        ("subway",        "Eating Out"),
        ("warteg",        "Eating Out"),
        ("warung makan",  "Eating Out"),
        ("rumah makan",   "Eating Out"),
        ("bakso",         "Eating Out"),
        ("mie ayam",      "Eating Out"),
        ("soto",          "Eating Out"),
        ("nasi padang",   "Eating Out"),
        ("nasi goreng",   "Eating Out"),
        ("makan",         "Eating Out"),
        ("restoran",      "Eating Out"),
        ("restaurant",    "Eating Out"),
        ("mie",           "Eating Out"),

        // ── Coffee ───────────────────────────────────────────────────────
        ("starbucks",     "Coffee"),
        ("kopi",          "Coffee"),
        ("coffee",        "Coffee"),
        ("kopitiam",      "Coffee"),
        ("janji jiwa",    "Coffee"),
        ("jiwa",          "Coffee"),
        ("fore coffee",   "Coffee"),
        ("kulo",          "Coffee"),
        ("kopi kenangan", "Coffee"),
        ("kenangan",      "Coffee"),
        ("excelso",       "Coffee"),
        ("toraja",        "Coffee"),
        ("cafe",          "Coffee"),
        ("kafe",          "Coffee"),
        ("teh",           "Coffee"),

        // ── Car / Fuel ───────────────────────────────────────────────────
        ("spbu",          "Car"),
        ("pertamina",     "Car"),
        ("shell",         "Car"),
        ("bensin",        "Car"),
        ("solar",         "Car"),
        ("parkir",        "Car"),
        ("parking",       "Car"),
        ("tol",           "Car"),
        ("bengkel",       "Car"),
        ("ganti oli",     "Car"),
        ("servis motor",  "Car"),
        ("servis mobil",  "Car"),

        // ── Health ───────────────────────────────────────────────────────
        ("apotek",        "Health"),
        ("apotik",        "Health"),
        ("kimia farma",   "Health"),
        ("guardian",      "Health"),
        ("century",       "Health"),
        ("dokter",        "Health"),
        ("klinik",        "Health"),
        ("rumah sakit",   "Health"),
        ("puskesmas",     "Health"),
        ("obat",          "Health"),
        ("vitamin",       "Health"),
        ("kesehatan",     "Health"),

        // ── Shopping ─────────────────────────────────────────────────────
        ("shopee",        "Shopping"),
        ("tokopedia",     "Shopping"),
        ("lazada",        "Shopping"),
        ("bukalapak",     "Shopping"),
        ("blibli",        "Shopping"),
        ("zalora",        "Shopping"),
        ("tiktok shop",   "Shopping"),
        ("belanja",       "Shopping"),

        // ── Entertainment ────────────────────────────────────────────────
        ("netflix",       "Entertainment"),
        ("spotify",       "Entertainment"),
        ("youtube",       "Entertainment"),
        ("cgv",           "Entertainment"),
        ("cinepolis",     "Entertainment"),
        ("xxi",           "Entertainment"),
        ("bioskop",       "Entertainment"),
        ("disney",        "Entertainment"),
        ("vidio",         "Entertainment"),
        ("steam",         "Entertainment"),
        ("playstation",   "Entertainment"),
        ("nonton",        "Entertainment"),
        ("hiburan",       "Entertainment"),

        // ── Home / Bills ─────────────────────────────────────────────────
        ("pln",           "Home"),
        ("pdam",          "Home"),
        ("indihome",      "Home"),
        ("indosat",       "Home"),
        ("telkomsel",     "Home"),
        ("listrik",       "Home"),
        ("air",           "Home"),
        ("internet",      "Home"),
        ("wifi",          "Home"),
        ("kontrakan",     "Home"),
        ("sewa",          "Home"),
        ("kost",          "Home"),
        ("ipl",           "Home"),
        ("token",         "Home"),

        // ── Income ───────────────────────────────────────────────────────
        ("gaji",          "Salary"),
        ("salary",        "Salary"),
        ("payroll",       "Salary"),
        ("dividen",       "Investment"),
        ("dividend",      "Investment"),
        ("investasi",     "Investment"),
        ("saham",         "Investment"),
        ("reksa dana",    "Investment"),
        ("freelance",     "Freelance"),
    ]

    // MARK: - API

    /// Returns the matching category name and confidence 0.90, or nil.
    /// Compound keywords are checked first so "grab food" beats "grab".
    /// Fuzzy per-word matching runs only when exact substring fails.
    public static func match(note: String) -> (category: String, confidence: Double)? {
        let lower = note.lowercased()

        // Layer A1: compound exact match (priority pass)
        for (keyword, category) in compoundKeywords {
            if lower.contains(keyword) {
                return (category, 0.90)
            }
        }

        // Layer A2: single-keyword exact match
        for (keyword, category) in singleKeywords {
            if lower.contains(keyword) {
                return (category, 0.90)
            }
        }

        // Layer B: fuzzy per-word (Levenshtein ≤ 1)
        // Only applied to single-word keywords with ≥ 4 chars to avoid false positives
        // on short tokens like "air", "teh", "mie", "tol", "ipl", "kfc".
        let words = lower.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        for (keyword, category) in singleKeywords {
            guard !keyword.contains(" "), keyword.count >= 4 else { continue }
            for word in words {
                // Length pre-check: edit distance ≥ length difference, so skip if gap > 1
                guard abs(word.count - keyword.count) <= 1 else { continue }
                if levenshtein(word, keyword) <= 1 {
                    return (category, 0.90)
                }
            }
        }

        return nil
    }

    // MARK: - Levenshtein distance

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        let m = a.count, n = b.count
        guard m > 0 else { return n }
        guard n > 0 else { return m }
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }
        for i in 1...m {
            for j in 1...n {
                dp[i][j] = a[i-1] == b[j-1]
                    ? dp[i-1][j-1]
                    : 1 + min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1])
            }
        }
        return dp[m][n]
    }
}
