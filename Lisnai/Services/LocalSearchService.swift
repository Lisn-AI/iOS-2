import Foundation
import SwiftData
import Accelerate

/// On-device vector similarity search using Apple's Accelerate framework (vDSP)
/// Provides cosine similarity search over locally stored memory embeddings
class LocalSearchService {
    static let shared = LocalSearchService()

    struct LocalSearchResult {
        let memory: LocalMemory
        let score: Float
    }

    // MARK: - Vector Search

    /// Search local memories by embedding similarity
    /// 1. Call /api/embed to get query vector
    /// 2. Load local memory embeddings from SwiftData
    /// 3. Compute cosine similarity using vDSP (SIMD-accelerated)
    /// 4. Return top-k results above threshold
    func searchMemories(
        query: String,
        limit: Int = 10,
        threshold: Float = 0.35,
        context: ModelContext
    ) async -> [LocalSearchResult] {
        print("[LocalSearch] Hybrid search — query=\"\(query.prefix(50))\", limit=\(limit), threshold=\(threshold)")

        // Always run keyword search in parallel (catches proper nouns, dates, names missed by vector)
        let keywordResults = keywordSearch(query: query, limit: limit * 2, context: context)
        print("[LocalSearch] Keyword search: \(keywordResults.count) results")

        // Step 1: Get query embedding from backend
        guard let queryEmbedding = await generateEmbedding(text: query) else {
            print("[LocalSearch] Embedding generation failed — returning keyword results only")
            let mapped = keywordResults.map { LocalSearchResult(memory: $0, score: 0.45) }
            return Array(mapped.prefix(limit))
        }

        print("[LocalSearch] Query embedding generated (\(queryEmbedding.count) dims)")

        // Step 2: Fetch all memories with embeddings
        let descriptor = FetchDescriptor<LocalMemory>(
            predicate: #Predicate { $0.embeddingData != nil }
        )
        guard let memories = try? context.fetch(descriptor), !memories.isEmpty else {
            print("[LocalSearch] No local memories with embeddings — returning keyword results")
            return keywordResults.map { LocalSearchResult(memory: $0, score: 0.45) }
        }

        print("[LocalSearch] Searching \(memories.count) local memories with vDSP cosine similarity")

        // Step 3: Vector similarity for all memories
        var vectorResults: [LocalSearchResult] = []
        for memory in memories {
            guard let memoryEmbedding = memory.embedding else { continue }
            let score = cosineSimilarity(queryEmbedding, memoryEmbedding)
            if score >= threshold {
                vectorResults.append(LocalSearchResult(memory: memory, score: score))
            }
        }
        vectorResults.sort { $0.score > $1.score }
        print("[LocalSearch] Vector: \(vectorResults.count) above threshold \(threshold)")

        // Step 4: Merge hybrid results — vector score takes priority for overlap
        var seen = Set<UUID>()
        var merged: [LocalSearchResult] = []

        for result in vectorResults {
            if !seen.contains(result.memory.id) {
                seen.insert(result.memory.id)
                merged.append(result)
            }
        }
        // Add keyword-only matches with a 0.4 score (below typical vector hits, above threshold)
        for memory in keywordResults {
            if !seen.contains(memory.id) {
                seen.insert(memory.id)
                merged.append(LocalSearchResult(memory: memory, score: 0.40))
            }
        }

        // Step 5: Also search Recordings directly (catches everything even without LocalMemory)
        let recordingMatches = searchRecordingTranscripts(query: query, limit: limit, context: context)
        for match in recordingMatches {
            if !seen.contains(match.memory.id) {
                seen.insert(match.memory.id)
                merged.append(match)
            }
        }

        merged.sort { $0.score > $1.score }
        let topResults = Array(merged.prefix(limit))
        print("[LocalSearch] Hybrid merged: \(topResults.count) results (best score=\(topResults.first?.score ?? 0))")
        return topResults
    }

