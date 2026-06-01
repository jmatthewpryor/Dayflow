import Foundation
import GRDB
import Sentry

extension StorageManager {
  // MARK: - Screenshot Management (new - replaces video chunks)

  func nextScreenshotURL() -> URL {
    let df = DateFormatter()
    df.dateFormat = "yyyyMMdd_HHmmssSSS"
    return root.appendingPathComponent("\(df.string(from: Date())).jpg")
  }

  func saveScreenshot(url: URL, capturedAt: Date, idleSecondsAtCapture: Int?) -> Int64? {
    let timestamp = Int(capturedAt.timeIntervalSince1970)
    let path = url.path
    let fileSize: Int64? = {
      if let attrs = try? fileMgr.attributesOfItem(atPath: path),
        let size = attrs[.size] as? NSNumber
      {
        return size.int64Value
      }
      return nil
    }()

    var screenshotId: Int64?
    try? timedWrite("saveScreenshot") { db in
      try db.execute(
        sql: """
              INSERT INTO screenshots(captured_at, file_path, file_size, idle_seconds_at_capture)
              VALUES (?, ?, ?, ?)
          """, arguments: [timestamp, path, fileSize, idleSecondsAtCapture])
      screenshotId = db.lastInsertedRowID
    }
    return screenshotId
  }

  func screenshot(from row: Row) -> Screenshot {
    Screenshot(
      id: row["id"],
      capturedAt: row["captured_at"],
      filePath: row["file_path"],
      fileSize: row["file_size"],
      idleSecondsAtCapture: row["idle_seconds_at_capture"],
      isDeleted: (row["is_deleted"] as? Int ?? 0) != 0
    )
  }

  func fetchUnprocessedScreenshots(since oldestTimestamp: Int) -> [Screenshot] {
    (try? timedRead("fetchUnprocessedScreenshots") { db in
      try Row.fetchAll(
        db,
        sql: """
              SELECT * FROM screenshots
              WHERE captured_at >= ?
                AND is_deleted = 0
                AND id NOT IN (SELECT screenshot_id FROM batch_screenshots)
              ORDER BY captured_at ASC
          """, arguments: [oldestTimestamp]
      )
      .map(screenshot(from:))
    }) ?? []
  }

  func saveBatchWithScreenshots(startTs: Int, endTs: Int, screenshotIds: [Int64]) -> Int64? {
    guard !screenshotIds.isEmpty else { return nil }
    var batchId: Int64 = 0

    try? timedWrite("saveBatchWithScreenshots(\(screenshotIds.count))") { db in
      try db.execute(
        sql: """
              INSERT INTO analysis_batches(batch_start_ts, batch_end_ts)
              VALUES (?, ?)
          """, arguments: [startTs, endTs])
      batchId = db.lastInsertedRowID

      for id in screenshotIds {
        try db.execute(
          sql: """
                INSERT INTO batch_screenshots(batch_id, screenshot_id)
                VALUES (?, ?)
            """, arguments: [batchId, id])
      }
    }
    return batchId == 0 ? nil : batchId
  }

  func screenshotsForBatch(_ batchId: Int64) -> [Screenshot] {
    (try? timedRead("screenshotsForBatch") { db in
      try Row.fetchAll(
        db,
        sql: """
              SELECT s.* FROM batch_screenshots bs
              JOIN screenshots s ON s.id = bs.screenshot_id
              WHERE bs.batch_id = ?
                AND s.is_deleted = 0
              ORDER BY s.captured_at ASC
          """, arguments: [batchId]
      )
      .map(screenshot(from:))
    }) ?? []
  }

  func fetchScreenshotsInTimeRange(startTs: Int, endTs: Int) -> [Screenshot] {
    (try? timedRead("fetchScreenshotsInTimeRange") { db in
      try Row.fetchAll(
        db,
        sql: """
              SELECT * FROM screenshots
              WHERE captured_at >= ? AND captured_at <= ?
                AND is_deleted = 0
              ORDER BY captured_at ASC
          """, arguments: [startTs, endTs]
      )
      .map(screenshot(from:))
    }) ?? []
  }

  // MARK: - Search Feature

  /// Save app context captured at screenshot time (for search feature)
  func saveScreenshotContext(
    screenshotId: Int64, appName: String?, bundleId: String?, windowTitle: String?,
    browserURL: String?
  ) {
    try? timedWrite("saveScreenshotContext") { db in
      try db.execute(
        sql: """
              INSERT INTO screenshot_context(screenshot_id, app_name, bundle_id, window_title, browser_url)
              VALUES (?, ?, ?, ?, ?)
          """, arguments: [screenshotId, appName, bundleId, windowTitle, browserURL])
    }
  }

  /// Fetch screenshots that haven't been OCR processed yet
  func fetchScreenshotsWithoutOCR(limit: Int) -> [(screenshotId: Int64, filePath: String)] {
    (try? timedRead("fetchScreenshotsWithoutOCR") { db in
      try Row.fetchAll(
        db,
        sql: """
              SELECT s.id, s.file_path FROM screenshots s
              LEFT JOIN screenshot_ocr o ON s.id = o.screenshot_id
              WHERE o.id IS NULL
                AND s.is_deleted = 0
              ORDER BY s.captured_at DESC
              LIMIT ?
          """, arguments: [limit]
      )
      .compactMap { row -> (Int64, String)? in
        guard let id: Int64 = row["id"],
          let path: String = row["file_path"]
        else { return nil }
        return (id, path)
      }
    }) ?? []
  }

  /// Save OCR results for a screenshot
  func saveScreenshotOCR(
    screenshotId: Int64, ocrText: String, ocrRegions: [OCRProcessingService.TextRegion],
    confidence: Float, processingDurationMs: Int
  ) {
    let regionsJSON: String? = {
      guard !ocrRegions.isEmpty else { return nil }
      let encoder = JSONEncoder()
      if let data = try? encoder.encode(ocrRegions) {
        return String(data: data, encoding: .utf8)
      }
      return nil
    }()

    try? timedWrite("saveScreenshotOCR") { db in
      try db.execute(
        sql: """
              INSERT INTO screenshot_ocr(screenshot_id, ocr_text, ocr_regions, confidence, processing_duration_ms)
              VALUES (?, ?, ?, ?, ?)
          """, arguments: [screenshotId, ocrText, regionsJSON, confidence, processingDurationMs])

      // Also update FTS index
      if let contextRow = try? Row.fetchOne(
        db,
        sql: """
              SELECT app_name, window_title, browser_url FROM screenshot_context
              WHERE screenshot_id = ?
          """, arguments: [screenshotId])
      {
        let appName: String? = contextRow["app_name"]
        let windowTitle: String? = contextRow["window_title"]
        let browserURL: String? = contextRow["browser_url"]

        try db.execute(
          sql: """
                INSERT INTO screenshot_search(rowid, ocr_text, window_title, app_name, browser_url)
                VALUES (?, ?, ?, ?, ?)
            """, arguments: [screenshotId, ocrText, windowTitle, appName, browserURL])
      } else {
        try db.execute(
          sql: """
                INSERT INTO screenshot_search(rowid, ocr_text, window_title, app_name, browser_url)
                VALUES (?, ?, NULL, NULL, NULL)
            """, arguments: [screenshotId, ocrText])
      }
    }
  }

}
