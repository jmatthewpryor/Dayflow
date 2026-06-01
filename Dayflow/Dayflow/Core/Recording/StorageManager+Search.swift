import Foundation
import GRDB

extension StorageManager {
  /// Search screenshots using FTS5 full-text search
  func searchScreenshots(
    ftsQuery: String, filters: SearchService.SearchFilters?, limit: Int, offset: Int
  ) -> [SearchService.SearchResult] {
    (try? timedRead("searchScreenshots") { db in
      var conditions: [String] = []
      var arguments: [DatabaseValueConvertible] = []

      if let dateRange = filters?.dateRange {
        let startTs = Int(dateRange.lowerBound.timeIntervalSince1970)
        let endTs = Int(dateRange.upperBound.timeIntervalSince1970)
        conditions.append("s.captured_at >= ? AND s.captured_at <= ?")
        arguments.append(contentsOf: [startTs, endTs])
      }

      if let bundleIds = filters?.appBundleIds, !bundleIds.isEmpty {
        let placeholders = bundleIds.map { _ in "?" }.joined(separator: ", ")
        conditions.append("c.bundle_id IN (\(placeholders))")
        arguments.append(contentsOf: bundleIds)
      }

      let whereClause =
        conditions.isEmpty ? "" : " AND " + conditions.joined(separator: " AND ")

      arguments.insert(ftsQuery, at: 0)

      let sql = """
            SELECT
                s.id,
                s.file_path,
                s.captured_at,
                substr(o.ocr_text, 1, 200) AS matched_text,
                c.app_name,
                c.window_title,
                c.bundle_id,
                c.browser_url,
                o.ocr_regions
            FROM screenshot_search fts
            JOIN screenshots s ON s.id = fts.rowid
            LEFT JOIN screenshot_ocr o ON o.screenshot_id = s.id
            LEFT JOIN screenshot_context c ON c.screenshot_id = s.id
            WHERE screenshot_search MATCH ?
              AND s.is_deleted = 0
            \(whereClause)
            ORDER BY fts.rank, s.captured_at DESC
            LIMIT ? OFFSET ?
        """

      arguments.append(limit)
      arguments.append(offset)

      return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        .map { row in
          var ocrRegions: [SearchService.TextRegion] = []
          if let regionsJson = row["ocr_regions"] as? String,
            let data = regionsJson.data(using: .utf8)
          {
            ocrRegions =
              (try? JSONDecoder().decode([SearchService.TextRegion].self, from: data)) ?? []
          }

          return SearchService.SearchResult(
            id: row["id"] ?? 0,
            screenshotPath: row["file_path"] ?? "",
            capturedAt: Date(
              timeIntervalSince1970: TimeInterval(row["captured_at"] as Int? ?? 0)),
            matchedText: row["matched_text"] ?? "",
            appName: row["app_name"],
            windowTitle: row["window_title"],
            bundleId: row["bundle_id"],
            browserURL: row["browser_url"],
            ocrRegions: ocrRegions
          )
        }
    }) ?? []
  }

  /// Fetch distinct apps for filter dropdown
  func fetchDistinctApps() -> [SearchService.AppInfo] {
    (try? timedRead("fetchDistinctApps") { db in
      try Row.fetchAll(
        db,
        sql: """
              SELECT c.app_name, c.bundle_id, COUNT(*) as count
              FROM screenshot_context c
              JOIN screenshots s ON s.id = c.screenshot_id
              WHERE s.is_deleted = 0
                AND c.bundle_id IS NOT NULL
              GROUP BY c.bundle_id
              ORDER BY count DESC
          """
      )
      .compactMap { row -> SearchService.AppInfo? in
        guard let name: String = row["app_name"],
          let bundleId: String = row["bundle_id"],
          let count: Int = row["count"]
        else { return nil }
        return SearchService.AppInfo(name: name, bundleId: bundleId, count: count)
      }
    }) ?? []
  }
}
