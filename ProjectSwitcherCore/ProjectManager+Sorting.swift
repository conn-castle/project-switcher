import Foundation

extension ProjectManager {
    // MARK: - Project Sorting

    /// Returns projects sorted and filtered for display.
    ///
    /// - Parameter query: Search query (empty = no filter, just sort by recency)
    /// - Returns: Sorted (and filtered if query non-empty) projects
    public func sortedProjects(query: String) -> [ProjectConfig] {
        let projects = self.projects
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let recencySnapshot = withState { recentProjectIds }

        // Build recency map: projectId -> rank (0 = most recent)
        var recencyRank: [String: Int] = [:]
        for (index, projectId) in recencySnapshot.enumerated() {
            if recencyRank[projectId] == nil {
                recencyRank[projectId] = index
            }
        }

        // Build config order map
        var configOrder: [String: Int] = [:]
        for (index, project) in projects.enumerated() {
            configOrder[project.id] = index
        }

        let noHistoryRank = recencySnapshot.count

        if trimmedQuery.isEmpty {
            // No filter, just sort by recency then config order
            return projects.sorted { a, b in
                let rankA = recencyRank[a.id] ?? noHistoryRank
                let rankB = recencyRank[b.id] ?? noHistoryRank
                if rankA != rankB {
                    return rankA < rankB
                }
                let configA = configOrder[a.id] ?? Int.max
                let configB = configOrder[b.id] ?? Int.max
                return configA < configB
            }
        }

        // Filter and compute fuzzy score (best of name and ID match)
        let matched = projects.compactMap { project -> (project: ProjectConfig, score: Int)? in
            let score = Self.projectScore(project: project, query: trimmedQuery)
            guard score > 0 else { return nil }
            return (project, score)
        }

        // Sort by: score descending, then recency, then config order
        let sorted = matched.sorted { a, b in
            if a.score != b.score {
                return a.score > b.score
            }
            let rankA = recencyRank[a.project.id] ?? noHistoryRank
            let rankB = recencyRank[b.project.id] ?? noHistoryRank
            if rankA != rankB {
                return rankA < rankB
            }
            let configA = configOrder[a.project.id] ?? Int.max
            let configB = configOrder[b.project.id] ?? Int.max
            return configA < configB
        }

        return sorted.map { $0.project }
    }

    /// Returns the best fuzzy match score for a project, checking both name and ID.
    private static func projectScore(project: ProjectConfig, query: String) -> Int {
        let nameScore = FuzzyMatcher.score(query: query, target: project.name)
        let idScore = FuzzyMatcher.score(query: query, target: project.id)
        return max(nameScore, idScore)
    }

}