    /// Search Recording transcriptions directly — catches recordings that have no LocalMemory
    private func searchRecordingTranscripts(
        query: String,
        limit: Int = 10,
        context: ModelContext
    ) -> [LocalSearchResult] {
        let lowercased = query.lowercased()
        let keywords = lowercased.split(separator: " ").map(String.init).filter { $0.count >= 2 }
        guard !keywords.isEmpty else { return [] }

        let descriptor = FetchDescriptor<Recording>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        guard let recordings = try? context.fetch(descriptor) else { return [] }

        var results: [LocalSearchResult] = []

        for recording in recordings.prefix(100) { // Cap to avoid scanning too many
            let transcript = (recording.transcription?.text ?? "").lowercased()
            let title = (recording.title ?? "").lowercased()
            guard !transcript.isEmpty else { continue }

            var matchCount = 0
            for keyword in keywords {
                if transcript.contains(keyword) { matchCount += 1 }
                if title.contains(keyword) { matchCount += 2 }
            }

            guard matchCount > 0 else { continue }

            // Check if we already have a LocalMemory for this recording
            let recordingId = recording.id
            let memDescriptor = FetchDescriptor<LocalMemory>(
                predicate: #Predicate { $0.recordingId == recordingId }
            )
            if let existingMemory = try? context.fetch(memDescriptor).first {
                // Already covered by LocalMemory search — skip
                continue
            }

            // Create a synthetic LocalMemory result from the Recording
            let syntheticMemory = LocalMemory(
                serverMemoryId: nil,
                timestamp: recording.date,
                title: recording.title,
                rawTranscript: String(transcript.prefix(500)),
                summary: recording.summary?.text,
                isSynced: false
            )
            syntheticMemory.recordingId = recording.id

            let score = Float(matchCount) / Float(keywords.count) * 0.5 // Scale to 0-0.5 range
            results.append(LocalSearchResult(memory: syntheticMemory, score: min(score, 0.5)))
        }

        print("[LocalSearch] Recording transcript search: \(results.count) results")
        return results
    }

    // MARK: - Keyword Search (Fallback)

    /// Simple keyword search on rawTranscript + topics + people
    func keywordSearch(
        query: String,
        limit: Int = 10,
        context: ModelContext
    ) -> [LocalMemory] {
        let lowercased = query.lowercased()
        let keywords = lowercased.split(separator: " ").map(String.init)

        let descriptor = FetchDescriptor<LocalMemory>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        guard let allMemories = try? context.fetch(descriptor) else { return [] }

        // Score each memory by keyword matches
        var scored: [(memory: LocalMemory, score: Int)] = []

        for memory in allMemories {
            var score = 0
            let transcript = memory.rawTranscript.lowercased()
            let title = (memory.title ?? "").lowercased()
            let topics = memory.topics.map { $0.lowercased() }
            let people = memory.people.map { $0.lowercased() }

            for keyword in keywords {
                if transcript.contains(keyword) { score += 1 }
                if title.contains(keyword) { score += 2 }
                if topics.contains(where: { $0.contains(keyword) }) { score += 3 }
                if people.contains(where: { $0.contains(keyword) }) { score += 3 }
            }

            if score > 0 {
                scored.append((memory, score))
            }
        }

        scored.sort { $0.score > $1.score }
        return Array(scored.prefix(limit).map(\.memory))
    }

    // MARK: - Recording-Based Search (same source as History page)

    /// Return the N most recent Recordings as context — reads from the SAME SwiftData
    /// model as the History page, guaranteeing anything visible there is available to chat.
    func recentRecordingsAsContext(limit: Int = 3, context: ModelContext) -> [LocalSearchResult] {
        let descriptor = FetchDescriptor<Recording>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        guard let recordings = try? context.fetch(descriptor) else { return [] }
        let top = Array(recordings.prefix(limit))
        let results = top.compactMap { recordingToSearchResult($0, score: 0.70, context: context) }
        print("[LocalSearch] Recent recordings: \(results.count) from History")
        return results
    }

