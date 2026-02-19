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
        threshold: Float = 0.3,
        context: ModelContext
    ) async -> [LocalSearchResult] {
        print("[LocalSearch] Vector search — query=\"\(query.prefix(50))\", limit=\(limit), threshold=\(threshold)")

        // Step 1: Get query embedding from backend
        guard let queryEmbedding = await generateEmbedding(text: query) else {
            print("[LocalSearch] Embedding generation failed, falling back to keyword search")
            // Fallback to keyword search
            let results = keywordSearch(query: query, limit: limit, context: context)
                .map { LocalSearchResult(memory: $0, score: 0.5) }
            print("[LocalSearch] Keyword fallback returned \(results.count) results")
            return results
        }

        print("[LocalSearch] Query embedding generated (\(queryEmbedding.count) dims)")

        // Step 2: Fetch all memories with embeddings
        let descriptor = FetchDescriptor<LocalMemory>(
            predicate: #Predicate { $0.embeddingData != nil }
        )
        guard let memories = try? context.fetch(descriptor), !memories.isEmpty else {
            print("[LocalSearch] No local memories with embeddings found")
            return []
        }

        print("[LocalSearch] Searching \(memories.count) local memories with vDSP cosine similarity")

        // Step 3: Compute cosine similarity for each memory
        var results: [LocalSearchResult] = []

        for memory in memories {
            guard let memoryEmbedding = memory.embedding else { continue }
            let score = cosineSimilarity(queryEmbedding, memoryEmbedding)
            if score >= threshold {
                results.append(LocalSearchResult(memory: memory, score: score))
            }
        }

        // Step 4: Sort by score and return top-k
        results.sort { $0.score > $1.score }
        let topResults = Array(results.prefix(limit))
        print("[LocalSearch] Found \(results.count) matches above threshold, returning top \(topResults.count) (best score=\(topResults.first?.score ?? 0))")
        return topResults
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
