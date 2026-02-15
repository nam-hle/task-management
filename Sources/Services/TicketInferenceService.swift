import Foundation

struct TicketActivity: Identifiable {
    let id: String
    let ticketID: String?
    let branches: [BranchActivity]

    var totalDuration: TimeInterval {
        branches.reduce(0.0) { $0 + $1.totalDuration }
    }

    var segments: [BranchSegment] {
        branches.flatMap(\.segments).sorted { $0.start < $1.start }
    }
}

enum TicketInferenceService {
    private static let ticketPattern = try! Regex("[A-Z][A-Z0-9]+-\\d+")

    static func inferTickets(
        from branches: [BranchActivity],
        overrides: [TicketOverride],
        excludedProjects: Set<String>,
        unknownPatterns: [String]
    ) -> [TicketActivity] {
        let compiledPatterns = unknownPatterns.compactMap { pattern in
            try? Regex(pattern)
        }

        let overrideMap = Dictionary(
            overrides.map { ("\($0.project)\0\($0.branch)", $0.ticketID) },
            uniquingKeysWith: { _, last in last }
        )

        var ticketGroups: [String: [BranchActivity]] = [:]
        var unknownBranches: [BranchActivity] = []

        for branch in branches {
            // Step 1: Filter excluded projects
            if excludedProjects.contains(branch.project) {
                continue
            }

            // Step 2: Check manual overrides
            let overrideKey = "\(branch.project)\0\(branch.branch)"
            if let overrideTicket = overrideMap[overrideKey] {
                ticketGroups[overrideTicket, default: []].append(branch)
                continue
            }

            // Step 3: Check unknown patterns
            if matchesAny(branch.branch, patterns: compiledPatterns) {
                unknownBranches.append(branch)
                continue
            }

            // Step 4: Regex extraction from branch name
            if let ticket = extractTicketID(from: branch.branch) {
                ticketGroups[ticket, default: []].append(branch)
                continue
            }

            // Step 5: Fallback to unknown
            unknownBranches.append(branch)
        }

        var results: [TicketActivity] = ticketGroups.map { ticket, branches in
            TicketActivity(
                id: ticket,
                ticketID: ticket,
                branches: branches.sorted { $0.totalDuration > $1.totalDuration }
            )
        }
        .sorted { $0.totalDuration > $1.totalDuration }

        if !unknownBranches.isEmpty {
            results.append(
                TicketActivity(
                    id: "__unknown__",
                    ticketID: nil,
                    branches: unknownBranches.sorted {
                        $0.totalDuration > $1.totalDuration
                    }
                )
            )
        }

        return results
    }

    private static func extractTicketID(from branch: String) -> String? {
        guard let match = branch.firstMatch(of: ticketPattern) else {
            return nil
        }
        return String(branch[match.range])
    }

    private static func matchesAny(
        _ value: String, patterns: [Regex<AnyRegexOutput>]
    ) -> Bool {
        patterns.contains { pattern in
            (try? pattern.firstMatch(in: value)) != nil
        }
    }
}