    /// Fetch all Recordings within a date window — same source as History page.
    /// Used for temporal queries ("what happened on the 25th") to ensure ALL history is covered.
    func recordingsInDateRange(from: Date, to: Date, context: ModelContext) -> [LocalSearchResult] {
        let descriptor = FetchDescriptor<Recording>(
            predicate: #Predicate { $0.date >= from && $0.date <= to },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        guard let recordings = try? context.fetch(descriptor) else { return [] }
        let results = recordings.compactMap { recordingToSearchResult($0, score: 0.65, context: context) }
        print("[LocalSearch] Date-range Recording fetch: \(results.count) recordings")
        return results
    }

    /// Convert a Recording → LocalSearchResult.
    /// Looks up the linked LocalMemory first (for embeddings/metadata).
    /// If none exists, creates a synthetic LocalMemory from the transcript (NOT inserted into SwiftData).
    private func recordingToSearchResult(_ recording: Recording, score: Float, context: ModelContext) -> LocalSearchResult? {
        let recId = recording.id

        // Try to find linked LocalMemory
        let memDescriptor = FetchDescriptor<LocalMemory>(
            predicate: #Predicate { $0.recordingId == recId }
        )
        if let localMemory = try? context.fetch(memDescriptor).first {
            return LocalSearchResult(memory: localMemory, score: score)
        }

        // No linked LocalMemory — build a synthetic one from Recording data
        let transcript = recording.transcription?.text ?? recording.summary?.text ?? ""
        guard !transcript.isEmpty else { return nil }

        let synthetic = LocalMemory(
            timestamp: recording.date,
            title: recording.title,
            rawTranscript: transcript,
            summary: recording.summary?.text
        )
        synthetic.recordingId = recording.id
        // NOT inserted into context — used only as a data carrier for this search result
        return LocalSearchResult(memory: synthetic, score: score)
    }

    // MARK: - Temporal Search

    /// Detect temporal signals in the query and fetch from BOTH Recording and LocalMemory.
    /// Returns results with a fixed relevance score of 0.65.
    func temporalSearch(query: String, context: ModelContext) -> [LocalSearchResult] {
        guard let range = detectDateRange(from: query) else { return [] }
        print("[LocalSearch] Temporal search — from=\(range.from) to=\(range.to)")

        // Fetch from Recording model (same source as History — always complete)
        let recordingResults = recordingsInDateRange(from: range.from, to: range.to, context: context)

        // Also fetch from LocalMemory (may have additional metadata/embeddings)
        let memoryResults = dateRangeSearch(from: range.from, to: range.to, context: context)

        // Merge: deduplicate by recordingId where possible
        var seen = Set<UUID>()
        var merged: [LocalSearchResult] = []
        for r in recordingResults {
            if let rid = r.memory.recordingId { seen.insert(rid) }
            merged.append(r)
        }
        for r in memoryResults {
            if let rid = r.memory.recordingId, seen.contains(rid) { continue }
            merged.append(r)
        }

        print("[LocalSearch] Temporal merged: \(merged.count) total (recordings=\(recordingResults.count), memories=\(memoryResults.count))")
        return merged
    }

    /// Fetch LocalMemory entries within an explicit date window.
    func dateRangeSearch(from: Date, to: Date, context: ModelContext) -> [LocalSearchResult] {
        let descriptor = FetchDescriptor<LocalMemory>(
            predicate: #Predicate { $0.timestamp >= from && $0.timestamp <= to },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        guard let memories = try? context.fetch(descriptor) else { return [] }
        return memories.map { LocalSearchResult(memory: $0, score: 0.65) }
    }

    /// Regex-based temporal signal detection — mirrors quickTemporalParse on the backend.
    /// Returns a (from, to) Date pair when a temporal reference is found, nil otherwise.
    private func detectDateRange(from query: String) -> (from: Date, to: Date)? {
        let lower = query.lowercased()
        let now = Date()
        let cal = Calendar.current

        // Helper: regex test
        func matches(_ pattern: String) -> Bool {
            (try? NSRegularExpression(pattern: pattern, options: .caseInsensitive))?
                .firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) != nil
        }

        // Helper: capture group 1 from first regex match
        func capture1(_ pattern: String) -> String? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let m = re.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
                  m.numberOfRanges > 1,
                  let r = Range(m.range(at: 1), in: lower) else { return nil }
            return String(lower[r])
        }

        // Recency patterns: "last spoken/talked/discussed", "most recent", "latest recording"
        if matches(#"\b(?:last|latest|most\s+recent)\s+(?:spoken|talked|discussed|conversation|recording|chat)"#)
            || matches(#"\bwhat\s+(?:was|did|have)\s+(?:I\s+)?(?:last|recently)\s+(?:spoken|talked|discussed|said|recorded)"#)
            || matches(#"\bwhat\s+was\s+last\s+(?:spoken|talked|said)\s+about"#) {
            return (cal.date(byAdding: .hour, value: -48, to: now)!, now)
        }

        // "yesterday"
        if lower.contains("yesterday") {
            let y = cal.date(byAdding: .day, value: -1, to: now)!
            return (startOfDay(y), endOfDay(y))
        }

        // "today"
        if lower.contains("today") { return (startOfDay(now), now) }

        // "this morning"
        if matches(#"\bthis\s+morning\b"#) {
            var s = cal.startOfDay(for: now); s = cal.date(bySettingHour: 6, minute: 0, second: 0, of: s)!
            var e = cal.startOfDay(for: now); e = cal.date(bySettingHour: 12, minute: 0, second: 0, of: e)!
            return (s, min(now, e))
        }

        // "this afternoon"
        if matches(#"\bthis\s+afternoon\b"#) {
            var s = cal.startOfDay(for: now); s = cal.date(bySettingHour: 12, minute: 0, second: 0, of: s)!
            var e = cal.startOfDay(for: now); e = cal.date(bySettingHour: 18, minute: 0, second: 0, of: e)!
            return (s, min(now, e))
        }

        // "this evening" / "tonight"
        if matches(#"\b(?:this\s+evening|tonight)\b"#) {
            let s = cal.date(bySettingHour: 18, minute: 0, second: 0, of: cal.startOfDay(for: now))!
            return (s, now)
        }

        // "last night"
        if matches(#"\blast\s+night\b"#) {
            let y = cal.date(byAdding: .day, value: -1, to: now)!
            let s = cal.date(bySettingHour: 18, minute: 0, second: 0, of: cal.startOfDay(for: y))!
            return (s, endOfDay(y))
        }

        // "earlier" / "earlier today"
        if matches(#"\bearlier\b"#) {
            return (cal.date(byAdding: .hour, value: -6, to: now)!, now)
        }

        // "the other day"
        if matches(#"\bthe\s+other\s+day\b"#) {
            let from = cal.date(byAdding: .day, value: -3, to: now)!
            let to   = cal.date(byAdding: .day, value: -1, to: now)!
            return (startOfDay(from), endOfDay(to))
        }

        // "recently"
        if matches(#"\brecently\b"#) {
            return (cal.date(byAdding: .hour, value: -24, to: now)!, now)
        }

        // "last few days" / "past few days" / "a few days ago"
        if matches(#"\b(?:last|past)\s+few\s+days\b"#) || matches(#"\ba\s+few\s+days\s+ago\b"#) {
            return (startOfDay(cal.date(byAdding: .day, value: -4, to: now)!), now)
        }

        // "last week"
        if matches(#"\blast\s+week\b"#) && !matches(#"\blast\s+\d+\s+weeks?\b"#) {
            let weekStart = startOfWeek(now, cal: cal)
            let lastStart = cal.date(byAdding: .weekOfYear, value: -1, to: weekStart)!
            let lastEnd   = cal.date(byAdding: .day, value: 6, to: lastStart)!
            return (lastStart, endOfDay(lastEnd))
        }

        // "this week"
        if matches(#"\bthis\s+week\b"#) { return (startOfWeek(now, cal: cal), now) }

        // "last month"
        if matches(#"\blast\s+month\b"#) && !matches(#"\blast\s+\d+\s+months?\b"#) {
            let y = cal.component(.year, from: now)
            let m = cal.component(.month, from: now)
            let prevM = m == 1 ? 12 : m - 1
            let prevY = m == 1 ? y - 1 : y
            let s = cal.date(from: DateComponents(year: prevY, month: prevM, day: 1))!
            // Last day of previous month = first day of current month minus 1 second
            let nextMonthStart = cal.date(from: DateComponents(year: y, month: m, day: 1))!
            let e = cal.date(byAdding: .second, value: -1, to: nextMonthStart)!
            return (s, e)
        }

        // "last N days/hours/weeks/months"
        if let valStr = capture1(#"\blast\s+(\d+)\s+(?:days?|hours?|weeks?|months?)"#),
           let val = Int(valStr),
           let unitMatch = (try? NSRegularExpression(pattern: #"\blast\s+\d+\s+(days?|hours?|weeks?|months?)"#, options: .caseInsensitive))?
               .firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let unitRange = Range(unitMatch.range(at: 1), in: lower) {
            let unit = String(lower[unitRange])
            let from: Date
            if unit.hasPrefix("hour") {
                from = cal.date(byAdding: .hour, value: -val, to: now)!
            } else if unit.hasPrefix("week") {
                from = cal.date(byAdding: .weekOfYear, value: -val, to: now)!
            } else if unit.hasPrefix("month") {
                from = cal.date(byAdding: .month, value: -val, to: now)!
            } else {
                from = cal.date(byAdding: .day, value: -val, to: now)!
            }
            return (from, now)
        }

        // "on the 25th" / "the 25th" / "on 25th" / bare "25th"
        // Requires ordinal suffix OR "on the N" form to avoid false positives on bare numbers
        let dayStr = capture1(#"\b(?:on\s+)?(?:the\s+)?(\d{1,2})(?:st|nd|rd|th)\b"#)
            ?? capture1(#"\bon\s+the\s+(\d{1,2})\b"#)
        if let dayStr = dayStr,
           let day = Int(dayStr), day >= 1 && day <= 31,
           let target = resolveSpecificDay(day, relativeTo: now, cal: cal) {
            return (startOfDay(target), endOfDay(target))
        }

        // Named month + day: "April 25th", "25th of April"
        let monthMap: [String: Int] = [
            "january":1,"february":2,"march":3,"april":4,"may":5,"june":6,
            "july":7,"august":8,"september":9,"october":10,"november":11,"december":12,
            "jan":1,"feb":2,"mar":3,"apr":4,"jun":6,"jul":7,"aug":8,
            "sep":9,"oct":10,"nov":11,"dec":12
        ]
        let monthAlts = monthMap.keys.sorted(by: { $0.count > $1.count }).joined(separator: "|")

        // "April 25" / "April 25th"
        if let re = try? NSRegularExpression(pattern: "\\b(\(monthAlts))\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b", options: .caseInsensitive),
           let m = re.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           m.numberOfRanges > 2,
           let monthRange = Range(m.range(at: 1), in: lower),
           let dayRange = Range(m.range(at: 2), in: lower),
           let monthNum = monthMap[String(lower[monthRange])],
           let day = Int(lower[dayRange]) {
            let y = cal.component(.year, from: now)
            if var date = cal.date(from: DateComponents(year: y, month: monthNum, day: day)) {
                if date > now { date = cal.date(byAdding: .year, value: -1, to: date)! }
                return (startOfDay(date), endOfDay(date))
            }
        }

        // "25th of April"
        if let re = try? NSRegularExpression(pattern: "\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+of\\s+(\(monthAlts))\\b", options: .caseInsensitive),
           let m = re.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           m.numberOfRanges > 2,
           let dayRange = Range(m.range(at: 1), in: lower),
           let monthRange = Range(m.range(at: 2), in: lower),
           let day = Int(lower[dayRange]),
           let monthNum = monthMap[String(lower[monthRange])] {
            let y = cal.component(.year, from: now)
            if var date = cal.date(from: DateComponents(year: y, month: monthNum, day: day)) {
                if date > now { date = cal.date(byAdding: .year, value: -1, to: date)! }
                return (startOfDay(date), endOfDay(date))
            }
        }

        return nil
    }

    // MARK: - Date helpers

    private func resolveSpecificDay(_ day: Int, relativeTo now: Date, cal: Calendar) -> Date? {
        let y = cal.component(.year, from: now)
        let m = cal.component(.month, from: now)
        if let candidate = cal.date(from: DateComponents(year: y, month: m, day: day)),
           candidate <= now {
            return candidate
        }
        let prevM = m == 1 ? 12 : m - 1
        let prevY = m == 1 ? y - 1 : y
        return cal.date(from: DateComponents(year: prevY, month: prevM, day: day))
    }

    private func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func endOfDay(_ date: Date) -> Date {
        var c = DateComponents(); c.day = 1; c.second = -1
        return Calendar.current.date(byAdding: c, to: Calendar.current.startOfDay(for: date)) ?? date
    }

    private func startOfWeek(_ date: Date, cal: Calendar) -> Date {
        let c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: c) ?? date
    }

    // MARK: - Cosine Similarity (vDSP accelerated)

    /// Compute cosine similarity between two vectors using vDSP
    /// Returns value in [-1, 1] where 1 = identical direction
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var magnitudeA: Float = 0
        var magnitudeB: Float = 0

        // vDSP dot product: a · b
        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))

        // vDSP sum of squares: ||a||²
        vDSP_svesq(a, 1, &magnitudeA, vDSP_Length(a.count))

        // vDSP sum of squares: ||b||²
        vDSP_svesq(b, 1, &magnitudeB, vDSP_Length(b.count))

        let denominator = sqrtf(magnitudeA) * sqrtf(magnitudeB)
        guard denominator > 0 else { return 0 }

        return dotProduct / denominator
    }

    // MARK: - Embedding Generation

    /// Call the backend /api/embed endpoint to get an embedding vector
    private func generateEmbedding(text: String) async -> [Float]? {
        do {
            return try await APIService.shared.generateEmbedding(text: text)
        } catch {
            print("[LocalSearch] Failed to generate embedding: \(error)")
            return nil
        }
    }
}
