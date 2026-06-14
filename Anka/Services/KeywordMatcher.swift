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

        // ── Global Food Delivery compounds ────────────────────────────────
        ("uber eats",      "Food Delivery"),
        ("ubereats",       "Food Delivery"),

        // ── Global Eating Out compounds ─────────────────────────────────
        ("in n out",       "Eating Out"),
        ("in-n-out",       "Eating Out"),
        ("five guys",      "Eating Out"),
        ("shake shack",    "Eating Out"),
        ("chick fil a",    "Eating Out"),
        ("chick-fil-a",    "Eating Out"),
        ("panda express",  "Eating Out"),
        ("taco bell",      "Eating Out"),

        // ── Global Groceries compounds ──────────────────────────────────
        ("whole foods",    "Groceries"),
        ("trader joe's",   "Groceries"),
        ("trader joes",    "Groceries"),

        // ── Global Shopping compounds ───────────────────────────────────
        ("best buy",       "Shopping"),
        ("home depot",     "Shopping"),
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

        // ── Global Taxi / Rideshare ──────────────────────────────────────
        ("uber",          "Taxi"),
        ("lyft",          "Taxi"),
        ("bolt",          "Taxi"),
        ("careem",        "Taxi"),

        // ── Food Delivery ────────────────────────────────────────────────
        ("anterin",       "Food Delivery"),
        ("delivery",      "Food Delivery"),
        ("pesan makan",   "Food Delivery"),

        // ── Global Food Delivery ─────────────────────────────────────────
        ("doordash",      "Food Delivery"),
        ("postmates",     "Food Delivery"),
        ("deliveroo",     "Food Delivery"),
        ("grubhub",       "Food Delivery"),
        ("seamless",      "Food Delivery"),
        ("wolt",          "Food Delivery"),
        ("glovo",         "Food Delivery"),
        ("justeat",       "Food Delivery"),
        ("just eat",      "Food Delivery"),
        ("takeaway",      "Food Delivery"),

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

        // ── Global Groceries ─────────────────────────────────────────────
        ("walmart",       "Groceries"),
        ("target",        "Groceries"),
        ("costco",        "Groceries"),
        ("kroger",        "Groceries"),
        ("aldi",          "Groceries"),
        ("lidl",          "Groceries"),
        ("tesco",         "Groceries"),
        ("sainsbury",     "Groceries"),
        ("sainsburys",    "Groceries"),
        ("asda",          "Groceries"),
        ("morrisons",     "Groceries"),
        ("waitrose",      "Groceries"),
        ("rewe",          "Groceries"),
        ("edeka",         "Groceries"),
        ("kaufland",      "Groceries"),
        ("mercadona",     "Groceries"),
        ("publix",        "Groceries"),
        ("safeway",       "Groceries"),
        ("wegmans",       "Groceries"),

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

        // ── Global Eating Out ────────────────────────────────────────────
        ("chipotle",      "Eating Out"),
        ("wendy",         "Eating Out"),
        ("wendys",        "Eating Out"),
        ("nando",         "Eating Out"),
        ("nandos",        "Eating Out"),
        ("wagamama",      "Eating Out"),
        ("greggs",        "Eating Out"),
        ("pret",          "Eating Out"),

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

        // ── Global Coffee ────────────────────────────────────────────────
        ("costa",         "Coffee"),
        ("peet",          "Coffee"),
        ("peets",         "Coffee"),
        ("tim hortons",   "Coffee"),
        ("caribou",       "Coffee"),

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

        // ── Global Car / Fuel ────────────────────────────────────────────
        ("chevron",       "Car"),
        ("exxon",         "Car"),
        ("mobil",         "Car"),
        ("texaco",        "Car"),
        ("esso",          "Car"),
        ("totalenergies", "Car"),
        ("aral",          "Car"),

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

        // ── Global Health ────────────────────────────────────────────────
        ("cvs",           "Health"),
        ("walgreens",     "Health"),
        ("boots",         "Health"),
        ("riteaid",       "Health"),

        // ── Shopping ─────────────────────────────────────────────────────
        ("shopee",        "Shopping"),
        ("tokopedia",     "Shopping"),
        ("lazada",        "Shopping"),
        ("bukalapak",     "Shopping"),
        ("blibli",        "Shopping"),
        ("zalora",        "Shopping"),
        ("tiktok shop",   "Shopping"),
        ("belanja",       "Shopping"),

        // ── Global Shopping ──────────────────────────────────────────────
        ("amazon",        "Shopping"),
        ("ebay",          "Shopping"),
        ("etsy",          "Shopping"),
        ("ikea",          "Shopping"),
        ("bestbuy",       "Shopping"),
        ("homedepot",     "Shopping"),
        ("lowes",         "Shopping"),
        ("asos",          "Shopping"),
        ("zara",          "Shopping"),
        ("primark",       "Shopping"),
        ("argos",         "Shopping"),
        ("wayfair",       "Shopping"),
        ("shein",         "Shopping"),

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

        // ── Global Entertainment ─────────────────────────────────────────
        ("hulu",          "Entertainment"),
        ("disneyplus",    "Entertainment"),
        ("hbomax",        "Entertainment"),
        ("hbo",           "Entertainment"),
        ("paramount",     "Entertainment"),
        ("apple tv",      "Entertainment"),
        ("twitch",        "Entertainment"),
        ("xbox",          "Entertainment"),
        ("nintendo",      "Entertainment"),

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

        // ── Global Home / Bills ──────────────────────────────────────────
        ("comcast",       "Home"),
        ("xfinity",       "Home"),
        ("verizon",       "Home"),
        ("vodafone",      "Home"),
        ("mortgage",      "Home"),

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

        // Layer A2: single-keyword exact match.
        // Short keywords (≤ shortKeywordMaxLength chars) use word-boundary
        // matching to avoid false positives like "repair" → Home ("air"),
        // "premiere" → Eating Out ("mie"), "theory" → Coffee ("teh"),
        // "gigantic" → Groceries ("giant"). Brand names and longer keywords
        // still use plain substring so "indomaret" matches "ke indomaret".
        // (AUDIT.md X6)
        let words = lower.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        for (keyword, category) in singleKeywords {
            if keyword.count <= shortKeywordMaxLength || shortKeywords.contains(keyword) {
                // Word-boundary match: the keyword must appear as a whole
                // word (or multi-word phrase) in the input.
                if keyword.contains(" ") {
                    // Multi-word short keyword — use the same compound logic.
                    if lower.contains(keyword) { return (category, 0.90) }
                } else {
                    if words.contains(keyword) { return (category, 0.90) }
                }
            } else {
                if lower.contains(keyword) { return (category, 0.90) }
            }
        }

        // Layer B: fuzzy per-word (Levenshtein ≤ 1)
        // Only applied to single-word keywords with ≥ 4 chars to avoid false positives
        // on short tokens like "air", "teh", "mie", "tol", "ipl", "kfc".
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

    // MARK: - Word-boundary config (AUDIT.md X6)

    /// Keywords at or below this length use word-boundary matching instead of
    /// substring matching. Covers the documented false-positive cases: "air"(3),
    /// "teh"(3), "mie"(3), "tol"(3), "ipl"(3), "kfc"(3), "cafe"(4), "kafe"(4),
    /// "hero"(4), "kost"(4), "sewa"(4), "obat"(4), "grab"(4), "giant"(5),
    /// "token"(5), "solar"(5), "steam"(5).
    private static let shortKeywordMaxLength = 5

    /// Explicit overrides for keywords longer than `shortKeywordMaxLength` that
    /// still need word-boundary matching because they're common English/Indonesian
    /// words that appear as substrings in unrelated words.
    private static let shortKeywords: Set<String> = [
        // Longer global keywords that double as common English words —
        // word-boundary matching avoids "of paramount importance" → Entertainment,
        // "savings target" → Groceries, "muscle twitch" → Entertainment.
        "target",
        "paramount",
        "twitch",
    ]

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
