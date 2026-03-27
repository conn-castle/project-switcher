import Foundation

/// Fuzzy matching scorer for project search.
///
/// Scores a query against a target string using tiered matching:
/// - Prefix match (1000): query is a prefix of target
/// - Word-boundary acronym (800): query chars match word-boundary chars (e.g., "al" → "Agent Layer")
/// - Consecutive substring (600): query appears as a contiguous substring
/// - Non-consecutive fuzzy (variable): chars match in order with gap penalties
/// - No match (0): query chars cannot be matched in order
///
/// All matching is case-insensitive.
public struct FuzzyMatcher {
    /// Scores how well `query` matches `target`.
    ///
    /// - Parameters:
    ///   - query: The search string (typically short, user-typed).
    ///   - target: The string to match against (e.g., project name or ID).
    /// - Returns: A score ≥ 0. Higher is better. 0 means no match.
    public static func score(query: String, target: String) -> Int {
        guard !query.isEmpty, !target.isEmpty else { return 0 }

        let queryLower = query.lowercased()
        let targetLower = target.lowercased()

        // Tier 1: Exact prefix match (best)
        if targetLower.hasPrefix(queryLower) {
            // Bonus for tighter match (shorter target = more specific)
            return 1000 + max(0, 100 - targetLower.count)
        }

        // Tier 2: Word-boundary acronym match
        let acronymScore = wordBoundaryAcronymScore(query: queryLower, target: targetLower, original: target)
        if acronymScore > 0 {
            return acronymScore
        }

        // Tier 3: Consecutive substring match
        if let range = targetLower.range(of: queryLower) {
            // Bonus for earlier position
            let position = targetLower.distance(from: targetLower.startIndex, to: range.lowerBound)
            return 600 + max(0, 50 - position)
        }

        // Tier 4: Non-consecutive fuzzy match
        return fuzzyScore(query: queryLower, target: targetLower)
    }

    /// Checks if query characters match word-boundary characters in the target.
    ///
    /// Word boundaries are: first character, characters after space/hyphen/underscore/period,
    /// and uppercase characters following a lowercase character (camelCase).
    private static func wordBoundaryAcronymScore(query: String, target: String, original: String) -> Int {
        let boundaryIndices = wordBoundaryIndices(target: target, original: original)
        guard boundaryIndices.count >= query.count else { return 0 }

        let queryChars = Array(query)
        let targetChars = Array(target)
        var queryIdx = 0
        var consecutiveMatches = 0
        var maxConsecutive = 0

        for boundaryIndex in boundaryIndices {
            guard queryIdx < queryChars.count else { break }
            if targetChars[boundaryIndex] == queryChars[queryIdx] {
                queryIdx += 1
                consecutiveMatches += 1
                maxConsecutive = max(maxConsecutive, consecutiveMatches)
            } else {
                consecutiveMatches = 0
            }
        }

        guard queryIdx == queryChars.count else { return 0 }

        // Bonus for consecutive boundary matches and for using more of the boundaries.
        // Capped at 999 to maintain strict tier precedence (prefix floor is 1000).
        let coverageBonus = (queryChars.count * 10) / max(boundaryIndices.count, 1)
        let consecutiveBonus = maxConsecutive * 5
        return min(999, 800 + coverageBonus + consecutiveBonus)
    }

    /// Returns indices of word-boundary characters in the target string.
    private static func wordBoundaryIndices(target: String, original: String) -> [Int] {
        let chars = Array(target)
        let origChars = Array(original)
        var indices: [Int] = []

        for i in 0..<chars.count {
            if i == 0 {
                indices.append(i)
            } else if chars[i - 1] == " " || chars[i - 1] == "-" || chars[i - 1] == "_" || chars[i - 1] == "." {
                indices.append(i)
            } else if i < origChars.count && origChars[i].isUppercase && origChars[i - 1].isLowercase {
                // CamelCase boundary (check original case)
                indices.append(i)
            }
        }

        return indices
    }

    /// Scores a non-consecutive fuzzy match.
    ///
    /// Characters must appear in order. Gaps are penalized.
    private static func fuzzyScore(query: String, target: String) -> Int {
        let queryChars = Array(query)
        let targetChars = Array(target)

        var queryIdx = 0
        var matchPositions: [Int] = []

        for (targetIdx, targetChar) in targetChars.enumerated() {
            guard queryIdx < queryChars.count else { break }
            if targetChar == queryChars[queryIdx] {
                matchPositions.append(targetIdx)
                queryIdx += 1
            }
        }

        // All query characters must be matched
        guard queryIdx == queryChars.count else { return 0 }

        // Score based on character coverage and gap penalties
        let coverage = queryChars.count * 100 / max(targetChars.count, 1)

        var gapPenalty = 0
        for i in 1..<matchPositions.count {
            let gap = matchPositions[i] - matchPositions[i - 1] - 1
            gapPenalty += gap * 10
        }

        // First match position penalty (later = worse)
        let positionPenalty = matchPositions.first.map { $0 * 5 } ?? 0

        let raw = 400 + coverage - gapPenalty - positionPenalty
        return max(1, raw) // At least 1 if we matched all chars
    }
}
