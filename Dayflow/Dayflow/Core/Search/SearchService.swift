import Foundation

/// Search service for querying screenshots via FTS5
actor SearchService {
    static let shared = SearchService()

    /// OCR text region with normalized bounding box (0-1 range, Vision coordinates)
    struct TextRegion: Codable, Sendable, Hashable {
        let text: String
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
        let confidence: Float
    }

    struct SearchResult: Identifiable, Sendable {
        let id: Int64  // screenshot_id
        let screenshotPath: String
        let capturedAt: Date
        let matchedText: String  // With <mark> tags for highlighting
        let appName: String?
        let windowTitle: String?
        let bundleId: String?
        let browserURL: String?
        let ocrRegions: [TextRegion]  // All OCR regions for highlighting
    }

    struct SearchFilters: Sendable {
        var appBundleIds: [String]?
        var dateRange: ClosedRange<Date>?

        init(appBundleIds: [String]? = nil, dateRange: ClosedRange<Date>? = nil) {
            self.appBundleIds = appBundleIds
            self.dateRange = dateRange
        }
    }

    struct AppInfo: Sendable, Identifiable, Hashable {
        var id: String { bundleId }
        let name: String
        let bundleId: String
        let count: Int
    }

    // MARK: - Search

    /// Search screenshots using FTS5 full-text search
    func search(query: String, filters: SearchFilters? = nil, limit: Int = 50, offset: Int = 0) async -> [SearchResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        // Convert query to FTS5 match format with prefix matching
        let ftsQuery = buildFTSQuery(query)

        return StorageManager.shared.searchScreenshots(
            ftsQuery: ftsQuery,
            filters: filters,
            limit: limit,
            offset: offset
        )
    }

    /// Get list of apps that have been captured (for filter dropdown)
    func getAvailableApps() async -> [AppInfo] {
        StorageManager.shared.fetchDistinctApps()
    }

    // MARK: - Query Building

    /// Common English stop words to filter from search queries
    private let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "by", "for",
        "from", "has", "he", "in", "is", "it", "its", "of", "on",
        "or", "that", "the", "to", "was", "were", "will", "with"
    ]

    private func buildFTSQuery(_ query: String) -> String {
        // Normalize quotes (smart quotes to straight quotes)
        let normalized = query
            .replacingOccurrences(of: "\u{201C}", with: "\"")  // Left double quote
            .replacingOccurrences(of: "\u{201D}", with: "\"")  // Right double quote
            .replacingOccurrences(of: "\u{2018}", with: "'")   // Left single quote
            .replacingOccurrences(of: "\u{2019}", with: "'")
        let trimmed = normalized.trimmingCharacters(in: .whitespaces)

        // Check for quoted phrase (exact match)
        if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") && trimmed.count > 2 {
            // Return as-is for exact phrase matching (FTS5 handles quoted phrases)
            return trimmed
        }

        // Split into words, filter stop words, add prefix matching
        let words = trimmed
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .filter { !stopWords.contains($0.lowercased()) }

        guard !words.isEmpty else {
            // If all words were stop words, use original query
            return trimmed.components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
                .map { "\"\($0)\"*" }
                .joined(separator: " ")
        }

        if words.count == 1 {
            // Single word: prefix match
            return "\"\(words[0])\"*"
        } else {
            // Multiple words: each word as prefix match, joined with implicit AND
            return words.map { "\"\($0)\"*" }.joined(separator: " ")
        }
    }
}
