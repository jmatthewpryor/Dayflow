import Foundation
import Vision
import AppKit

/// Background OCR processing service using Vision framework
actor OCRProcessingService {
    static let shared = OCRProcessingService()

    private let processingInterval: TimeInterval = 60  // Process every minute
    private let batchSize = 10

    private var isProcessing = false
    private var processingTask: Task<Void, Never>?

    struct OCRResult {
        let text: String
        let regions: [TextRegion]
        let confidence: Float
        let processingDurationMs: Int
    }

    struct TextRegion: Codable {
        let text: String
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
        let confidence: Float
    }

    // MARK: - Lifecycle

    /// Start background OCR processing loop
    func startProcessing() {
        guard processingTask == nil else { return }

        isProcessing = true
        processingTask = Task(priority: .utility) {
            await processingLoop()
        }
        dbg("OCR processing started")
    }

    /// Stop background processing
    func stopProcessing() {
        isProcessing = false
        processingTask?.cancel()
        processingTask = nil
        dbg("OCR processing stopped")
    }

    // MARK: - Processing Loop

    private func processingLoop() async {
        while isProcessing && !Task.isCancelled {
            await processBatch()
            try? await Task.sleep(nanoseconds: UInt64(processingInterval * 1_000_000_000))
        }
    }

    private func processBatch() async {
        // Get screenshots that haven't been OCR'd yet
        let unprocessedIds = StorageManager.shared.fetchScreenshotsWithoutOCR(limit: batchSize)

        guard !unprocessedIds.isEmpty else { return }

        dbg("OCR: Processing batch of \(unprocessedIds.count) screenshots")

        for (screenshotId, filePath) in unprocessedIds {
            guard !Task.isCancelled else { break }

            guard let image = loadImage(from: filePath) else {
                dbg("OCR: Failed to load image for screenshot \(screenshotId)")
                continue
            }

            if let result = await performOCR(on: image) {
                StorageManager.shared.saveScreenshotOCR(
                    screenshotId: screenshotId,
                    ocrText: result.text,
                    ocrRegions: result.regions,
                    confidence: result.confidence,
                    processingDurationMs: result.processingDurationMs
                )
                dbg("OCR: Screenshot \(screenshotId) - \(result.text.prefix(50))...")
            }
        }
    }

    // MARK: - Image Loading

    private func loadImage(from path: String) -> CGImage? {
        guard let nsImage = NSImage(contentsOfFile: path),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return cgImage
    }

    // MARK: - OCR Processing

    func performOCR(on image: CGImage) async -> OCRResult? {
        let startTime = Date()

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }

                var allText: [String] = []
                var regions: [TextRegion] = []
                var totalConfidence: Float = 0

                for observation in observations {
                    guard let topCandidate = observation.topCandidates(1).first else { continue }

                    allText.append(topCandidate.string)
                    totalConfidence += topCandidate.confidence

                    // Convert normalized bounding box to region
                    let box = observation.boundingBox
                    regions.append(TextRegion(
                        text: topCandidate.string,
                        x: box.origin.x,
                        y: box.origin.y,
                        width: box.width,
                        height: box.height,
                        confidence: topCandidate.confidence
                    ))
                }

                let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
                let avgConfidence = observations.isEmpty ? 0 : totalConfidence / Float(observations.count)

                let result = OCRResult(
                    text: allText.joined(separator: "\n"),
                    regions: regions,
                    confidence: avgConfidence,
                    processingDurationMs: durationMs
                )

                continuation.resume(returning: result)
            }

            // Configure for accurate recognition
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                dbg("OCR: Vision request failed: \(error.localizedDescription)")
                continuation.resume(returning: nil)
            }
        }
    }
}

